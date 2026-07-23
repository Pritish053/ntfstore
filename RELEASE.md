# Releases

Release notes and the publishing process for **NTFStore**.
For the full change list see [`CHANGELOG.md`](CHANGELOG.md); for downloads see the
[GitHub Releases page](https://github.com/Pritish053/ntfstore/releases).

---

## Latest — v1.1.0

**Kext-free NTFS read/write for macOS, in a clean menu-bar app.**

### Highlights
- 🖴 **Menu-bar app** — per-drive Mount read-write / Open in Finder / Unmount / Eject, plus Mount-all.
- 🧩 **Kext-free engine** — FUSE-T + ntfs-3g. No kernel extension, no Reduced Security, no reboots.
- 🎨 **Custom app icon** (source-art based).
- 💪 **Robust helper** — force-mounts dirty / hibernated volumes, wins the macOS FSKit auto-mount race, and auto-recovers a drive yanked without ejecting.
- 🩺 **`doctor.sh`** — self-diagnostic that checks the whole stack and prints the fix for anything broken.
- 🛠️ **`build.sh` / `make-dmg.sh`** — no-sudo dev build, and a distributable disk-image builder.
- 📖 **Docs** — architecture write-up and an exhaustive symptom → cause → fix troubleshooting guide.

### Install

**Option A — disk image (easiest)**
1. Download **`NTFStore-1.1.0.dmg`** from the [release](https://github.com/Pritish053/ntfstore/releases/latest).
2. Open it and double-click **Install NTFStore.command**.
   (If macOS blocks it: right-click → Open. It asks for your password once.)

**Option B — from source**
```bash
git clone https://github.com/Pritish053/ntfstore NTFStore
cd NTFStore && ./install.sh
```

**Requirements:** macOS 12+ (tested on macOS 26, Apple Silicon), Homebrew, Xcode Command Line Tools.

### Verify / troubleshoot
```bash
./scripts/doctor.sh
```

---

## History

| Version | Date | Notes |
|---------|------|-------|
| **v1.1.0** | 2026-07-23 | App icon, `doctor.sh`, `build.sh`, `make-dmg.sh`, troubleshooting docs, DMG installer. |
| **v1.0.0** | 2026-07-23 | Initial release — menu-bar app, FUSE-T + ntfs-3g engine, libfuse shim, mount helper, installer/uninstaller. |

---

## Cutting a new release (maintainer)

1. **Update the version** in `src/NTFStore/Info.plist`
   (`CFBundleShortVersionString` and `CFBundleVersion`).
2. **Update the docs** — add an entry to [`CHANGELOG.md`](CHANGELOG.md) and the
   *History* table above; refresh the *Latest* section.
3. **Sanity check** the build:
   ```bash
   ./scripts/build.sh          # compiles the app into ./build
   ./scripts/doctor.sh         # (on an installed machine) all checks pass
   ```
4. **Build the disk image**:
   ```bash
   ./scripts/make-dmg.sh       # -> dist/NTFStore-<version>.dmg
   ```
5. **Commit, tag and push**:
   ```bash
   git add -A && git commit -m "release: vX.Y.Z"
   git tag -a vX.Y.Z -m "NTFStore vX.Y.Z"
   git push origin main --tags
   ```
6. **Publish the GitHub release** with the DMG attached:
   ```bash
   gh release create vX.Y.Z dist/NTFStore-X.Y.Z.dmg \
     --title "NTFStore vX.Y.Z" --notes-file - <<'NOTES'
   <paste the highlights + install instructions here>
   NOTES
   ```

### Versioning
NTFStore follows [semantic versioning](https://semver.org): **MAJOR** for breaking
changes to install layout/behavior, **MINOR** for features, **PATCH** for fixes.
