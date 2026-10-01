"""Apps that are not in the Arch repositories, from their maker's official release archive
(docs/os-plan.md) – not Flatpak: we install them, we keep them up to date, and they run
in our sandbox like every other app. Which apps and how: data/archive-apps.json.

    archive-app list            the apps with the installed and the newest release (JSON)
    archive-app install <app>   install it, or update it to the newest release
    archive-app update          update every installed app that has a newer release (JSON)
    archive-app remove <app>    remove it (its personal data stays: System Settings → Apps)
    archive-app clean           remove old versions that no running app uses any more

Where:
    ~/.local/share/macos/apps/<app>/                  the program (read-only in its sandbox)
    ~/.local/share/macos/apps/<app>/.riptide-release  what is installed: tag, file, SHA-256
    ~/.local/share/macos/apps/entries/<app>.desktop   its start entry (app-sandbox --sync
                                                      makes the sandboxed one from it)
Updating: the newest release of the GitHub project (api.github.com, HTTPS). The file must
match the SHA-256 that GitHub gives for it; it is unpacked next to the installed version
(no paths out of the folder, no devices) and swapped in with one rename. A running app
keeps its old files – its sandbox holds them – until it quits; `clean` removes them once
no sandbox of the app runs. The app's own updater is switched off (policies.json): its
folder is read-only for it, so a hijacked app cannot rewrite itself.
"""

import ctypes
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

from desktop_shell import paths

HOME = Path.home()
CONFIG = paths.DATA / "archive-apps.json"
APPS = HOME / ".local/share/macos/apps"
ENTRIES = APPS / "entries"
RELEASE = ".riptide-release"
MAX_SIZE = 1024 ** 3  # no release archive is bigger than 1 GB
TAG = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
APP = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")


class ArchiveError(Exception):
    """Something the user should hear about."""


def specs():
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in data.items() if not k.startswith("_") and APP.match(k)}


def spec_of(app):
    spec = specs().get(app)
    if not spec:
        raise ArchiveError(f"„{app}“ ist keine App aus einem Release-Archiv.")
    return spec


def installed(app):
    """What is installed ({"tag", "asset", "sha256"}), or None"""
    try:
        return json.loads((APPS / app / RELEASE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- the newest release

def _get(url, timeout=30):
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                                   "User-Agent": "riptide-archive-apps"})
    return urllib.request.urlopen(request, timeout=timeout)


def latest(spec):
    """The newest release: {"tag", "url", "sha256", "size"}"""
    repo = spec["repo"]
    try:
        with _get(f"https://api.github.com/repos/{repo}/releases/latest") as r:
            release = json.load(r)
    except (OSError, ValueError) as e:
        raise ArchiveError(f"Keine Verbindung zu GitHub ({e}).")
    tag = release.get("tag_name", "")
    if not TAG.match(tag):
        raise ArchiveError("GitHub nennt keine gültige Version.")
    asset = next((a for a in release.get("assets", []) if a.get("name") == spec["asset"]), None)
    if not asset:
        raise ArchiveError(f"Die Version {tag} hat keine Datei „{spec['asset']}“.")
    url = asset.get("browser_download_url", "")
    digest = asset.get("digest") or ""
    if not url.startswith(f"https://github.com/{repo}/releases/download/"):
        raise ArchiveError("Die Download-Adresse liegt nicht beim Projekt.")
    if not re.match(r"^sha256:[0-9a-f]{64}$", digest):
        raise ArchiveError("GitHub nennt keine Prüfsumme für die Datei – sie wird nicht installiert.")
    return {"tag": tag, "url": url, "sha256": digest[7:], "size": asset.get("size", 0)}


# ---------------------------------------------------------------- installing

def _download(url, target, sha256):
    digest = hashlib.sha256()
    size = 0
    try:
        with _get(url, timeout=60) as r, open(target, "wb") as f:
            while chunk := r.read(1 << 20):
                size += len(chunk)
                if size > MAX_SIZE:
                    raise ArchiveError("Die Datei ist unerwartet groß – abgebrochen.")
                digest.update(chunk)
                f.write(chunk)
    except OSError as e:
        raise ArchiveError(f"Download fehlgeschlagen ({e}).")
    if digest.hexdigest() != sha256:
        raise ArchiveError("Die Datei stimmt nicht mit GitHubs Prüfsumme überein – sie wird nicht installiert.")


def _swap(new, target):
    """Put `new` in the place of `target` in one step (renameat2 RENAME_EXCHANGE); the old
    version ends up at `new`'s path. Without an old version a plain rename."""
    if not target.exists():
        new.rename(target)
        return None
    libc = ctypes.CDLL(None, use_errno=True)
    at_fdcwd, rename_exchange = -100, 2
    if libc.renameat2(at_fdcwd, os.fsencode(new), at_fdcwd, os.fsencode(target), rename_exchange) != 0:
        raise ArchiveError(f"Die neue Version ließ sich nicht einsetzen ({os.strerror(ctypes.get_errno())}).")
    return new  # now the old version


