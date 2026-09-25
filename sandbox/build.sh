#!/usr/bin/env bash
# Build the sandbox helpers into ~/.local/lib/macos-sandbox (app-sandbox uses them).
#   wl-security-context   Wayland socket in a security context (see its source)
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
out=~/.local/lib/macos-sandbox
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
