# NTFStore — Architecture & Design Notes

This documents how NTFStore works and the (surprisingly deep) macOS-26
lessons that shaped it, so future-you doesn't re-learn them the hard way.

## The goal

macOS mounts NTFS **read-only**. We want reliable **read-write** access with a
one-click menu-bar UI, as lightly as possible.

## The stack

```
  NTFStore.app  (Swift, menu bar, user session)
         │  sudo -n (NOPASSWD, scoped)
         ▼
  /usr/local/sbin/ntfs-mount-rw.sh   (root, one-shot mount helper)
         │  runs
         ▼
  ntfs-3g  ──loads──▶  /usr/local/lib/libfuse.2.dylib   (shim → FUSE-T)
         │                         │
         ▼                         ▼
  raw device /dev/diskXsY    FUSE-T (go-nfsv4, userspace NFS — no kext)
         │
         ▼
  fuse-t:/<Volume> on /Volumes/<Volume>   (read-write)
```

- **FUSE-T** — a kext-free FUSE implementation that bridges via a local NFS v4
  server (`go-nfsv4`). No kernel extension, no Reduced Security, no reboots.
- **ntfs-3g** (`ntfs-3g-mac` from the `gromgit/fuse` tap) — the read-write NTFS
  driver. It was built for **macFUSE** and links `/usr/local/lib/libfuse.2.dylib`.

## The shim

ntfs-3g requires `libfuse.2.dylib` with **compatibility version ≥ 12.0.0**.
FUSE-T ships `libfuse-t.dylib` reporting version **0.0.0**, so dyld would reject a
plain symlink. `install.sh` therefore:

1. copies FUSE-T's `libfuse-t-<ver>.dylib`,
2. patches its `LC_ID_DYLIB` current/compat version to **12.9.0**
   (`src/scripts/patch_version.py`, a small Mach-O editor that handles the fat binary),
3. sets its install-name to `/usr/local/lib/libfuse.2.dylib`,
4. ad-hoc **re-signs** it (patching invalidates the signature),
5. installs it at `/usr/local/lib/libfuse.2.dylib`.

Now ntfs-3g loads FUSE-T. (macFUSE is **not** needed — and should not be installed;
old macFUSE 4.x is incompatible with macOS 26 anyway.)

## Why a menu-bar button, not an auto-mount daemon

This is the crux. Several approaches were tried and failed on macOS 26:

1. **System `LaunchDaemon` + `StartOnMount`** — self-sabotages: the daemon fires on
   its *own* successful mount event and runs `unmountDisk force`, tearing down the
   mount it just made.
2. **FUSE-T mounts need a user login session** to persist. A mount created from the
   *system* domain (a LaunchDaemon) vanishes; the same mount from the user's session
   (Terminal, a user LaunchAgent, or the menu-bar app) persists.
3. **macOS does not reliably auto-mount NTFS.** A leftover `/etc/fstab` `noauto`
   entry intermittently suppressed FSKit — so a mount-event trigger can't be relied
   on to fire at all.
4. **FSKit fights for the device.** When macOS *does* auto-mount NTFS read-only, it
   re-grabs the raw device within milliseconds; opening `/dev/diskXsY` while it's
   mounted returns `Operation not permitted`.

The robust, simple answer: **mount on demand from the user session, as root, via a
one-shot helper** invoked by the menu-bar button (`sudo -n`). No self-triggering,
guaranteed session persistence, no dependence on macOS auto-mounting.

## The mount helper (`ntfs-mount-rw.sh`)

One-shot, idempotent, invoked explicitly. For a given `diskXsY`:

- **Already read-write and live?** Do nothing (a timed `stat` confirms liveness).
- **Stale FUSE-T mount** (drive was yanked without ejecting — `go-nfsv4`/`ntfs-3g`
  still running against a gone device)? Force-unmount + kill the backing processes,
  then remount.
- **Otherwise:** win the FSKit race by tightly alternating
  `diskutil unmountDisk force` + `ntfs-3g … -o force -o remove_hiberfile` until the
  open succeeds, then strip the read-only FSKit duplicate FSKit leaves behind.

`-o force -o remove_hiberfile` lets it mount volumes left **dirty** or in **Windows
fast-startup / hibernation** ("unsafe state"), which is common for shared drives.

## Privilege model

- Mounting needs **root** (to open the raw device). The app runs as the **user**.
- Bridge: a single `sudoers.d` rule — `<user> ALL=(root) NOPASSWD:
  /usr/local/sbin/ntfs-mount-rw.sh`. Scoped to exactly that root-owned helper, which
  validates its argument (must be an NTFS `diskXsY`). No broad privilege is granted.
- Unmount / eject / open-in-Finder need no root and are run directly by the app.

## The app (`main.swift`)

~210 lines of Swift/Cocoa. An `NSStatusItem` (menu-bar only, `LSUIElement`) that on
each open enumerates NTFS volumes (`diskutil` + `mount`), shows each with a status
dot, and offers per-drive actions. "Mount read-write" and "Mount all" shell out to
the helper via `sudo -n`; unmount/eject/open use `diskutil`/`open`.

## Files

See the table in [`../README.md`](../README.md#what-gets-installed).

## Known caveats

- ntfs-3g is reliable but not Apple-blessed — eject cleanly, keep backups.
- Built/tested on Apple Silicon, macOS 26. The `/usr/local/...` paths suit Homebrew;
  the helper auto-detects `ntfs-3g` under both `/opt/homebrew` and `/usr/local`.
