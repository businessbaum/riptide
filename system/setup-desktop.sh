#!/usr/bin/env bash
# One-time system steps for the desktop that need root. Run:  sudo ~/dotfiles/system/setup-desktop.sh
#   1. packages from packages.txt (official repos)
#   2. Claude Desktop from packages/claude-desktop (built beforehand as user with makepkg)
#   3. gnome-keyring unlocked at console login (PAM), so apps keep their logins
set -euo pipefail
cd "$(dirname "$0")/.."

((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "Pakete aus den offiziellen Repos (packages.txt)"
grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -

step "Claude Desktop (lokal gebautes Paket, Signatur geprüft)"
pkg=$(ls -t packages/claude-desktop/claude-desktop-*.pkg.tar.zst 2>/dev/null | head -1)
if [[ -n "$pkg" ]]; then
    pacman -U --needed "$pkg"
else
    echo "  kein Paket gebaut – übersprungen (cd packages/claude-desktop && makepkg)"
fi

step "Schlüsselbund bei der Anmeldung entsperren (PAM, /etc/pam.d/login)"
pam=/etc/pam.d/login
if grep -q pam_gnome_keyring "$pam"; then
    echo "  schon eingerichtet"
else
    backup="$pam.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$pam" "$backup"
    # after the other auth lines / at the end of the session lines (Arch Wiki: GNOME/Keyring)
    awk '
        { lines[NR] = $0 }
        /^auth/    { last_auth = NR }
        /^session/ { last_session = NR }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_auth)    print "auth       optional     pam_gnome_keyring.so"
                if (i == last_session) print "session    optional     pam_gnome_keyring.so auto_start"
            }
        }' "$backup" > "$pam.new"
    mv "$pam.new" "$pam"
    cat "$pam"
fi

printf '\nFertig.\n'
