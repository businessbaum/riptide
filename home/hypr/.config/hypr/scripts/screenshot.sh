#!/usr/bin/env bash
# Screenshots like on a Mac.
#   screenshot.sh screen|area [file|clipboard|both]
#     file       saved in ~/Bilder/Bildschirmfotos (default)
#     clipboard  only copied, nothing saved
#     both       saved and copied
set -euo pipefail

folder="$HOME/Bilder/Bildschirmfotos"
mkdir -p "$folder"
file="$folder/Bildschirmfoto $(date '+%Y-%m-%d um %H.%M.%S').png"
target=${2:-file}

# the camera sound, like on a Mac (System Settings → Ton → Toneffekte der Oberfläche)
shutter() {
    [ "$(jq -r '.sound.ui_sounds // true' "$HOME/.config/macos/settings.json" 2>/dev/null)" = false ] && return
    pw-play --media-role=Notification /usr/share/sounds/freedesktop/stereo/camera-shutter.oga >/dev/null 2>&1 &
}

region=()
if [ "${1:-screen}" = area ]; then
    geometry=$(slurp -d) || exit 0 # cancelled with Esc
    region=(-g "$geometry")
fi

shutter
case "$target" in
    clipboard)
        grim "${region[@]}" - | wl-copy --type image/png
        notify-send -a Bildschirmfoto -i image-x-generic "Bildschirmfoto" "In die Zwischenablage kopiert" ;;
    both)
        grim "${region[@]}" "$file"
        wl-copy --type image/png < "$file"
        notify-send -a Bildschirmfoto -i "$file" "Bildschirmfoto" "Gesichert in Bilder/Bildschirmfotos und kopiert" ;;
    *)
        grim "${region[@]}" "$file"
        notify-send -a Bildschirmfoto -i "$file" "Bildschirmfoto" "Gesichert in Bilder/Bildschirmfotos" ;;
esac
