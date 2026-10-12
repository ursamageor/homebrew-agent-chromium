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

`scripts/setup-agent-browser.sh` downloads these from their own GitHub releases onto the user's
machine and unpacks them into `~/.agent-chromium/extensions`:

- **Bitwarden browser extension**, <https://github.com/bitwarden/clients>, release
  `browser-v<version>`, asset `dist-chrome-<version>.zip`. GPL-3.0. The script adds a `key` field to
  `manifest.json` (our own public key, which fixes the extension ID) and removes the reserved
  `_metadata` folder, which Chromium refuses in unpacked extensions. Bitwarden is a trademark of
  Bitwarden Inc.; this project is not affiliated with or endorsed by Bitwarden.
- **chromium-web-store**, <https://github.com/NeverDecaf/chromium-web-store>, release `v<version>`,
  the `.crx`. MIT. Unpacked as is.

## Installed by Homebrew as a dependency

[agent-browser](https://github.com/vercel-labs/agent-browser), Apache-2.0, is a separate Homebrew
formula the cask depends on; nothing of it is redistributed here.
