#!/usr/bin/env python3
"""Default apps for System Settings → Standard-Apps (JSON on stdout).

    default-apps.py                  every category: its default app and the apps that can open it
    default-apps.py set <key> <app>  make <app> (desktop id) the default for all types of <key>

Writes ~/.config/mimeapps.list in place (it is a link into ~/dotfiles; gio and xdg-mime
would replace the link with a plain file).
"""

import json
import os
import subprocess
import sys
from pathlib import Path

# key, label, file types (the first one decides which apps are offered)
CATEGORIES = [
    ("browser", "Webbrowser", ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"]),
    ("mail", "E-Mail", ["x-scheme-handler/mailto"]),
    ("files", "Ordner", ["inode/directory"]),
    ("pdf", "PDF-Dokumente", ["application/pdf"]),
    ("images", "Bilder", ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif", "image/avif",
                          "image/svg+xml", "image/tiff", "image/bmp"]),
    ("music", "Musik", ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus", "audio/wav",
                        "audio/x-wav", "audio/mp4", "audio/x-m4a", "audio/aac"]),
    ("video", "Videos", ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
                         "video/mpeg", "video/ogg"]),
    ("text", "Textdateien", ["text/plain"]),
    ("archive", "Archive", ["application/zip", "application/x-tar", "application/gzip", "application/x-7z-compressed",
                            "application/x-compressed-tar", "application/x-xz-compressed-tar", "application/vnd.rar"]),
]

MIMEAPPS = (Path.home() / ".config/mimeapps.list").resolve()


def gio(mime):
    """(default app, [apps that can open it]) as gio sees it."""
    out = subprocess.run(["gio", "mime", mime], capture_output=True, text=True,
                         env=dict(os.environ, LC_ALL="C")).stdout
    default, apps = "", []
    for line in out.splitlines():
        if line.startswith("Default application for"):
            default = line.rsplit(":", 1)[-1].strip()
        elif line.startswith("\t"):
            app = line.strip()
            if app not in apps:
                apps.append(app)
    return default, apps


def listing():
    result = []
    for key, label, types in CATEGORIES:
        default, apps = gio(types[0])
        if default and default not in apps:
            apps.insert(0, default)
        result.append({"key": key, "label": label, "default": default, "apps": apps})
    return result


def set_default(key, app):
    types = next((t for k, _, t in CATEGORIES if k == key), None)
    if types is None or not app.endswith(".desktop"):
        sys.exit("unknown category or app")

    lines = MIMEAPPS.read_text(encoding="utf-8").splitlines() if MIMEAPPS.exists() else []
    if "[Default Applications]" not in lines:
        lines += ["[Default Applications]"]
    start = lines.index("[Default Applications]") + 1
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("[")), len(lines))
    section = [l for l in lines[start:end] if l.split("=", 1)[0] not in types]
    section += [f"{t}={app}" for t in types]
    lines[start:end] = section

    tmp = MIMEAPPS.with_name("." + MIMEAPPS.name + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    tmp.replace(MIMEAPPS)  # the real file inside ~/dotfiles, the link stays


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "set":
        set_default(sys.argv[2], sys.argv[3])
    else:
        print(json.dumps(listing()))
