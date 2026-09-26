"""Time Machine, like on a Mac: two kinds of earlier versions of your files.

  on this computer   hourly snapshots of /home (snapper config "home", system/setup-os.sh):
                     the last 24 hours, 7 days, 4 weeks, 6 months – instant, but on the same disk
  on a backup disk   backups to an external drive with restic: encrypted (the password is
                     kept in the keyring), only what changed is copied; kept like on a Mac:
                     hourly for 24 hours, daily for a month, weekly after that

Settings (settings.json "timemachine"): volume {uuid, name}, schedule hourly|daily|weekly|
manual, exclude [paths], keep {hourly, daily, weekly}. State (last backup, progress, errors):
~/.local/state/macos/timemachine.json – System Settings → Time Machine shows it.
The backup runs as riptide-backup.service (timer: hourly; also when the disk is plugged in),
does nothing unless due, and never needs root.

    riptide-timemachine status              JSON for System Settings
    riptide-timemachine volumes             external drives that can take backups
    riptide-timemachine setup <uuid>        password from stdin: a new or existing backup on it
                                            (prints the volume; System Settings stores it)
    riptide-timemachine forget-volume       forget its password (the backups stay on the disk)
    riptide-timemachine backup [--if-due]   back up now (--if-due: only when the schedule says so)
    riptide-timemachine browse <point>      open an earlier version in Finder (local:N or backup:ID)
    riptide-timemachine close               unmount the browsed backup
"""

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
SETTINGS = HOME / ".config/macos/settings.json"
STATE = HOME / ".local/state/macos/timemachine.json"
MOUNT = HOME / ".local/state/macos/timemachine-backup"   # restic mount for browsing
SNAPSHOTS = Path("/home/.snapshots")
ALWAYS_EXCLUDED = ["~/.cache", "~/.local/share/Trash", "~/.local/state/macos/timemachine-backup"]  # never backed up
DEFAULT_KEEP = {"hourly": 24, "daily": 31, "weekly": 520}
EVERY = {"hourly": 3600, "daily": 86400, "weekly": 7 * 86400}
PRUNE_EVERY = 7 * 86400  # freeing space on the disk is slow: once a week


def settings():
    try:
        return json.loads(SETTINGS.read_text()).get("timemachine", {})
    except (OSError, ValueError):
        return {}


def state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(**changes):
    s = state()
    s.update(changes)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(s, indent=1))
    tmp.replace(STATE)


def run(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, **kw)


def notify(title, body, critical=False):
    subprocess.run(["notify-send", "-a", "System", "-i", "", *(["-u", "critical"] if critical else []), title, body])


# ---------------------------------------------------------------- the backup disk

def external_volumes():
    """Mounted file systems on external drives (USB, removable)"""
    out = run(["lsblk", "-J", "-b", "-o", "NAME,UUID,LABEL,MOUNTPOINT,SIZE,FSAVAIL,FSTYPE,TRAN,HOTPLUG,RM,MODEL"]).stdout
    found = []

    def walk(dev, parent):
        external = dev.get("hotplug") or dev.get("rm") or dev.get("tran") in ("usb", "ieee1394") or \
            (parent and (parent.get("hotplug") or parent.get("rm") or parent.get("tran") in ("usb", "ieee1394")))
        if external and dev.get("mountpoint") and dev.get("uuid") and dev.get("fstype") not in ("swap", None):
            found.append({"uuid": dev["uuid"], "name": dev.get("label") or (parent or dev).get("model") or dev["name"],
                          "mount": dev["mountpoint"], "size": int(dev.get("size") or 0),
                          "free": int(dev.get("fsavail") or 0), "fs": dev.get("fstype")})
        for child in dev.get("children", []):
            walk(child, dev if parent is None else parent)

    try:
        for dev in json.loads(out).get("blockdevices", []):
            walk(dev, None)
    except ValueError:
        pass
    return found


def volume_mount(uuid):
    return next((v["mount"] for v in external_volumes() if v["uuid"] == uuid), None)


def repo_of(mount):
    return str(Path(mount) / "riptide-backup" / socket.gethostname())


def restic_env(uuid):
    env = dict(os.environ)
    env["RESTIC_PASSWORD_COMMAND"] = f"secret-tool lookup service riptide-backup volume {uuid}"
    env.pop("RESTIC_PASSWORD", None)
    return env