def write_entry(app, spec):
    """The app's start entry: its program in its folder; app-sandbox --sync makes the
    sandboxed entry the desktop uses from it."""
    folder = APPS / app
    fields = {"Type": "Application", "Name": spec["name"], "Exec": f"{folder / spec['program']} %u",
              "Icon": str(folder / spec["icon"]), "StartupWMClass": spec.get("wm_class", app),
              "Terminal": "false", **spec.get("entry", {})}
    lines = ["[Desktop Entry]"] + [f"{k}={v}" for k, v in fields.items()]
    ENTRIES.mkdir(parents=True, exist_ok=True)
    path = ENTRIES / f"{app}.desktop"
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text("# Written by archive-app from archive-apps.json – do not edit.\n" + "\n".join(lines) + "\n",
                   encoding="utf-8")
    tmp.replace(path)


def install(app, log=print):
    spec = spec_of(app)
    newest = latest(spec)
    have = installed(app)
    if have and have.get("tag") == newest["tag"] and (APPS / app / spec["program"]).is_file():
        write_entry(app, spec)
        return {"app": app, "tag": newest["tag"], "changed": False}

    APPS.mkdir(parents=True, exist_ok=True)
    stamp = f"{int(time.time())}"
    download = APPS / f".{app}.download-{stamp}"
    unpacked = APPS / f".{app}.new-{stamp}"
    try:
        log(f"{app}: {newest['tag']} wird geladen …")
        _download(newest["url"], download, newest["sha256"])
        log(f"{app}: geprüft, wird entpackt …")
        unpacked.mkdir()
        with tarfile.open(download) as archive:
            archive.extractall(unpacked, filter="data")  # no absolute paths, links out, devices
        folder = unpacked / spec["folder"]
        program = folder / spec["program"]
        if not program.is_file() or not os.access(program, os.X_OK):
            raise ArchiveError(f"Im Archiv fehlt das Programm „{spec['folder']}/{spec['program']}“.")
        if spec.get("policies"):
            (folder / "distribution").mkdir(exist_ok=True)
            (folder / "distribution/policies.json").write_text(
                json.dumps({"policies": spec["policies"]}, indent=2) + "\n", encoding="utf-8")
        (folder / RELEASE).write_text(json.dumps({"tag": newest["tag"], "asset": spec["asset"],
                                                  "sha256": newest["sha256"], "installed": int(time.time())}) + "\n",
                                      encoding="utf-8")
        old = _swap(folder, APPS / app)
        if old:
            old.rename(APPS / f".{app}.old-{stamp}")
    finally:
        download.unlink(missing_ok=True)
        shutil.rmtree(unpacked, ignore_errors=True)
    write_entry(app, spec)
    clean(app)
    return {"app": app, "tag": newest["tag"], "from": (have or {}).get("tag"), "changed": True}


def update(log=print):
    """Every installed app to its newest release; [{app, tag, from, changed} | {app, error}]"""
    done = []
    for app in specs():
        if installed(app) is None:
            continue
        try:
            done.append(install(app, log))
        except ArchiveError as e:
            done.append({"app": app, "error": str(e)})
    clean()  # versions left from before, once their app has quit
    return done


def clean(app=None):
    """Old versions and leftovers, once no sandbox of the app runs (it may still use them)"""
    from desktop_shell import sandbox

    busy = {a for a, _instance, folder in sandbox.instances() if sandbox.running(folder)}
    for path in APPS.glob(".*"):
        m = re.match(r"^\.(.+)\.(old|new|download)-\d+$", path.name)
        if not m or (app and m.group(1) != app) or (m.group(2) == "old" and m.group(1) in busy):
            continue
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)


def remove(app):
    """The program and its start entry; not while it runs (its sandbox uses the files)"""
    from desktop_shell import sandbox

    spec_of(app)
    if any(a == app and sandbox.running(folder) for a, _instance, folder in sandbox.instances()):
        raise ArchiveError("Die App läuft noch – bitte zuerst beenden.")
    shutil.rmtree(APPS / app, ignore_errors=True)
    (ENTRIES / f"{app}.desktop").unlink(missing_ok=True)
    sandbox.sync()  # its sandboxed start entry goes too
    clean(app)
    return {"app": app, "removed": True}


def main():
    args = sys.argv[1:]
    try:
        if args == ["list"]:
            result = []
            for app, spec in specs().items():
                item = {"app": app, "name": spec["name"], "installed": (installed(app) or {}).get("tag")}
                try:
                    item["newest"] = latest(spec)["tag"]
                except ArchiveError as e:
                    item["error"] = str(e)
                result.append(item)
            print(json.dumps(result, ensure_ascii=False))
        elif len(args) == 2 and args[0] == "install":
            print(json.dumps(install(args[1], log=lambda m: print(m, file=sys.stderr)), ensure_ascii=False))
        elif args == ["update"]:
            print(json.dumps(update(log=lambda m: print(m, file=sys.stderr)), ensure_ascii=False))
        elif len(args) == 2 and args[0] == "remove":
            print(json.dumps(remove(args[1]), ensure_ascii=False))
        elif args == ["clean"]:
            clean()
        else:
            sys.exit(__doc__)
    except ArchiveError as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
