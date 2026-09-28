"""One place for everything that went wrong: a report from all sources, to read now and then
and make the system better from it.

    riptide-report              report of the last 24 hours (also written to the file below)
    riptide-report --since 3d   another time span (journalctl syntax: 3d, 12h, "2026-09-26")
    riptide-report --quiet      only write the file (the daily timer)

Written to ~/.local/state/macos/reports/<date>.md (the last 30 are kept).

Sources:
  failed services          systemd, user and system
  crashes                  systemd-coredump
  Hyprland                 config errors and errors in our Lua (hyprland-errors.log)
  shell                    warnings and errors of Quickshell (qs log)
  system services          errors of the user session's services (journal, priority ≤ warning)
  apps                     errors apps printed (their output goes to riptide-session)
  system                   errors of the whole system (journal, priority ≤ error)

Equal messages are counted once: numbers, addresses and times are made alike first
(e.g. "Frame latency is negative: -0.3 ms" and "…: -0.1 ms" are one line).
"""

import datetime
import json
import os
import pwd
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
REPORTS = HOME / ".local/state/macos/reports"
KEEP = 30

# Known noise: harmless, not ours, already explained (keep this list short and say why)
NOISE = [
    # Electron's tray icon answers the question for its icon name with an error
    re.compile(r"StatusNotifierItem.*IconName|error occurred in Get"),
    # Chromium/Electron log chatter in the apps' output
    re.compile(r"Frame latency is negative|Exiting due to channel error"),
    # icon search of AppIcon.qml: each name once per session, the generic icon follows
    re.compile(r"IconImage\.qml.*Cannot open"),
    # desktop PC without battery; no camera plugin needed
    re.compile(r"UPower|libcamera"),
    # sandboxed apps may not make themselves the default app (mimeapps.list is read-only)
    re.compile(r"mimeapps\.list"),
    # sandboxed GTK apps look for the drive services, which stay outside
    re.compile(r"remote volume monitor with dbus name org\.gtk\.vfs"),
    # our sandbox replaces an app's D-Bus start file on purpose (app-sandbox --sync): the bus
    # says it ignores the original
    re.compile(r"Ignoring duplicate name '.*' in service file '/usr/share/+dbus-1/services/"),
    # Chromium/Electron: its own chatter, its tray icon's name taken by a second window
    re.compile(r"rejected by interface blink\.mojom|Failed to get the ownership of org\.freedesktop\.StatusNotifierItem"),
    # the start without password (autologin into the locked session) cannot open the keyring
    # – the password on the lock screen does, right after ("unlocked login keyring"); a text
    # login on a console has no keyring at all
    re.compile(r"(greetd|getty@tty\d+): gkr-pam: (couldn't unlock the login keyring|unable to locate daemon control file)"),
    re.compile(r"gnome-keyring-daemon: (The Secret Service was already initialized|asked to register item .* already registered)"
               r"|discover_other_daemon"),
    # the shell reloaded: its bus connection had told the portal who it is before
    re.compile(r"Failed to register with host portal .*already associated|had owner '' but we thought it was"),
    # hardware and drivers, all working: WLAN (multicast RX), Bluetooth adapter RTL8761BU
    # (before its firmware is loaded), DisplayPort repeaters (LTTPR), Intel TDX (this is AMD)
    re.compile(r"multicast RX registrations are not supported|bluetooth: Failed to set mode: Failed \(0x[0-9a-f]+\)"
               r"|LTTPR|lttpr_caps|TDX not supported|Unable to get io data for Hands-Free Voice gateway"),
    # Bluetooth headphones switched off or out of reach: the adapter keeps trying
    re.compile(r"Hands-Free Voice gateway SDP record: Host is down|bluetooth: No matching connection for device"),
    # the kernel is built without audit: pam_faillock cannot send its audit note (it still counts)
    re.compile(r"pam_faillock\(.*Error sending audit message: Address family not supported"),
    # back in the session after the login screen: the sound server registers Bluetooth MIDI
    # again and hears it still is
    re.compile(r"GattManager1?\.RegisterApplication\(\) failed: .*AlreadyExists"),
    # each crash is listed under "Abstürze" already
    re.compile(r"of user \d+ dumped core\."),
    # while logging out or shutting down: services report their last changes, systemd starts
    # nothing anymore; the Hyprland crash at that moment (see Abstürze) loses its core dump
    re.compile(r"Activation request for '(org\.freedesktop\.nm_dispatcher|org\.bluez)' failed"
               r"|Transaction for sound\.target/start is destructive|io\.systemd\.Login\.NoSuchSession"
               r"|signal-handler\.sh: .*printf|at-spi-dbus-bus\.service: (Main process exited|Failed with result)"
               r"|Failed to send coredump datagram|Owner of volume monitor .* disconnected from the bus"),
    # Claude's test runs (a second Hyprland in its scratch folder)
    re.compile(r"/tmp/claude-\d+/"),
]

