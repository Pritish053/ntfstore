# NTFStore — Troubleshooting & Findings

Everything that went wrong while building this on **macOS 26 (Tahoe), Apple
Silicon**, and exactly how each was solved — so you never have to re-debug it.

Run **`./scripts/doctor.sh`** first: it checks the whole stack and prints the fix
for anything broken. This doc is the reference behind it.

---

## 0. Quick diagnostics

```bash
# What NTFS drives exist and how are they mounted?
diskutil list | grep -i ntfs
mount | grep -iE 'ntfs|fuse-t'

# Is a specific volume mounted, and read-only or read-write?
diskutil info /dev/disk5s1 | grep -iE 'Mounted|Read-Only|Volume Name'

# Backing processes (a healthy RW mount has BOTH of these):
pgrep -fl 'ntfs-3g|go-nfsv4'

# The mount log:
tail -30 /var/log/ntfstore.log

# Is the engine installed?
ls -l /opt/homebrew/bin/ntfs-3g /usr/local/lib/libfuse.2.dylib
brew list --cask fuse-t; brew list ntfs-3g-mac
```

A healthy read-write mount looks like:

```
fuse-t:/Seagate Pritish on /Volumes/Seagate Pritish (nfs)
```

A read-only (macOS built-in FSKit) mount looks like:

```
/dev/disk5s1 on /Volumes/Seagate Pritish (ntfs, ..., read-only, ..., fskit)
```

---

## 1. Symptom → Cause → Fix

### "Unsupported macOS Version — the installed version of macFUSE is too old"
- **Cause:** macFUSE 4.x is incompatible with macOS 26, and it's a kernel extension anyway.
- **Fix:** Don't use macFUSE. NTFStore uses **FUSE-T** (kext-free). If old macFUSE
  is present, it's harmless once the shim is installed, but you can remove it:
  `sudo rm -rf /Library/Filesystems/macfuse.fs /Library/PreferencePanes/macFUSE.prefPane`
  and forget its receipts (`pkgutil --forget io.macfuse.installer.components.*`).

### `brew install ntfs-3g` → "Linux is required for this software"
- **Cause:** Homebrew's mainline `ntfs-3g` formula is Linux-only.
- **Fix:** Use the macOS build: `brew tap gromgit/homebrew-fuse && brew install ntfs-3g-mac`.

### `brew` → "…not trusted. Run `brew trust`"
- **Cause:** Newer Homebrew requires trusting third-party taps.
- **Fix:** `brew trust --formula gromgit/fuse/ntfs-3g-mac`, or install with
  `HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew install ntfs-3g-mac`. (The installer does this.)

### ntfs-3g runs but nothing mounts; dyld error about `libfuse.2.dylib` version
- **Cause:** ntfs-3g requires `libfuse.2.dylib` **compatibility version ≥ 12.0.0**;
  FUSE-T's `libfuse-t.dylib` reports **0.0.0**, so a plain symlink is rejected by dyld.
- **Fix:** the **shim** — a copy of FUSE-T's lib with its `LC_ID_DYLIB` version bumped
  to 12.9.0, install-name set to `/usr/local/lib/libfuse.2.dylib`, and ad-hoc re-signed.
  Built by `install.sh` via `src/scripts/patch_version.py`. Verify:
  `otool -l /usr/local/lib/libfuse.2.dylib | grep -A3 LC_ID_DYLIB` → should show `12.9.0`.

### `Error opening '/dev/diskXsY': Operation not permitted`
- **Cause:** macOS refuses to open a **mounted** raw device. macOS's FSKit driver had
  the volume mounted read-only (or re-grabbed it within milliseconds).
- **Fix:** free the whole disk and grab it in the same breath, retrying:
  `diskutil unmountDisk force /dev/diskN` immediately followed by the `ntfs-3g` mount,
  looped until the open wins. This is exactly what `ntfs-mount-rw.sh` does.

### "The NTFS partition is in an unsafe state… mount read-only"
- **Cause:** the volume has a dirty flag — Windows fast-startup / hibernation, or it was
  removed uncleanly.
