"""Login items ("Beim Anmelden öffnen", System Settings → Anmeldeobjekte): a copy of an
app's start entry in ~/.config/autostart, marked X-Riptide-Login-Item, so it starts the
same way the dock starts it (in its sandbox). The copy follows its start entry: when that
changes (a new start command), sync refreshes it (sandbox.sync) – before, a login item kept
the command of the day it was added."""
import re
from pathlib import Path

AUTOSTART = Path.home() / ".config/autostart"
MARK = "X-Riptide-Login-Item"
_DROP = re.compile(r"^(Hidden|X-GNOME-Autostart-enabled|OnlyShowIn|NotShowIn|" + MARK + r")\s*=")


def as_login_item(text):
    """A start entry's text as a login item: its main section only, marked."""
    out, in_main = [], False
    for line in text.splitlines():
        if line.startswith("["):
            if in_main:
                out.append(f"{MARK}=true")
            in_main = line.strip() == "[Desktop Entry]"
            if not in_main:
                break  # actions etc. are not needed to start it
        elif in_main and _DROP.match(line):
            continue
        out.append(line)
    if in_main:
        out.append(f"{MARK}=true")
    return "\n".join(out) + "\n"


def is_login_item(path):
    try:
        return any(line.strip() == f"{MARK}=true" for line in path.read_text(encoding="utf-8").splitlines())
    except OSError:
        return False


def refresh(entry_dirs):
    """Every login item again from its app's start entry now (the first found in
    entry_dirs); a switched-off one (Hidden=true) stays off."""
    if not AUTOSTART.is_dir():
        return
    for item in sorted(AUTOSTART.glob("*.desktop")):
        if not is_login_item(item):
            continue
        source = next((d / item.name for d in entry_dirs if (d / item.name).is_file()), None)
        if source is None:
            continue
        text = as_login_item(source.read_text(encoding="utf-8"))
        if re.search(r"(?m)^Hidden\s*=\s*true", item.read_text(encoding="utf-8")):
            text = text.replace("[Desktop Entry]\n", "[Desktop Entry]\nHidden=true\n", 1)
        if item.read_text(encoding="utf-8") != text:
            tmp = item.with_name(f".{item.name}.tmp")
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(item)