# Crashes that are known and not ours to fix (the rest shows one by one, with where it broke)
KNOWN_CRASHES = [
    # every end of Hyprland with two screens (logging out, restarting, the login screen after
    # the password): after everything is closed, while tidying up – nothing is lost
    (re.compile(r"/Hyprland$"), re.compile(r"flushAsyncCommitEvents[\s\S]*__cxa_finalize"),
     "beim Beenden – bekannter Fehler in aquamarine bei zwei Bildschirmen, nichts geht verloren "
     "(github.com/hyprwm/aquamarine/issues/383)"),
    # Claude's check of a config (Hyprland --verify-config) crashes when it cleans up
    (re.compile(r"/Hyprland$"), re.compile(r"CConfigManager11cleanTimers"),
     "Konfigurationsprüfung (Test), nicht die Sitzung"),
]

APP_ERRORS = re.compile(r"\b(ERROR|CRITICAL|FATAL|Traceback|Segmentation fault|segfault|core dumped|"
                        r"Error:|error:|Exception)\b")


def run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def alike(text):
    """A message with its changing parts made equal, so repeats can be counted."""
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    text = re.sub(r"0x[0-9a-fA-F]+", "0x…", text)
    text = re.sub(r"\b\d{2}:\d{2}:\d{2}(\.\d+)?\b", "…", text)
    text = re.sub(r"[-+]?\d+(\.\d+)?", "N", text)
    return text.strip()[:220]


def noise(text):
    return any(p.search(text) for p in NOISE)


def count(lines):
    """[(count, message)], most frequent first."""
    found = {}
    for line in lines:
        if line.strip() and not noise(line):
            key = alike(line)
            found[key] = found.get(key, 0) + 1
    return sorted(((n, m) for m, n in found.items()), key=lambda x: -x[0])


def journal(args, since):
    out = run(["journalctl", "--no-pager", "-o", "json", "--since", since, *args])
    lines = []
    for raw in out.splitlines():
        try:
            entry = json.loads(raw)
        except ValueError:
            continue
        message = entry.get("MESSAGE")
        if isinstance(message, list):  # bytes
            message = bytes(message).decode(errors="replace")
        if not message or not str(message).strip():
            continue
        unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("_SYSTEMD_UNIT") or entry.get("SYSLOG_IDENTIFIER", "?")
        # (first line only: crash reports carry whole stack traces)
        lines.append((unit, entry.get("SYSLOG_IDENTIFIER", ""), str(message).split("\n")[0]))
    return lines


def crashes(since):
    """[(count, text)]: each crash with the program, who ran it and where it broke; known ones
    (KNOWN_CRASHES) counted together with their explanation."""
    out = run(["journalctl", "--no-pager", "-a", "-o", "json", "--since", since,
               "--output-fields=MESSAGE,COREDUMP_EXE,COREDUMP_SIGNAL_NAME,COREDUMP_UID",
               "MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1"])  # systemd-coredump's report
    rows, known = [], {}
    for raw in out.splitlines():
        try:
            entry = json.loads(raw)
        except ValueError:
            continue
        exe = entry.get("COREDUMP_EXE") or "?"
        trace = entry.get("MESSAGE") or ""
        if isinstance(trace, list):
            trace = bytes(trace).decode(errors="replace")
        when = datetime.datetime.fromtimestamp(int(entry.get("__REALTIME_TIMESTAMP", 0)) / 1e6)
        try:
            who = pwd.getpwuid(int(entry.get("COREDUMP_UID"))).pw_name
        except (TypeError, ValueError, KeyError):
            who = "?"
        name = f"{Path(exe).name} ({entry.get('COREDUMP_SIGNAL_NAME') or 'Signal ?'}, {who})"
        why = next((text for exe_re, trace_re, text in KNOWN_CRASHES if exe_re.search(exe) and trace_re.search(trace)), None)
        if why:
            n, last = known.get((name, why), (0, when))
            known[(name, why)] = (n + 1, max(last, when))
            continue
        # where it broke: the first frame of the crashed thread
        frame = re.search(r"^\s*#0\s+\S+\s+(.+)$", trace, re.M)
        rows.append((1, f"{when:%Y-%m-%d %H:%M:%S} {name}: {frame.group(1) if frame else exe}"))
    rows += [(n, f"{name} {why}, zuletzt {last:%Y-%m-%d %H:%M}") for (name, why), (n, last) in known.items()]
    return rows


