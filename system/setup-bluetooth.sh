#!/usr/bin/env bash
# One-time Bluetooth setup. Run:  sudo ~/dotfiles/system/setup-bluetooth.sh
#   AlwaysPairable: the adapter stays pairable after every boot. Without it BlueZ only
#   makes temporary pairings (no stored key) and devices such as AirPods are forgotten
#   as soon as they disconnect.
set -euo pipefail
((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }

conf=/etc/bluetooth/main.conf
if grep -q '^AlwaysPairable *= *true' "$conf"; then
    echo "schon eingerichtet"
else
    cp "$conf" "$conf.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i 's/^\[General\]$/[General]\nAlwaysPairable = true/' "$conf"
    grep -n -A1 '^\[General\]' "$conf"
fi
systemctl restart bluetooth.service
echo "Fertig. Bluetooth wurde neu gestartet."
