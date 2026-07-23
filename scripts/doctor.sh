#!/usr/bin/env bash
#
# NTFStore — doctor
# Checks the whole NTFS read/write stack and prints the fix for anything broken.
# Read-only: it inspects, it does not change anything.
#
#   ./scripts/doctor.sh
#
# By Pritish Maheta.

HELPER_PATH="/usr/local/sbin/ntfs-mount-rw.sh"
SHIM_PATH="/usr/local/lib/libfuse.2.dylib"
SUDOERS_PATH="/etc/sudoers.d/ntfstore"
APP_DEST="/Applications/NTFStore.app"
AGENT_LABEL="com.ntfstore.app"

pass=0; fail=0
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '      \033[2m↳ fix:\033[0m %s\n' "$2"; }
info() { printf '  \033[1;34mi\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

printf '\033[1m🖴  NTFStore — doctor\033[0m\n'

hdr "System"
[ "$(uname)" = "Darwin" ] && ok "macOS $(sw_vers -productVersion) ($(uname -m))" \
    || bad "Not macOS — NTFStore is macOS only."

hdr "Toolchain"
command -v brew   >/dev/null && ok "Homebrew present"               || bad "Homebrew missing" "install from https://brew.sh"
command -v swiftc >/dev/null && ok "Xcode Command Line Tools present" || bad "swiftc missing" "xcode-select --install"

hdr "Engine"
if ls /usr/local/lib/libfuse-t-*.dylib >/dev/null 2>&1; then ok "FUSE-T installed"
else bad "FUSE-T not installed" "brew install --cask fuse-t (or re-run ./install.sh)"; fi

NTFS_3G=""
for c in /opt/homebrew/bin/ntfs-3g /usr/local/bin/ntfs-3g; do [ -x "$c" ] && NTFS_3G="$c" && break; done
[ -n "$NTFS_3G" ] && ok "ntfs-3g present ($NTFS_3G)" \
    || bad "ntfs-3g not found" "brew tap gromgit/homebrew-fuse && brew install ntfs-3g-mac"

hdr "libfuse shim"
if [ -e "$SHIM_PATH" ]; then
    ver=$(otool -l "$SHIM_PATH" 2>/dev/null | awk '/LC_ID_DYLIB/{f=1} f&&/compatibility version/{print $3; exit}')
    if [ "$ver" = "12.9.0" ]; then ok "shim present, compatibility version $ver"
    else bad "shim present but wrong version ($ver, need 12.9.0)" "re-run ./install.sh"; fi
else
    bad "shim missing at $SHIM_PATH" "re-run ./install.sh"
fi
if [ -n "$NTFS_3G" ]; then
    otool -L "$NTFS_3G" 2>/dev/null | grep -q "$SHIM_PATH" \
        && ok "ntfs-3g links the shim" \
        || bad "ntfs-3g does not link $SHIM_PATH" "reinstall ntfs-3g-mac, then ./install.sh"
fi

hdr "Mount helper + privileges"
[ -x "$HELPER_PATH" ] && ok "helper installed ($HELPER_PATH)" \
    || bad "helper missing" "re-run ./install.sh"
if [ -e "$SUDOERS_PATH" ]; then
    if sudo -n visudo -cf "$SUDOERS_PATH" >/dev/null 2>&1; then ok "sudoers rule present & valid"
    else info "sudoers rule present (couldn't validate without a cached sudo credential)"; fi
else
    bad "sudoers rule missing at $SUDOERS_PATH" "re-run ./install.sh"
fi
if [ -x "$HELPER_PATH" ]; then
    # A harmless no-op: the helper exits 2 on a bad arg but never prompts if NOPASSWD works.
    if sudo -n "$HELPER_PATH" __doctor_probe__ >/dev/null 2>&1 || [ $? -eq 2 ]; then
        ok "passwordless sudo for the helper works"
    else
        bad "passwordless sudo for the helper failed" "check $SUDOERS_PATH names your user ($(id -un))"
    fi
fi

hdr "App + login item"
[ -d "$APP_DEST" ] && ok "NTFStore.app installed" || bad "app not installed" "re-run ./install.sh"
pgrep -f "NTFStore" >/dev/null && ok "app is running (menu-bar icon should be visible)" \
    || info "app not running — launch it: open \"$APP_DEST\""
if launchctl print "gui/$(id -u)/${AGENT_LABEL}" >/dev/null 2>&1; then ok "login item registered (starts at login)"
else info "login item not loaded — re-run ./install.sh to enable start-at-login"; fi

hdr "NTFS drives"
ids=$(diskutil list 2>/dev/null | awk '/Windows_NTFS/ {print $NF}')
if [ -z "$ids" ]; then
    info "No NTFS drives currently connected."
else
    for id in $ids; do
        name=$(diskutil info "/dev/$id" 2>/dev/null | awk -F': *' '/Volume Name/ {print $2; exit}')
        if mount | grep -qF "fuse-t:/$name on "; then info "$name ($id): 🟢 read-write"
        elif mount | grep -q "^/dev/$id on ";      then info "$name ($id): 🔴 read-only — use 'Mount read-write' in the menu"
        else                                             info "$name ($id): ⚪️ not mounted — use 'Mount read-write' in the menu"; fi
    done
fi

hdr "Result"
if [ "$fail" -eq 0 ]; then
    printf '  \033[1;32mAll %d checks passed. You are good to go.\033[0m\n\n' "$pass"
else
    printf '  \033[1;31m%d issue(s) found\033[0m, %d checks passed. Apply the fixes above (usually: ./install.sh).\n\n' "$fail" "$pass"
fi
exit 0
