#!/usr/bin/env python3
"""Printers and scanners for System Settings → Drucker & Scanner and the app "Drucker"
(the print queue), like on a Mac. Talks to CUPS (lpadmin, ipptool against
ipp://localhost) and finds devices in the home network through Avahi (driverless IPP,
AirPrint; scanners through SANE's eSCL/WSD backend). Output is JSON.

    printers.py list                    the printers: state, supplies, jobs waiting, default
    printers.py discover                printers in the network and on USB not added yet
    printers.py add <uri> <name> [loc]  add one (IPP Everywhere: no driver needed)
    printers.py remove <printer>
    printers.py default <printer>       default printer of this user
    printers.py jobs <printer>          jobs not done yet
    printers.py cancel|hold|release <printer> <job id>
    printers.py pause|resume <printer>  stop/start printing (the queue keeps jobs)
    printers.py test <printer>          print a test page
    printers.py scanners                scanners (SANE)

Errors: {"error": "text"} and exit code 1.
"""

import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.parse

CUPS = "ipp://localhost"
NAME = re.compile(r"^[A-Za-z0-9_-]{1,127}$")
URI = re.compile(r"^(ipps?|dnssd|usb|ipp-usb)://[^\s'\"`$;|&<>]+$")
STATES = {3: "idle", 4: "printing", 5: "stopped"}
JOB_STATES = {3: "pending", 4: "held", 5: "printing", 6: "stopped", 7: "canceled", 8: "aborted", 9: "completed"}

PRINTER_ATTRS = ("printer-name,printer-info,printer-location,printer-make-and-model,device-uri,printer-state,"
                 "printer-state-reasons,printer-state-message,printer-is-accepting-jobs,queued-job-count,"
                 "marker-names,marker-levels,marker-colors,marker-types")
JOB_ATTRS = "job-id,job-name,job-state,job-state-reasons,job-originating-user-name,job-k-octets,time-at-creation,job-impressions-completed,job-media-sheets-completed"


def fail(message):
    print(json.dumps({"error": message}, ensure_ascii=False))
    sys.exit(1)


def run(argv, timeout=30):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                           env=dict(os.environ, LANG="C", LC_ALL="C"))
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def ipp(uri, operation, attrs, extra=""):
    """One IPP request through ipptool; returns the response's attribute groups as dicts"""
    test = f"""{{
    OPERATION {operation}
    GROUP operation-attributes-tag
    ATTR charset attributes-charset utf-8
    ATTR naturalLanguage attributes-natural-language de
    ATTR uri printer-uri {uri}
    ATTR name requesting-user-name {os.environ.get("USER", "")}
    {extra}
    ATTR keyword requested-attributes {attrs}
}}
"""
    with tempfile.NamedTemporaryFile("w", suffix=".test") as f:
        f.write(test)
        f.flush()
        try:
            out = subprocess.run(["ipptool", "-X", "-T", "10", uri, f.name], capture_output=True, timeout=20).stdout
        except (OSError, subprocess.TimeoutExpired):
            return None
    try:
        plist = plistlib.loads(out)
    except Exception:
        return None
    groups = []
    for t in plist.get("Tests", []):
        for group in t.get("ResponseAttributes", []):
            groups.append(group)
    return groups


def as_list(v):
    return v if isinstance(v, list) else ([] if v is None else [v])


def cups_running():
    return run(["lpstat", "-r"])[1].strip() == "scheduler is running"


def default_printer():
    code, out, _ = run(["lpstat", "-d"])
    m = re.search(r"destination: (\S+)", out)
    return m.group(1) if m else ""


# ---------------------------------------------------------------- printers

def printers():
    if not cups_running():
        return {"printers": [], "default": "", "running": False}
    groups = ipp(CUPS + "/", "CUPS-Get-Printers", PRINTER_ATTRS) or []
    found = []
    default = default_printer()
    for g in groups:
        name = g.get("printer-name")
        if not name:
            continue
        colours = as_list(g.get("marker-colors"))
        levels = as_list(g.get("marker-levels"))
        supplies = [{"name": n, "level": levels[i] if i < len(levels) else -1,
                     "colour": colours[i].split("#")[1] if i < len(colours) and "#" in colours[i] else "888888"}
                    for i, n in enumerate(as_list(g.get("marker-names")))]
        reasons = [r for r in as_list(g.get("printer-state-reasons")) if r != "none"]
        found.append({
            "name": name,
            "info": g.get("printer-info") or name,
            "location": g.get("printer-location") or "",
            # "HP OfficeJet Pro 9010 series, driverless, cups-filters 2.0.1" → the printer
            "model": re.sub(r",\s*(driverless|IPP Everywhere).*$", "", g.get("printer-make-and-model") or ""),
            "uri": g.get("device-uri") or "",
            "state": STATES.get(g.get("printer-state"), "idle"),
            "reasons": reasons,
            "offline": any(r.startswith(("offline", "connecting-to-device")) for r in reasons),
            "message": g.get("printer-state-message") or "",
            "accepting": g.get("printer-is-accepting-jobs", True),
            "jobs": g.get("queued-job-count", 0),
            "supplies": supplies,
            "default": name == default,
        })
    return {"printers": found, "default": default, "running": True}