def restic(uuid, mount, *args, **kw):
    return subprocess.run(["restic", "-r", repo_of(mount), *args], env=restic_env(uuid), capture_output=True,
                          text=True, **kw)


# ---------------------------------------------------------------- commands

def setup(uuid):
    """A new backup on the disk – or the existing one, when its password fits"""
    password = sys.stdin.read().rstrip("\n")
    if len(password) < 8:
        return fail("Das Passwort braucht mindestens 8 Zeichen.")
    mount = volume_mount(uuid)
    if not mount:
        return fail("Das Laufwerk ist nicht angeschlossen.")
    p = subprocess.run(["secret-tool", "store", "--label", "Time Machine – Sicherungsvolume",
                        "service", "riptide-backup", "volume", uuid], input=password, text=True, capture_output=True)
    if p.returncode != 0:
        return fail("Das Passwort ließ sich nicht im Schlüsselbund speichern.")
    repo = Path(repo_of(mount))
    if (repo / "config").exists():
        check = restic(uuid, mount, "cat", "config")
        if check.returncode != 0:
            run(["secret-tool", "clear", "service", "riptide-backup", "volume", uuid])
            return fail("Auf dem Laufwerk gibt es schon eine Sicherung mit einem anderen Passwort.")
    else:
        repo.mkdir(parents=True, exist_ok=True)
        init = restic(uuid, mount, "init")
        if init.returncode != 0:
            return fail("Die Sicherung ließ sich nicht anlegen: " + (init.stderr.strip().splitlines() or ["?"])[-1])
    # (System Settings stores it in settings.json – one writer for that file)
    name = next((v["name"] for v in external_volumes() if v["uuid"] == uuid), "Sicherungsvolume")
    print(json.dumps({"ok": True, "volume": {"uuid": uuid, "name": name}}, ensure_ascii=False))


def forget_volume():
    uuid = settings().get("volume", {}).get("uuid")
    if uuid:
        run(["secret-tool", "clear", "service", "riptide-backup", "volume", uuid])
    print(json.dumps({"ok": True}))


def fail(message):
    print(json.dumps({"error": message}, ensure_ascii=False))
    sys.exit(1)


def excludes():
    paths = ALWAYS_EXCLUDED + settings().get("exclude", [])
    return [str(Path(os.path.expanduser(p))) for p in paths]


