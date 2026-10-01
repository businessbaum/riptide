"""Where riptide's software lives: one tree, laid out like /usr/lib/riptide (docs/os-plan.md
"System files root-owned") – today this repo, one day the package. Every part of the
software is found from here, never through the home folder; the user's settings and data stay
in the home folder (their paths are where they are used)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # <root>/session/desktop_shell/paths.py
BIN = ROOT / "bin"            # commands
DATA = ROOT / "data"          # knowledge about apps (sandbox.json …), design tokens, entries
SHELL = ROOT / "shell"        # Quickshell: shell, System Settings, App Store, scripts
SANDBOX = ROOT / "sandbox"    # sandbox helpers (built: sandbox/build.sh)
