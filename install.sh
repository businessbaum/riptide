#!/usr/bin/env bash
# Set up riptide from this repo.
#   sudo ./install.sh packages   install everything in packages.txt (official repos)
#   ./install.sh link            link the user's configs (stow) and the software into the home folder
#   ./install.sh services        enable the user services of the desktop session
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
packages)
    ((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
    grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -
    ;;
link)
    ((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
    # The user's own things (home/): every directory there is one stow package mirroring
    # $HOME. Config folders are linked as a whole; shared folders under ~/.local/share get
    # one link per file (--no-folding), so other programs never write into this repo.
    # Folded packages: only add what is missing, never --restow – that removes a link such
    # as ~/.config/kitty for a moment. Shared packages: --restow (per-file links, no folder
    # vanishes) also drops links of files that are gone.
    shared=(applications wireplumber)
    stow --dir=home --target="$HOME" $(ls home | grep -vxF -f <(printf '%s\n' "${shared[@]}"))
    stow --dir=home --target="$HOME" --restow --no-folding "${shared[@]}"

    # The software (shell/, hypr/, session/, bin/, data/, systemd/, wireplumber/) runs from
    # /usr/lib/riptide once that is there – the package (packaging/), or this repo bound
    # over it read-only in developer mode (docs/os-plan.md); before that from this repo.
    # Each place in the home folder is a link into it. A link is swapped in one step
    # (rename), so nothing reads a missing folder in between; a folder that holds only
    # links (and Python's caches) may be replaced by one link, anything else is left alone.
    root=$PWD
    [[ -d /usr/lib/riptide/shell && -d /usr/lib/riptide/session ]] && root=/usr/lib/riptide
    echo "Software aus: $root"
    place() { # place <path in the tree> <path in $HOME>
        local target="$root/$1" link="$HOME/$2" parent
        parent=$(dirname "$link")
        [[ -L "$parent" && ! -e "$parent" ]] && rm -f -- "$parent" # (a stow link to a folder that moved)
        mkdir -p "$parent"
        [[ -L "$link" && "$(readlink "$link")" == "$target" ]] && return
        if [[ -d "$link" && ! -L "$link" ]]; then
            if find "$link" -mindepth 1 ! -type l ! -name __pycache__ ! -path '*/__pycache__/*' | grep -q .; then
                echo "Übersprungen (kein reiner Link-Ordner): $link" >&2
                return
            fi
            rm -rf -- "$link"
        fi
        ln -s "$target" "$link.riptide-new" && mv -Tf "$link.riptide-new" "$link"
    }
    place shell .config/quickshell
    place hypr .config/hypr
    place session/desktop_shell .local/lib/desktop_shell
    place wireplumber/scripts/macos .local/share/wireplumber/scripts/macos
    place data/portals/hyprland-portals.conf .config/xdg-desktop-portal/hyprland-portals.conf
    for f in "$root"/bin/*; do f=${f#"$root"/}; place "$f" ".local/bin/${f#bin/}"; done
    for f in "$root"/systemd/*.service "$root"/systemd/*.timer "$root"/systemd/*.d/*; do f=${f#"$root"/}; place "$f" ".config/systemd/user/${f#systemd/}"; done
    for f in "$root"/data/applications/*; do place "${f#"$root"/}" ".local/share/applications/${f##*/}"; done
    for f in "$root"/data/icons/hicolor/scalable/apps/*; do place "${f#"$root"/}" ".local/share/icons/hicolor/scalable/apps/${f##*/}"; done
    for f in "$root"/data/dbus-1/services/*; do place "${f#"$root"/}" ".local/share/dbus-1/services/${f##*/}"; done
    for f in "$root"/wireplumber/conf.d/*; do place "${f#"$root"/}" ".config/wireplumber/wireplumber.conf.d/${f##*/}"; done
    # start links of enabled services that point where a unit file was before: to its
    # place in the home folder (what is disabled stays disabled)
    for w in "$HOME"/.config/systemd/user/*.wants/riptide-*; do
        [[ -L "$w" && ! -e "$w" ]] && ln -sfn "$HOME/.config/systemd/user/${w##*/}" "$w"
    done
    systemctl --user daemon-reload

    # "Neues Dokument" in the file manager's menu (right click on an empty spot): Nautilus
    # offers what lies in the templates folder. An empty file without an ending – the ending
    # is typed with the name – and a text document. Real files, not links: a new document is
    # a copy of one.
    templates=$(xdg-user-dir TEMPLATES 2>/dev/null || true)
    if [[ -n "$templates" && "$templates" != "$HOME" ]]; then
        mkdir -p "$templates"
        [[ -e "$templates/Neue Datei" ]] || : > "$templates/Neue Datei"
        [[ -e "$templates/Textdokument.txt" ]] || : > "$templates/Textdokument.txt"
    fi
    ;;
services)
    ((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
    systemctl --user enable hypridle.service   # starts with the next Hyprland session
    systemctl --user enable --now riptide-session.service   # permissions, sandboxes, new apps
    systemctl --user enable riptide-shell.service           # the shell; restarted should it crash
    systemctl --user enable hyprsunset.service              # Night Shift (started neutral)
    systemctl --user enable --now riptide-report.timer      # daily error report
    ~/.local/bin/app-sandbox --sync
    ;;
*)
    sed -n '2,5p' "$0"
    exit 1
    ;;
esac
