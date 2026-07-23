#!/usr/bin/env bash
#
# NTFStore — uninstaller
# Removes the app, helper, sudoers rule, shim and login item. Leaves the Homebrew
# packages (FUSE-T, ntfs-3g) unless you pass --all.
#
#   ./uninstall.sh          # remove NTFStore bits only
#   ./uninstall.sh --all    # also 'brew uninstall' FUSE-T and ntfs-3g
#
# By Pritish Maheta.

set -uo pipefail

APP_NAME="NTFStore"
AGENT_LABEL="com.ntfstore.app"
HELPER_PATH="/usr/local/sbin/ntfs-mount-rw.sh"
SHIM_PATH="/usr/local/lib/libfuse.2.dylib"
SUDOERS_PATH="/etc/sudoers.d/ntfstore"
APP_DEST="/Applications/${APP_NAME}.app"
AGENT_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

blue() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

blue "Stopping and removing the app + login item…"
launchctl bootout "gui/$(id -u)/${AGENT_LABEL}" 2>/dev/null || true
rm -f "${AGENT_PATH}"
pkill -f "NTFStore" 2>/dev/null || true
sudo rm -rf "${APP_DEST}"

blue "Removing helper + sudoers rule…"
sudo rm -f "${HELPER_PATH}" "${SUDOERS_PATH}"

blue "Removing the libfuse shim…"
if [ -e "${SHIM_PATH}.pre-ntfstore" ]; then
    sudo mv -f "${SHIM_PATH}.pre-ntfstore" "${SHIM_PATH}"   # restore what was there before
else
    sudo rm -f "${SHIM_PATH}"
fi

if [ "${1:-}" = "--all" ]; then
    blue "Removing Homebrew packages…"
    brew uninstall ntfs-3g-mac 2>/dev/null || true
    brew uninstall --cask fuse-t 2>/dev/null || true
fi

printf '\n\033[1;32m✓ %s uninstalled.\033[0m\n' "${APP_NAME}"
echo "  (Any mounted NTFS drives should be re-plugged; macOS will mount them read-only again.)"