def jobs(printer):
    groups = ipp(f"{CUPS}/printers/{printer}", "Get-Jobs", JOB_ATTRS, "ATTR keyword which-jobs not-completed") or []
    found = []
    for g in groups:
        if "job-id" not in g:
            continue
        found.append({
            "id": g["job-id"],
            "name": g.get("job-name") or "Ohne Titel",
            "state": JOB_STATES.get(g.get("job-state"), "pending"),
            "user": g.get("job-originating-user-name", ""),
            "size": g.get("job-k-octets", 0),
            "created": g.get("time-at-creation", 0),
            "pages": g.get("job-impressions-completed", 0),
        })
    return found


# ---------------------------------------------------------------- finding new ones

def unescape(s):
    """avahi-browse -p escapes like \\032 (decimal)"""
    return re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1))), s)


def discover():
    known = {p["uri"] for p in printers()["printers"]}
    found = {}
    for service, scheme in (("_ipps._tcp", "ipps"), ("_ipp._tcp", "ipp")):
        _, out, _ = run(["avahi-browse", "-rpt", "-k", service], timeout=8)
        for line in out.splitlines():
            f = line.split(";")
            if len(f) < 10 or f[0] != "=" or f[2] != "IPv4":
                continue
            name, host, port = unescape(f[3]), f[6], f[8]
            txt = dict(re.findall(r'"([^"=]+)=([^"]*)"', f[9]))
            rp = txt.get("rp", "ipp/print")
            uri = f"{scheme}://{host}:{port}/{rp}"
            key = txt.get("UUID") or name
            # prefer ipps (encrypted) when a printer offers both
            if key in found:
                continue
            found[key] = {"name": name, "uri": uri, "model": txt.get("ty", ""), "location": txt.get("note", ""),
                          "kind": "network", "driverless": "URF" in txt or "pdl" in txt}
    # USB (needs CUPS running)
    _, out, _ = run(["lpinfo", "--include-schemes", "usb", "-v"], timeout=15)
    for line in out.splitlines():
        m = re.match(r"^direct (usb://\S+)", line)
        if m:
            uri = m.group(1)
            model = urllib.parse.unquote(uri.split("://")[1].split("?")[0]).replace("/", " ")
            found[uri] = {"name": model, "uri": uri, "model": model, "location": "USB", "kind": "usb", "driverless": True}
    return [p for p in found.values() if p["uri"] not in known]


def queue_name(name):
    """A CUPS queue name from what the printer calls itself: HP_OfficeJet_Pro_9010"""
    q = re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_")[:60]
    return q or "Drucker"


def add(uri, name, location):
    if not URI.match(uri):
        fail("Ungültige Adresse des Druckers.")
    if not cups_running():
        fail("Der Druckdienst läuft nicht (einmalig: sudo ~/dotfiles/system/setup-os.sh).")
    queue = queue_name(name)
    argv = ["lpadmin", "-p", queue, "-E", "-v", uri, "-m", "everywhere", "-D", name[:127]]
    if location:
        argv += ["-L", location[:127]]
    code, out, err = run(argv, timeout=60)
    if code != 0:
        fail("Der Drucker ließ sich nicht hinzufügen: " + (err or out).strip().splitlines()[-1:][0] if (err or out).strip()
             else "Der Drucker ließ sich nicht hinzufügen.")
    # the first printer becomes the default
    if not default_printer():
        run(["lpoptions", "-d", queue])
    print(json.dumps({"added": queue}))


def simple(argv, what):
    code, out, err = run(argv)
    if code != 0:
        fail(f"{what}: " + ((err or out).strip() or "unbekannter Fehler"))
    print(json.dumps({"ok": True}))


def scanners():
    _, out, _ = run(["scanimage", "-L"], timeout=20)
    found = []
    for m in re.finditer(r"device `([^']+)' is a (.+)", out):
        # "eSCL HP OfficeJet Pro 9010 ip=…" → the scanner's name
        name = re.sub(r"^(eSCL|WSD)\s+|\s+ip=\S+$", "", m.group(2).strip())
        found.append({"device": m.group(1), "name": name})
    return found


def main():
    a = sys.argv[1:]
    if a == ["list"]:
        print(json.dumps(printers(), ensure_ascii=False))
    elif a == ["discover"]:
        print(json.dumps(discover(), ensure_ascii=False))
    elif a == ["scanners"]:
        print(json.dumps(scanners(), ensure_ascii=False))
    elif len(a) in (3, 4) and a[0] == "add":
        add(a[1], a[2], a[3] if len(a) == 4 else "")
    elif len(a) == 2 and NAME.match(a[1]) and a[0] in ("remove", "default", "jobs", "pause", "resume", "test"):
        p = a[1]
        if a[0] == "jobs":
            print(json.dumps(jobs(p), ensure_ascii=False))
        elif a[0] == "remove":
            simple(["lpadmin", "-x", p], "Entfernen fehlgeschlagen")
        elif a[0] == "default":
            simple(["lpoptions", "-d", p], "Standarddrucker nicht geändert")
        elif a[0] == "pause":
            simple(["cupsdisable", p], "Anhalten fehlgeschlagen")
        elif a[0] == "resume":
            simple(["cupsenable", p], "Fortsetzen fehlgeschlagen")
        elif a[0] == "test":
            simple(["lp", "-d", p, "-t", "Testseite", "/usr/share/cups/data/testprint"], "Testseite nicht gedruckt")
    elif len(a) == 3 and NAME.match(a[1]) and a[2].isdigit() and a[0] in ("cancel", "hold", "release"):
        job = f"{a[1]}-{a[2]}"
        if a[0] == "cancel":
            simple(["cancel", job], "Abbrechen fehlgeschlagen")
        else:
            simple(["lp", "-i", job, "-H", "hold" if a[0] == "hold" else "resume"], "Nicht geändert")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
