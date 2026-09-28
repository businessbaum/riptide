#!/usr/bin/env bash
# Storage overview for System Settings: prints "key|bytes|label" lines, quick ones first.
# Sizes of the home folders come from du and may take a moment.
export LC_ALL=C

read -r size used avail < <(df -B1 --output=size,used,avail / | tail -1)
echo "disk.size|$size|"
echo "disk.used|$used|"
echo "disk.free|$avail|"

# Installed packages (official repos): sum of "Installed Size"
pacman -Qi | awk -F': *' '/^Installed Size/ {
    split($2, a, " "); v = a[1]; u = a[2]
    m = (u == "B") ? 1 : (u == "KiB") ? 1024 : (u == "MiB") ? 1048576 : (u == "GiB") ? 1073741824 : 1
    s += v * m } END { printf "apps|%d|Programme (pacman)\n", s }'

size_of() { local s; s=$(du -sb "$1" 2>/dev/null | cut -f1); echo "${s:-0}"; }

# apps from their maker's release archive (archive-app: Zen …)
[ -d ~/.local/share/macos/apps ] && echo "archive|$(size_of ~/.local/share/macos/apps)|Programme (offizielle Releases)"
echo "pkgcache|$(size_of /var/cache/pacman/pkg)|Paket-Cache"
echo "trash|$(size_of ~/.local/share/Trash)|Papierkorb"
echo "cache|$(size_of ~/.cache)|Zwischenspeicher der Apps"

for kind in DOCUMENTS PICTURES MUSIC VIDEOS DOWNLOAD DESKTOP; do
    dir=$(xdg-user-dir "$kind" 2>/dev/null)
    [ -n "$dir" ] && [ "$dir" != "$HOME" ] && [ -d "$dir" ] && echo "folder|$(size_of "$dir")|$(basename "$dir")"
done
echo "home|$(size_of ~)|Persönlicher Ordner"
echo "done|0|"
