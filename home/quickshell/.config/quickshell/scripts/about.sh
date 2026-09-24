#!/usr/bin/env bash
# "Über diesen Computer": a short summary of the machine as a notification.
cpu=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
ram=$(awk '/MemTotal/ {printf "%.0f GB", $2/1024/1024}' /proc/meminfo)
gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
notify-send -a System -i computer "$(hostname)" \
    "Arch Linux\n$cpu\n${gpu:+$gpu\n}$ram Arbeitsspeicher\nKernel $(uname -r)"
