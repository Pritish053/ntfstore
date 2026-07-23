# Changelog

All notable changes to NTFStore are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [1.1.0] — 2026-07-23

### Added
- App icon — graphite squircle with an electric-blue drive module, read/write
  chevrons and a NTFS wordmark. `scripts/make-icon.swift` renders it and
  `AppIcon.icns` is bundled; `install.sh` installs it into the app.
- `scripts/build.sh` — no-sudo dev build of the app into `./build` (with `--run`).
- `docs/TROUBLESHOOTING.md` — every issue hit during development with
  symptom → cause → fix, an engineering findings log, and a full-reset procedure.
- `scripts/doctor.sh` — read-only self-diagnostic that checks the whole stack
  (engine, shim, helper, sudoers, app, login item, drive state) and prints fixes.
- README "Troubleshooting" section linking both.

## [1.0.0] — 2026-07-23

### Added
- Menu-bar app **NTFStore** (Swift/Cocoa, `LSUIElement`) with per-drive
  Mount read-write / Open in Finder / Unmount / Eject, plus Mount-all and Refresh.
- Kext-free NTFS read/write engine: **FUSE-T** + **ntfs-3g**.
- `libfuse.2.dylib` **shim** (version-patched FUSE-T library) so ntfs-3g loads FUSE-T.
- Privileged one-shot mount helper `ntfs-mount-rw.sh`:
  - stale-mount detection & recovery (drive yanked without ejecting),
  - `-o force -o remove_hiberfile` for dirty / hibernated volumes,
  - tight FSKit-race loop and read-only duplicate cleanup.
- Scoped `sudoers` NOPASSWD rule for the mount helper (per installing user).
- `install.sh` (idempotent) and `uninstall.sh` (`--all` to also remove brew packages).
- Login item so the app starts automatically.
- Docs: `README.md`, `docs/ARCHITECTURE.md`.

### Notes
- Built and tested on macOS 26 (Apple Silicon).
- Replaces an earlier system-LaunchDaemon auto-mount approach that self-sabotaged;
  mounting now runs on demand from the user session for reliability and persistence.
