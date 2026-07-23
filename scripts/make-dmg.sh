#!/usr/bin/env bash
#
# make-dmg.sh — build a distributable disk image for NTFStore.
# The .dmg contains the full project and a double-clickable installer command.
# (NTFStore needs a helper + engine, so this is a "double-click to install"
# image, not a drag-to-Applications app.)
#
#   ./scripts/make-dmg.sh            # -> dist/NTFStore-<version>.dmg
#
# By Pritish Maheta.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' src/NTFStore/Info.plist 2>/dev/null || echo dev)"
VOLNAME="NTFStore"
STAGE="$(mktemp -d)/dmg"
OUT="${REPO_DIR}/dist/NTFStore-${VERSION}.dmg"

mkdir -p "${STAGE}/NTFStore" "$(dirname "${OUT}")"

echo "==> Staging tracked files…"
git archive --format=tar HEAD | tar -x -C "${STAGE}/NTFStore"

echo "==> Writing installer command…"
cat > "${STAGE}/Install NTFStore.command" <<'CMD'
#!/bin/bash
# Double-click to install NTFStore. Opens Terminal and runs the installer.
cd "$(dirname "$0")/NTFStore" || { echo "payload missing"; exit 1; }
echo "Installing NTFStore — you'll be asked for your password once."
echo
exec ./install.sh
CMD
chmod +x "${STAGE}/Install NTFStore.command"

# A short read-me shown in the mounted image.
cat > "${STAGE}/READ ME FIRST.txt" <<TXT
NTFStore ${VERSION}
=======================

Read & write NTFS drives on macOS, by Pritish Maheta.

TO INSTALL:
  Double-click "Install NTFStore.command".
  (If macOS blocks it: right-click → Open, then confirm. It will ask for your
   password once, install FUSE-T + ntfs-3g and the menu-bar app, and start it.)

After installing, look for the drive icon + "NTFS" in your menu bar.

Full docs & source are in the NTFStore folder (README.md, docs/).
TXT

echo "==> Building ${OUT}…"
rm -f "${OUT}"
hdiutil create -volname "${VOLNAME}" -srcfolder "${STAGE}" -ov -format UDZO "${OUT}" >/dev/null
rm -rf "$(dirname "${STAGE}")"

echo "==> Done: ${OUT} ($(du -h "${OUT}" | cut -f1))"
