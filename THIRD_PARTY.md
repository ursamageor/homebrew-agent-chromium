# Third-party software in Agent-Chromium

The release zips repackage the software below. License texts are in [`licenses/`](licenses/) and,
inside the app, in `Agent-Chromium.app/Contents/Resources/agent-chromium/licenses/`. Each build
takes the latest ungoogled-chromium release and the extension versions pinned in
[`extensions/`](extensions/); the release notes of each build name them all.

## ungoogled-chromium (macOS)

- Source: <https://github.com/ungoogled-software/ungoogled-chromium-macos> (the signed release DMG
  for each architecture, checked against its checksum and Developer ID signature before
  repackaging).
- License: BSD-3-Clause,
  [`licenses/ungoogled-chromium-BSD-3-Clause.txt`](licenses/ungoogled-chromium-BSD-3-Clause.txt).
- Chromium and the libraries it includes carry their own licenses, listed in the browser itself at
  `chrome://credits`.
- Changes: renamed to Agent-Chromium (`Info.plist`: bundle ID, name, `CrProductDirName`), main
  executable replaced by a launcher stub (the original binary is kept as `Chromium-bin`), launcher
  scripts and default preferences added, re-signed ad hoc. See `scripts/build-app.sh`.

## Bitwarden browser extension

- Source: <https://github.com/bitwarden/clients>, release `browser-v<version>`. We ship that
  release's `dist-chrome-<version>.zip`, Bitwarden's open-source build; its complete source is the
  same release's `browser-source-<version>.zip`.
- License: GPL-3.0, [`licenses/bitwarden-GPL-3.0.txt`](licenses/bitwarden-GPL-3.0.txt).
- Changes: a `key` field added to `manifest.json` (our own public key, which fixes the extension
  ID), by `scripts/build-app.sh`. Nothing else is modified.
- Bitwarden is a trademark of Bitwarden Inc. This project is not affiliated with or endorsed by
  Bitwarden.

## chromium-web-store

- Source: <https://github.com/NeverDecaf/chromium-web-store>, release `v<version>` (the `.crx`).
- License: MIT, [`licenses/chromium-web-store-MIT.txt`](licenses/chromium-web-store-MIT.txt); it
  includes code under MIT from Yusuke Kawasaki,
  [`licenses/chromium-web-store-fromXML-MIT.txt`](licenses/chromium-web-store-fromXML-MIT.txt).
- Changes: none; unpacked from the CRX.

## Not bundled

[agent-browser](https://github.com/vercel-labs/agent-browser) (Apache-2.0) is installed by
Homebrew as a separate formula dependency, not redistributed here.
