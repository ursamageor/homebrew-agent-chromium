# Third-party software

## In the release zips

The zips contain one thing: **ungoogled-chromium (macOS)**, renamed and re-signed.

- Source: <https://github.com/ungoogled-software/ungoogled-chromium-macos>, the signed release DMG
  for each architecture, checked against its checksum and Developer ID signature before repackaging.
- License: BSD-3-Clause,
  [`licenses/ungoogled-chromium-BSD-3-Clause.txt`](licenses/ungoogled-chromium-BSD-3-Clause.txt).
  Chromium and the libraries it includes carry their own licenses, listed in the browser itself at
  `chrome://credits`.
- Changes: renamed to Agent-Chromium (`Info.plist`: bundle ID, name, `CrProductDirName`) and
  re-signed ad hoc. Nothing else. See `scripts/build-app.sh`.

## Fetched by the setup script, not redistributed

`scripts/setup-agent-browser.sh` downloads these onto the user's machine as the CRX files their
publishers ship, unchanged, into `~/.agent-chromium/extensions`, and has Chromium install them:

- **Bitwarden browser extension**, from the Chrome Web Store (ID `nngceckbapebfimnlniiiahkandclblb`),
  the same file Chrome downloads, checked against the sha256 the store's update check reports.
  GPL-3.0, source at <https://github.com/bitwarden/clients>. Bitwarden is a trademark of Bitwarden
  Inc.; this project is not affiliated with or endorsed by Bitwarden.
- **chromium-web-store**, <https://github.com/NeverDecaf/chromium-web-store>, release `v<version>`,
  the `.crx`, checked against GitHub's digest. MIT.

## Installed by Homebrew as a dependency

[agent-browser](https://github.com/vercel-labs/agent-browser), Apache-2.0, is a separate Homebrew
formula the cask depends on; nothing of it is redistributed here.