- **Fix:** `ntfs-3g … -o force -o remove_hiberfile` mounts read-write anyway. Built into
  the helper. (On the Windows side, fully shut down — disable Fast Startup — to avoid it.)

### It mounts read-write, then vanishes a few seconds later
- **Cause (the big one):** a **system `LaunchDaemon` with `StartOnMount` self-sabotages**
  — it fires on its *own* mount event and runs `unmountDisk force`, destroying the mount
  it just created.
- **Fix:** don't auto-mount from a system daemon. Mount **on demand** from the user
  session (the menu-bar button → helper via `sudo -n`). NTFStore has **no**
  auto-mount daemon by design.

### Mount works from Terminal (`sudo`) but not from a background daemon
- **Cause:** FUSE-T mounts **only persist when created inside the user's login session**.
  A mount made from the system domain (LaunchDaemon) doesn't stick.
- **Fix:** always mount from the user session — the menu-bar app, or a *user* LaunchAgent
  + `sudo -n`. Never a system LaunchDaemon.

### Drive plugged in but nothing auto-mounts (not even read-only)
- **Cause:** macOS 26 does **not** reliably auto-mount NTFS. A leftover `/etc/fstab`
  `noauto` entry (from a previous NTFS tool) intermittently suppresses FSKit, so no
  mount event fires. You can't depend on a mount-trigger.
- **Fix:** button-driven mounting (click **Mount read-write**). This is why NTFStore
  is a menu-bar button, not an auto-mounter. (You can inspect fstab with `cat /etc/fstab`;
  the entry is harmless and can stay.)

### After unplugging without ejecting: a "stale" mount lingers
- **Symptom:** `mount` still shows `fuse-t:/<name>` and `pgrep ntfs-3g` shows a process,
  but the drive is gone. The next mount attempt thinks it's "already mounted".
- **Cause:** yanking the drive leaves the FUSE-T NFS mount + `go-nfsv4`/`ntfs-3g`
  processes running against a dead device.
- **Fix:** the helper detects this (a timed `stat` on the mountpoint) and tears it down
  (`diskutil unmount force` + `umount -f` + `pkill` the backing processes) before
  remounting. To do it by hand:
  `diskutil unmount force "/Volumes/NAME"; sudo pkill -f "volname=NAME"; sudo pkill -f "go-nfsv4 --volname NAME"`.
  **Best practice: use Eject in the menu before unplugging.**

### Volume looks mounted, but every read fails with "Device not configured"
- **Symptom:** `mount` shows a healthy-looking `fuse-t:/<name> … (nfs)` line and `df`
  reports plausible size/usage, but any `ls` on the mountpoint fails with
  `ls: fts_read: Device not configured`. `diskutil list external` shows the drive is
  physically present and fine.
- **Cause:** **device-node drift.** The drive dropped off the USB bus and macOS
  re-enumerated it under a *new* node (e.g. `disk4s1` → `disk5s1`). Because ntfs-3g is a
  userspace FUSE driver it gets no clean teardown, so it keeps holding the **old, dead**
  node indefinitely. The mountpoint survives, the `df` figures are stale cache, and every
  actual read hits a device that no longer exists.
  *Distinct from the yank-without-eject case above:* here the drive never left, it just
  changed node — so checks keyed on "is the volume gone?" won't catch it.
- **Diagnose** — compare the node ntfs-3g holds against the node the drive actually has;
  a mismatch confirms it:
  ```bash
  pgrep -fl ntfs-3g          # → /opt/homebrew/bin/ntfs-3g /dev/disk4s1 /Volumes/<name> …
  diskutil list external     # → Windows_NTFS  <name>  …  disk5s1
  ```
- **Fix:** tear down the dead mount, then remount against the real node. Safe to force —
  the mount has no live device left to flush:
  ```bash
  diskutil unmount force "/Volumes/<name>"
  sudo -n /usr/local/sbin/ntfs-mount-rw.sh disk5s1   # use the node from diskutil
  ```
