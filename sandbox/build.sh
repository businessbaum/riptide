#!/usr/bin/env bash
# Build the sandbox helpers next to their sources (app-sandbox uses them from here,
# session/desktop_shell/paths.py; one day the package builds them into /usr/lib/riptide/sandbox).
#   wl-security-context   Wayland socket in a security context (see its source)
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
out=$src
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xml=/usr/share/wayland-protocols/staging/security-context/security-context-v1.xml
wayland-scanner client-header "$xml" "$tmp/security-context-v1-client-protocol.h"
wayland-scanner private-code "$xml" "$tmp/security-context-v1-protocol.c"

mkdir -p "$out"
gcc -O2 -Wall -Wextra -I"$tmp" -o "$out/wl-security-context" \
    "$src/wl-security-context.c" "$tmp/security-context-v1-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)
echo "gebaut: $out/wl-security-context"
