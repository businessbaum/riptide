#!/usr/bin/env bash
# Build the riptide package from this repo's last commit (as the user, not root). It lands in
# packaging/out/; sudo system/setup-os.sh installs the newest one (docs/os-plan.md).
set -euo pipefail
((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
if ! git -C "$here/.." diff --quiet HEAD -- shell hypr session bin data systemd wireplumber sandbox plugin; then
    echo "Hinweis: nicht committete Änderungen kommen nicht ins Paket." >&2
fi
mkdir -p "$here/out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$here/riptide"
BUILDDIR="$work" PKGDEST="$here/out" SRCDEST="$work" LOGDEST="$work" \
    makepkg --force --clean --cleanbuild --noconfirm
ls -t "$here"/out/riptide-*.pkg.tar.zst | head -1