- **Prevention:** the drift is caused by the drive losing the bus, so remove the causes.
  - **Don't run the drive through a bus-powered USB2 hub.** A 2.5" HDD pulls ~5 W at
    spin-up, which such a hub browns out (check with
    `ioreg -p IOUSB -w0 -l | grep -E '"USB Product Name"|"Device Speed"'`). Use a direct
    port or a *powered* USB3 hub.
  - **Stop aggressive sleep/spin-down** while the drive is attached:
    `sudo pmset -a disksleep 0` and `sudo pmset -c sleep 0` (inspect with `pmset -g custom`).
- **Note on cumulative damage:** each unclean detach leaves NTFS dirty, and NTFS gets no
  journal replay on macOS — Windows `chkdsk` later dumps the orphaned fragments into
  `found.000`, `found.001`, … at the volume root. A pile of those is a reliable sign this
  has been happening repeatedly. The helper's `-o force` mounts dirty volumes anyway,
  which keeps it invisible. Real repair needs `chkdsk /f` from Windows; ntfs-3g cannot
  properly repair NTFS.

### Two mounts of the same drive (e.g. "Seagate Pritish" and "Seagate Pritish 1")
- **Cause:** during the read-write swap, macOS FSKit mounts a **read-only duplicate** at
  a `<name> 1` path.
- **Fix:** the helper strips the FSKit duplicate after mounting (FSKit doesn't re-add it
  once removed). Manual: `diskutil unmount "/Volumes/Seagate Pritish 1"`.

### "Mount read-write" from the app does nothing / asks for a password
- **Cause:** the `sudoers` NOPASSWD rule is missing or names the wrong user.
- **Fix:** confirm `/etc/sudoers.d/ntfstore` contains
  `<your-username> ALL=(root) NOPASSWD: /usr/local/sbin/ntfs-mount-rw.sh` and validates
  (`sudo visudo -cf /etc/sudoers.d/ntfstore`). Re-run `./install.sh` to regenerate it.
  Test directly: `sudo -n /usr/local/sbin/ntfs-mount-rw.sh disk5s1` (should NOT prompt).

### First mount pops "System Extension Blocked" / mount fails until approved
- **Cause:** FUSE-T's system component needs approval on first use.
- **Fix:** **System Settings → Privacy & Security → Allow**, then retry (a reboot may be
  required once).

### `swiftc: command not found` during install
- **Fix:** `xcode-select --install` (Xcode Command Line Tools), then re-run `./install.sh`.

---

## 2. Engineering findings (why the design is what it is)

Chronological lessons that shaped the final architecture:

1. **macFUSE is a dead end on macOS 26** (too old; kext requires Reduced Security +
   Recovery). FUSE-T is kext-free and the right base.
2. **ntfs-3g links macFUSE's `libfuse.2.dylib`.** Bridging it to FUSE-T needs a
   version-patched, re-signed shim (dyld enforces the compat version).
3. **Opening the raw device requires it to be unmounted** — and FSKit re-grabs NTFS
   volumes aggressively, so you must win a race, not just "unmount then mount".
4. **A system LaunchDaemon is the wrong home:** it self-triggers destructively, and
   FUSE-T mounts don't persist outside a user session.
5. **macOS 26 auto-mount of NTFS is unreliable**, so a mount-event trigger can't be
   depended on. On-demand (button) mounting is both simpler and more robust.
6. **Yank-without-eject leaves stale mounts** that must be detected and cleared.

The net design: **mount on demand, from the user session, as root via a scoped helper**,
with the helper handling the FSKit race, dirty volumes, stale mounts and duplicates.
Full write-up in [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## 3. Full reset (nuke & reinstall)

If things are badly confused:

```bash
# 1. clear any stale/confused mounts of the drive
diskutil unmountDisk force /dev/disk5 2>/dev/null
sudo pkill -f 'ntfs-3g|go-nfsv4' 2>/dev/null

# 2. reinstall everything (idempotent)
cd NTFStore && ./install.sh

# 3. mount fresh
sudo -n /usr/local/sbin/ntfs-mount-rw.sh disk5s1   # replace with your disk id
```

To remove completely: `./uninstall.sh` (add `--all` to also remove FUSE-T & ntfs-3g).
