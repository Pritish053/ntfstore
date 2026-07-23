# TODO / Backlog

Optional enhancements for NTFStore. Nothing here is required — the app is complete
and shipped. These are "if it grows" ideas.

## Distribution
- [ ] **Homebrew tap** — publish so users can `brew install pritish053/tap/ntfstore`.
  - Create a `homebrew-tap` repo, add a `Casks/ntfstore.rb` (or a formula) pointing
    at the release DMG/tarball with the SHA256.
  - Slicker install; downside is extra maintenance (bump the cask each release).
- [ ] **Notarization / Developer ID signing** — removes the Gatekeeper
  "unidentified developer" warning on the DMG. Requires a paid Apple Developer
  account ($99/yr). Until then, users right-click → Open on first launch.

## Repo polish
- [ ] **Screenshot / GIF** of the menu bar and drop-down menu in the README.
- [ ] **GitHub Actions CI** — build the app + `bash -n`/`plutil` lint on push.
- [ ] **Issue templates / CONTRIBUTING.md** if opening up to contributions.

## App ideas
- [ ] Optional preference toggle for auto-mount-on-attach (was intentionally left out
  on macOS 26 for reliability — revisit if FSKit behavior stabilizes).
- [ ] Show per-drive capacity / free space in the menu.
