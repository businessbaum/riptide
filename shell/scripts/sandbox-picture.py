#!/usr/bin/env python3
"""Copy a picture an app in our sandbox names by a path in its own /tmp.

    sandbox-picture.py APP RELATIVE_PATH DEST

Chromium writes the sender's profile picture of a notification to /tmp/… and names only
the path; that /tmp is the sandbox's – here it is $XDG_RUNTIME_DIR/macos-sandbox/APP/tmp –
and the file goes with the notification. The app chooses the path, so nothing outside its
/tmp may be read: no "..", no links followed (each folder opened with O_NOFOLLOW), a
regular file of at most 4 MB. Exit 0 when DEST was written.
"""
import os
import re
import stat
import sys

LIMIT = 4 * 1024 * 1024


def main():
    app, rel, dest = sys.argv[1:4]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", app) or app in (".", ".."):
        return 1
    parts = [p for p in rel.split("/") if p]
    if not parts or any(p in (".", "..") for p in parts):
        return 1
    base = os.path.join(os.environ["XDG_RUNTIME_DIR"], "macos-sandbox", app, "tmp")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(base, flags | os.O_DIRECTORY)
    try:
        for part in parts[:-1]:
            sub = os.open(part, flags | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = sub
        f = os.open(parts[-1], flags | os.O_NONBLOCK, dir_fd=fd)
    finally:
        os.close(fd)
    with os.fdopen(f, "rb") as src:
        if not stat.S_ISREG(os.fstat(src.fileno()).st_mode):
            return 1
        data = src.read(LIMIT + 1)
    if not data or len(data) > LIMIT:
        return 1
    tmp = dest + ".part"
    with open(tmp, "wb") as out:
        out.write(data)
    os.replace(tmp, dest)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError):
        sys.exit(1)
