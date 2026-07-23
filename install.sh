#!/usr/bin/env bash
#
# NTFStore — installer
# Installs a kext-free NTFS read/write stack (FUSE-T + ntfs-3g) and the
# NTFStore menu-bar app on macOS. Safe to re-run (idempotent).
#
# Run as your NORMAL user (NOT with sudo). It calls sudo only for the steps that
# genuinely need root, and installs a passwordless sudo rule for the mount helper.
#
#   ./install.sh
#
# By Pritish Maheta.

set -euo pipefail

# ---- identity / paths ----------------------------------------------------
APP_NAME="NTFStore"
EXEC_NAME="NTFStore"
BUNDLE_ID="com.ntfstore.app"
AGENT_LABEL="com.ntfstore.app"

HELPER_PATH="/usr/local/sbin/ntfs-mount-rw.sh"
SHIM_PATH="/usr/local/lib/libfuse.2.dylib"
SUDOERS_PATH="/etc/sudoers.d/ntfstore"
APP_DEST="/Applications/${APP_NAME}.app"
AGENT_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${REPO_DIR}/src"

blue()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

# ---- preflight -----------------------------------------------------------
[ "$(uname)" = "Darwin" ]       || die "macOS only."
[ "${EUID:-$(id -u)}" -ne 0 ]   || die "Run as your normal user, not with sudo."
command -v brew   >/dev/null    || die "Homebrew is required — install from https://brew.sh then re-run."
command -v swiftc >/dev/null    || die "Xcode Command Line Tools required — run 'xcode-select --install' then re-run."

USER_NAME="$(id -un)"
blue "Installing ${APP_NAME} for user '${USER_NAME}' on $(sw_vers -productVersion) ($(uname -m))."
warn "You'll be asked for your password once (for the privileged steps)."

# ---- 1. FUSE-T (kext-free FUSE) -----------------------------------------
if ls /usr/local/lib/libfuse-t-*.dylib >/dev/null 2>&1; then
    blue "FUSE-T already present."
else
    blue "Installing FUSE-T…"
    brew install --cask fuse-t
fi
FUSE_T_LIB="$(ls -1 /usr/local/lib/libfuse-t-*.dylib 2>/dev/null | head -1 || true)"
[ -n "${FUSE_T_LIB}" ] && [ -e "${FUSE_T_LIB}" ] || die "FUSE-T library not found after install."

# ---- 2. ntfs-3g ----------------------------------------------------------
if brew list ntfs-3g-mac >/dev/null 2>&1; then
    blue "ntfs-3g already installed."
else
    blue "Installing ntfs-3g (gromgit/fuse tap)…"
    brew tap gromgit/homebrew-fuse >/dev/null 2>&1 || true
    brew trust --formula gromgit/fuse/ntfs-3g-mac >/dev/null 2>&1 || true
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew install ntfs-3g-mac
fi

# ---- 3. libfuse.2.dylib shim (points ntfs-3g at FUSE-T) ------------------
blue "Building the libfuse.2.dylib shim…"
TMP_LIB="$(mktemp -d)/libfuse.2.dylib"
cp "${FUSE_T_LIB}" "${TMP_LIB}"
python3 "${SRC}/scripts/patch_version.py" "${TMP_LIB}"
install_name_tool -id "${SHIM_PATH}" "${TMP_LIB}" 2>/dev/null || true
codesign -f -s - "${TMP_LIB}"
sudo mkdir -p /usr/local/lib
if [ -e "${SHIM_PATH}" ] && [ ! -e "${SHIM_PATH}.pre-ntfstore" ]; then
    sudo cp -p "${SHIM_PATH}" "${SHIM_PATH}.pre-ntfstore"      # keep any pre-existing lib
fi
sudo cp "${TMP_LIB}" "${SHIM_PATH}"
sudo chown root:wheel "${SHIM_PATH}"; sudo chmod 755 "${SHIM_PATH}"
rm -rf "$(dirname "${TMP_LIB}")"

# ---- 4. privileged mount helper -----------------------------------------
blue "Installing the mount helper → ${HELPER_PATH}"
sudo mkdir -p /usr/local/sbin
sudo install -m 0755 -o root -g wheel "${SRC}/scripts/ntfs-mount-rw.sh" "${HELPER_PATH}"

# ---- 5. passwordless sudo rule for THIS user ----------------------------
blue "Installing sudoers rule (NOPASSWD) for '${USER_NAME}'…"
SUDO_TMP="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: %s\n' "${USER_NAME}" "${HELPER_PATH}" > "${SUDO_TMP}"
if sudo visudo -cf "${SUDO_TMP}" >/dev/null 2>&1; then
    sudo install -m 0440 -o root -g wheel "${SUDO_TMP}" "${SUDOERS_PATH}"
    rm -f "${SUDO_TMP}"
else
    rm -f "${SUDO_TMP}"; die "Generated sudoers rule failed validation — aborting."
fi

# ---- 6. build & install the app -----------------------------------------
blue "Building ${APP_NAME}.app…"
BUILD_DIR="$(mktemp -d)"
swiftc -O -o "${BUILD_DIR}/${EXEC_NAME}" "${SRC}/NTFStore/main.swift" -framework Cocoa
sudo rm -rf "${APP_DEST}"
sudo mkdir -p "${APP_DEST}/Contents/MacOS" "${APP_DEST}/Contents/Resources"
sudo cp "${BUILD_DIR}/${EXEC_NAME}" "${APP_DEST}/Contents/MacOS/${EXEC_NAME}"
sudo cp "${SRC}/NTFStore/Info.plist" "${APP_DEST}/Contents/Info.plist"
[ -f "${SRC}/NTFStore/AppIcon.icns" ] && sudo cp "${SRC}/NTFStore/AppIcon.icns" "${APP_DEST}/Contents/Resources/AppIcon.icns"
sudo codesign -f -s - "${APP_DEST}"
rm -rf "${BUILD_DIR}"

# ---- 7. login item (auto-start, per-user) --------------------------------
blue "Installing login item…"
mkdir -p "${HOME}/Library/LaunchAgents"
cat > "${AGENT_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_DEST}/Contents/MacOS/${EXEC_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/${AGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${AGENT_PATH}" 2>/dev/null || open "${APP_DEST}"

printf '\n\033[1;32m✓ %s installed.\033[0m\n' "${APP_NAME}"
echo "  • Look for the drive icon + 'NTFS' in your menu bar (top-right)."
echo "  • Plug in an NTFS drive, click the icon, choose 'Mount read-write'."
echo "  • Eject from the menu before unplugging."
echo
warn "First mount may prompt macOS to approve FUSE-T in System Settings → Privacy & Security."
