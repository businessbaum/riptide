# Shared helpers for the secure-boot stage scripts. Sourced, not executed.
set -euo pipefail

readonly FILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../files" && pwd)"
readonly CONF=/boot/limine.conf
readonly LUKS_DEV=/dev/disk/by-uuid/YOUR-LUKS-UUID

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFehler: %s\033[0m\n' "$*" >&2; exit 1; }

((EUID == 0)) || die "bitte mit sudo ausführen."

# Copy a file from system/files to its place in /, root-owned.
put() { install -D -o root -g root -m "$1" "$FILES$2" "$2"; echo "  $2"; }

backup_conf() {
    local b="$CONF.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$CONF" "$b"
    echo "  Sicherung: $b"
}

sb_state() { sbctl status --json 2>/dev/null | tr -d ' \n'; }
