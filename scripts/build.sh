#!/usr/bin/env bash
#
# build.sh — compile NTFStore.app into ./build WITHOUT installing anything.
# For development / testing. No sudo, touches nothing system-wide.
#
#   ./scripts/build.sh          # builds ./build/NTFStore.app
#   ./scripts/build.sh --run    # ...and launches it
#
# By Pritish Maheta.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_DIR}/src"
OUT="${REPO_DIR}/build"
APP="${OUT}/NTFStore.app"
EXEC="NTFStore"

command -v swiftc >/dev/null || { echo "swiftc missing — run 'xcode-select --install'"; exit 1; }

echo "==> Compiling ${EXEC}…"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
swiftc -O -o "${APP}/Contents/MacOS/${EXEC}" "${SRC}/NTFStore/main.swift" -framework Cocoa
cp "${SRC}/NTFStore/Info.plist" "${APP}/Contents/Info.plist"
[ -f "${SRC}/NTFStore/AppIcon.icns" ] && cp "${SRC}/NTFStore/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
codesign -f -s - "${APP}" >/dev/null 2>&1 || true

echo "==> Built: ${APP}"
echo "    (Note: without the installed helper + sudoers rule, 'Mount read-write' won't work —"
echo "     run ./install.sh for a fully functional install.)"

if [ "${1:-}" = "--run" ]; then
    pkill -f "${EXEC}" 2>/dev/null || true
    sleep 1
    open "${APP}"
    echo "==> Launched. Look for the drive icon + 'NTFS' in the menu bar."
fi