def backup(if_due):
    tm = settings()
    uuid = tm.get("volume", {}).get("uuid")
    last = state().get("last", 0)
    if not uuid:
        return
    schedule = tm.get("schedule", "hourly")
    if if_due and (schedule == "manual" or time.time() - last < EVERY.get(schedule, 3600) - 300):
        return
    mount = volume_mount(uuid)
    if not mount:
        # like a Mac: after a while without a backup, a reminder (once a day)
        s = state()
        if last and time.time() - last > 7 * 86400 and time.time() - s.get("reminded", 0) > 86400:
            notify("Keine Sicherung seit " + str(int((time.time() - last) // 86400)) + " Tagen",
                   f"Schließe „{tm['volume'].get('name', 'dein Sicherungsvolume')}“ an, damit Time Machine sichern kann.")
            save_state(reminded=time.time())
        return
    save_state(running=True, progress=0, error="", started=time.time())
    argv = ["restic", "-r", repo_of(mount), "backup", "--json", "--exclude-caches", "--one-file-system",
            "--tag", "riptide", str(HOME)]
    for path in excludes():
        argv += ["--exclude", path]
    proc = subprocess.Popen(argv, env=restic_env(uuid), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    summary, shown = {}, 0
    for line in proc.stdout:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("message_type") == "status" and time.time() - shown > 1:
            shown = time.time()
            save_state(progress=msg.get("percent_done", 0), bytesDone=msg.get("bytes_done", 0),
                       bytesTotal=msg.get("total_bytes", 0), remaining=msg.get("seconds_remaining", 0))
        elif msg.get("message_type") == "summary":
            summary = msg
    err = proc.stderr.read()
    code = proc.wait()
    # 0 = done, 3 = done but some files could not be read (they are named in err)
    if code not in (0, 3):
        line = (err.strip().splitlines() or ["unbekannter Fehler"])[-1]
        save_state(running=False, error=line)
        notify("Time Machine konnte nicht sichern", line, critical=True)
        return
    save_state(running=False, progress=1, last=time.time(), error="" if code == 0 else "Einige Dateien waren nicht lesbar.",
               added=summary.get("data_added", 0), files=summary.get("total_files_processed", 0))
    keep = {**DEFAULT_KEEP, **tm.get("keep", {})}
    forget = ["forget", "--tag", "riptide", "--keep-hourly", str(keep["hourly"]), "--keep-daily", str(keep["daily"]),
              "--keep-weekly", str(keep["weekly"])]
    if time.time() - state().get("pruned", 0) > PRUNE_EVERY:
        forget.append("--prune")
    p = restic(uuid, mount, *forget)
    if p.returncode == 0 and "--prune" in forget:
        save_state(pruned=time.time())


def local_snapshots():
    out = run(["snapper", "--csvout", "-c", "home", "list", "--columns", "number,date,description,cleanup",
               "--disable-used-space"]).stdout
    found = []
    for row in out.splitlines()[1:]:
        f = row.split(",", 3)
        if len(f) >= 2 and f[0] != "0" and f[1]:
            found.append({"id": f"local:{f[0]}", "date": f[1], "description": f[2] if len(f) > 2 else ""})
    return found


def backups(uuid, mount):
    p = restic(uuid, mount, "snapshots", "--json", "--tag", "riptide", timeout=60)
    try:
        return [{"id": "backup:" + s["short_id"], "date": s["time"][:19].replace("T", " ")} for s in json.loads(p.stdout)]
    except (ValueError, KeyError):
        return []


def status():
    tm = settings()
    volume = tm.get("volume")
    mount = volume_mount(volume["uuid"]) if volume else None
    s = state()
    info = {
        "volume": volume, "mounted": bool(mount), "schedule": tm.get("schedule", "hourly"),
        "exclude": tm.get("exclude", []), "keep": {**DEFAULT_KEEP, **tm.get("keep", {})},
        "state": s, "local": local_snapshots(), "backups": [], "browsing": os.path.ismount(MOUNT),
    }
    if mount:
        usage = shutil.disk_usage(mount)
        info["disk"] = {"free": usage.free, "total": usage.total}
        if "--with-backups" in sys.argv:
            info["backups"] = backups(volume["uuid"], mount)
    print(json.dumps(info, ensure_ascii=False))


def browse(point):
    """An earlier version in Finder: a local snapshot as it is, a backup mounted (FUSE)"""
    kind, _, ident = point.partition(":")
    if kind == "local" and ident.isdigit():
        path = SNAPSHOTS / ident / "snapshot" / HOME.name
        if not path.is_dir():
            return fail("Diesen Snapshot gibt es nicht mehr.")
        subprocess.Popen(["xdg-open", str(path)], start_new_session=True)
        print(json.dumps({"ok": True}))
    elif kind == "backup" and re.fullmatch(r"[0-9a-f]{8}", ident):
        volume = settings().get("volume") or {}
        mount = volume_mount(volume.get("uuid", ""))
        if not mount:
            return fail("Das Sicherungsvolume ist nicht angeschlossen.")
        if not os.path.ismount(MOUNT):
            MOUNT.mkdir(parents=True, exist_ok=True)
            subprocess.Popen(["restic", "-r", repo_of(mount), "mount", "--allow-other=false", str(MOUNT)],
                             env=restic_env(volume["uuid"]), start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(60):
                if (MOUNT / "ids").is_dir():
                    break
                time.sleep(0.5)
        target = MOUNT / "ids" / ident / str(HOME).lstrip("/")
        subprocess.Popen(["xdg-open", str(target if target.exists() else MOUNT / "ids" / ident)], start_new_session=True)
        print(json.dumps({"ok": True}))
    else:
        fail("Unbekannter Zeitpunkt.")


def close():
    if os.path.ismount(MOUNT):
        run(["fusermount3", "-u", str(MOUNT)])
    print(json.dumps({"ok": True}))


def main():
    a = sys.argv[1:]
    if not a or a[0] == "status":
        status()
    elif a == ["volumes"]:
        print(json.dumps(external_volumes(), ensure_ascii=False))
    elif len(a) == 2 and a[0] == "setup" and re.fullmatch(r"[A-Za-z0-9-]{4,64}", a[1]):
        setup(a[1])
    elif a == ["forget-volume"]:
        forget_volume()
    elif a[0] == "backup":
        backup("--if-due" in a)
    elif len(a) == 2 and a[0] == "browse":
        browse(a[1])
    elif a == ["close"]:
        close()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