def sections(since):
    out = []

    # failed services
    failed = [l.split()[0] for l in run(["systemctl", "--user", "--failed", "--no-legend", "--plain"]).splitlines() if l.strip()]
    failed += ["(System) " + l.split()[0] for l in run(["systemctl", "--failed", "--no-legend", "--plain"]).splitlines() if l.strip()]
    out.append(("Fehlgeschlagene Dienste", [(1, f) for f in failed]))

    out.append(("Abstürze", crashes(since)))

    # Hyprland
    hypr = [l for l in run(["hyprctl", "configerrors"]).splitlines() if l.strip()]
    log = HOME / ".local/state/macos/hyprland-errors.log"
    if log.exists():
        cutoff = since_time(since)
        block_time = None
        for line in log.read_text(errors="replace").splitlines():
            m = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})$", line)
            if m:
                block_time = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            elif line.strip() and block_time and block_time >= cutoff:
                hypr.append(line)
    out.append(("Hyprland", count(hypr)))

    # shell
    shell = [l for l in run(["qs", "log"]).splitlines() if re.search(r"\b(WARN|ERROR|FATAL)\b|TypeError|ReferenceError", l)]
    out.append(("Shell (Quickshell, seit ihrem Start)", count(shell)))

    # user services (not the apps' output, which runs through riptide-session)
    # (the apps' output is logged under the name riptide-session, from their own scopes)
    services, apps = [], []
    for unit, ident, message in journal(["--user", "-p", "warning"], since):
        if ident != "riptide-session":
            services.append(f"{unit.removesuffix('.service')}: {message}")
    for unit, ident, message in journal(["--user", "-t", "riptide-session"], since):
        if APP_ERRORS.search(message):
            app = re.sub(r"^app-sandbox-(.+?)-\d+\.scope$", r"\1", unit)
            apps.append(f"{app}: {message}")
    out.append(("Dienste der Sitzung", count(services)))
    out.append(("Apps (ihre Fehlerausgaben)", count(apps)))

    # the whole system
    system = [f"{unit.removesuffix('.service')}: {message}" for unit, _, message in journal(["-p", "err", "--system"], since)]
    out.append(("System", count(system)))
    return out


def since_time(since):
    """journalctl-like time span ("24h", "3d") or date → datetime, for our own log."""
    m = re.fullmatch(r"(\d+)\s*([hd])", since)
    if m:
        hours = int(m.group(1)) * (24 if m.group(2) == "d" else 1)
        return datetime.datetime.now() - datetime.timedelta(hours=hours)
    try:
        return datetime.datetime.fromisoformat(since)
    except ValueError:
        return datetime.datetime.now() - datetime.timedelta(days=1)


def render(since, parts):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    total = sum(sum(n for n, _ in rows) for _, rows in parts)
    lines = [f"# Bericht {now} (seit {since})", "",
             f"{total} Meldungen, gleiche zusammengefasst. Bekanntes Rauschen ist ausgeblendet "
             "(Liste NOISE in ~/.local/lib/desktop_shell/report.py).", ""]
    for title, rows in parts:
        lines.append(f"## {title} ({sum(n for n, _ in rows)})")
        lines.append("")
        if not rows:
            lines.append("nichts")
        for n, message in rows[:40]:
            lines.append(f"- {n}× {message}")
        if len(rows) > 40:
            lines.append(f"- … und {len(rows) - 40} weitere")
        lines.append("")
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    since = "24h"
    if "--since" in args:
        since = args[args.index("--since") + 1]
    journal_since = f"-{since}" if re.fullmatch(r"\d+[hd]", since) else since
    text = render(since, sections(journal_since))

    REPORTS.mkdir(parents=True, exist_ok=True)
    path = REPORTS / (datetime.date.today().isoformat() + ".md")
    path.write_text(text, encoding="utf-8")
    for old in sorted(REPORTS.glob("*.md"))[:-KEEP]:
        old.unlink()
    if "--quiet" not in args:
        print(text)
        print(f"(gespeichert: {path})")
