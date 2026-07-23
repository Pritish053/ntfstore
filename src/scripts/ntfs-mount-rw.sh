#!/bin/bash
#
# ntfs-mount-rw.sh <diskXsY>
# One-shot: mount a single NTFS partition read-write via ntfs-3g (over FUSE-T).
# Invoked EXPLICITLY (NTFStore menu-bar button), never by mount events, so
# there is no self-triggering and no risk of tearing down a good mount.
#
# Idempotent and stale-safe:
#   - already read-write AND responsive -> do nothing
#   - a stale FUSE-T mount (drive yanked without ejecting) -> tear it down, remount
#   - read-only / not mounted -> mount read-write
#
# Must run as root (opening the raw device requires it). A sudoers NOPASSWD rule
# lets the logged-in user invoke it. Because the caller lives in the user's login
# session, the FUSE-T mount it creates persists (a system daemon's would not).
#
# Part of NTFStore — https://github.com/  (by Pritish Maheta)

set -u

# Locate the ntfs-3g binary (Apple Silicon or Intel Homebrew).
NTFS_3G=""
for c in /opt/homebrew/bin/ntfs-3g /usr/local/bin/ntfs-3g; do
    [ -x "$c" ] && { NTFS_3G="$c"; break; }
done

LOG="/var/log/ntfstore.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') mount-rw: $*" >>"$LOG" 2>/dev/null; }

# Is the mountpoint responsive? A live FUSE mount answers a stat immediately; a
# stale one (backing device gone) hangs or errors. Time it out so we never block.
mp_live() {
    local mp="$1"
    stat "$mp" >/dev/null 2>&1 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1; waited=$((waited + 1))
        if [ "$waited" -ge 5 ]; then
            kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 1
        fi
    done
    wait "$pid"; return $?
}

# Forcibly remove a stale FUSE-T mount and its backing processes for volume $1/$2.
teardown_stale() {
    local nm="$1" mp="$2"
    log "tearing down stale mount of '$nm' at '$mp'"
    diskutil unmount force "$mp" >/dev/null 2>&1
    umount -f "$mp" >/dev/null 2>&1
    pkill -f "go-nfsv4 --volname $nm" 2>/dev/null
    pkill -f "volname=$nm" 2>/dev/null
    sleep 1
}

[ -n "$NTFS_3G" ] || { log "ntfs-3g not found (is ntfs-3g-mac installed?)"; echo "ntfs-3g missing" >&2; exit 4; }

id="${1:-}"
case "$id" in
    disk[0-9]*s[0-9]*) ;;
    *) echo "usage: $(basename "$0") diskXsY" >&2; exit 2 ;;
esac
dev="/dev/$id"

info=$(diskutil info "$dev" 2>/dev/null) || { log "$dev: no such device"; exit 3; }
echo "$info" | grep -q "Windows_NTFS" || { log "$dev is not NTFS — refusing"; exit 3; }

name=$(printf '%s\n' "$info" | awk -F': *' '/Volume Name/ {print $2; exit}')
name=${name:-$id}
target="/Volumes/$name"

# Existing FUSE-T mount for this volume? Keep it only if it is actually live.
if mount | grep -qF "fuse-t:/$name on "; then
    if mp_live "$target"; then
        log "$name already read-write (live)"; echo "already read-write"; exit 0
    fi
    teardown_stale "$name" "$target"
fi

parent=$(printf '%s' "$id" | sed -E 's/^(disk[0-9]+).*/\1/')
mkdir -p "$target"

# Tight race against FSKit: free the whole disk and immediately grab it.
# -o force + -o remove_hiberfile: mount RW even from a dirty/hibernated state.
rc=1
for attempt in 1 2 3 4 5 6 7 8; do
    diskutil unmountDisk force "/dev/$parent" >/dev/null 2>&1
    "$NTFS_3G" "$dev" "$target" \
        -o local -o allow_other -o auto_xattr -o windows_names \
        -o force -o remove_hiberfile \
        -o volname="$name" >>"$LOG" 2>&1
    rc=$?
    [ $rc -eq 0 ] && break
    sleep 1
done

if [ $rc -ne 0 ]; then
    log "FAILED: could not mount $dev read-write; leaving it to macOS"
    diskutil mount "$dev" >/dev/null 2>&1
    echo "failed"; exit 1
fi

log "OK: $dev read-write at '$target'"
echo "mounted read-write"

# Strip the read-only FSKit duplicate FSKit adds during the swap. One gentle pass
# by mountpoint (FSKit does not re-add it once removed).
sleep 2
mount | grep "^$dev on " | while IFS= read -r line; do
    mp=$(printf '%s' "$line" | sed -n 's/^[^ ]* on \(.*\) (.*/\1/p')
    [ -n "$mp" ] && diskutil unmount "$mp" >/dev/null 2>&1
done
exit 0
