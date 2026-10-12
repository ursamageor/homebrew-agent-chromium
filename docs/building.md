# Building it yourself

Releases are repackaged, not compiled. The latest signed ungoogled-chromium DMG goes in, a zip per
architecture comes out. Building takes a few minutes and needs a Mac with the Xcode command-line tools
(`xcode-select --install`), [gh](https://cli.github.com) logged in, and agent-browser for the smoke
test.

## From a clone

```sh
git clone https://github.com/ursamageor/homebrew-agent-chromium
cd homebrew-agent-chromium
scripts/build-app.sh          # download, verify, repackage: dist/Agent-Chromium-<ver>-<arch>.zip
scripts/smoke-test.sh --app build/arm64/Agent-Chromium.app   # throwaway-profile test, ~1 min
```

`build-app.sh` downloads the DMG through `gh`, checks it against the sha256 GitHub records for it and
against ungoogled-chromium's Developer ID signature, and only then changes anything. It renames the
app, sets its bundle ID and data-folder name in `Info.plist`, re-signs it ad hoc and zips it. That is
the whole change: everything else (extensions, profile, flags) lives in `~/.agent-chromium` and is
set up on the user's machine by `scripts/setup-agent-browser.sh`.

- `--arch arm64` or `--arch x86_64` builds one architecture; the default is both.
- `--version <ver>` builds a specific upstream release instead of the latest.
- `--revision 1` (then 2, …) re-releases the same upstream build with changes of your own: the
  version becomes `<ver>_1`.
- A zip is only rebuilt when something that goes into it changed. A rebuild never gives the same
  bytes, so the release checksums would change for nothing. `--force` rebuilds anyway.

The smoke test checks the bundle, then runs the setup script into temp folders (so it downloads the
extensions and seeds a throwaway profile), launches the app through agent-browser with a config
pointing at them, and checks the launch flags, the extensions Chromium installs, the tabs and the
profile after quit, all on its own session. It can run next to your real Agent-Chromium. The x86_64
build runs under Rosetta. `scripts/smoke-test.sh --help` lists what it covers.

## Installing your build

Create a local tap once:

```sh
brew tap-new local/agent-chromium --no-git
brew trust local/agent-chromium
```

From then on, every `build-app.sh` run copies a cask pointing at the local zips into it. Install with
`brew install --cask local/agent-chromium/agent-chromium`.

## Publishing from a fork

The repository has to be named `homebrew-<name>` for `brew tap <you>/<name>` to find it.

1. In `Casks/agent-chromium.rb`, change `url` and `homepage` to your repository, and the tap name in
   the caveats.
2. Build, then publish:

   ```sh
   scripts/release.sh            # put the zips' checksums into the cask (dry run)
   scripts/release.sh --publish  # create the GitHub release v<version> with both zips
   ```

3. Commit and push the cask right away: users get the version the pushed cask names, and its files
   must already be on the release.

## Layout

| Path | What |
|---|---|
| `Casks/agent-chromium.rb` | the cask (the only file Homebrew reads) |
| `scripts/build-app.sh` | the build: the only thing that goes into the zips besides the DMG |
| `scripts/setup-agent-browser.sh` | the user-side setup: `~/.agent-chromium`, the profile's External Extensions, the config symlink, skills |
| `extensions/*.lock` | where each extension comes from: the Chrome Web Store (by ID) or a GitHub release asset |
| `prefs/initial_preferences.json` | settings seeded into a new profile |
| `skills/agent-chromium/` | the skill installed into agents |
| `scripts/` | also the smoke test, the release script, and `guarded-run.sh` for first runs of new builds |
