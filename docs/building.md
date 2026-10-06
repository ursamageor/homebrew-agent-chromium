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
scripts/smoke-test.sh --app build/arm64/Agent-Chromium.app   # throwaway-profile test, ~25 s
```

`build-app.sh` downloads the DMG through `gh`, checks it against the sha256 GitHub records for it and
against ungoogled-chromium's Developer ID signature, and only then changes anything. It renames the
app, adds the launcher, settings and extensions, re-signs it ad hoc and zips it.

- `--arch arm64` or `--arch x86_64` builds one architecture; the default is both.
- `--version <ver>` builds a specific upstream release instead of the latest.
- `--revision 1` (then 2, …) re-releases the same upstream build with changes of your own: the
  version becomes `<ver>_1`.
- A zip is only rebuilt when something that goes into it changed. A rebuild never gives the same
  bytes, so the release checksums would change for nothing. `--force` rebuilds anyway.

The smoke test runs the built app on a throwaway profile and its own port, so it can run next to
your real Agent-Chromium. The x86_64 build runs under Rosetta. `scripts/smoke-test.sh --help` lists
what it covers.

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

1. In `Casks/agent-chromium.rb`, change `url` and `homepage` to your repository.
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
| `extensions/*.lock` | bundled extensions, pinned by URL and sha256 |
| `launcher/` | launcher stub and script (flags, profile, `agent-chromium` command), `setup.sh` |
| `prefs/initial_preferences.json` | settings seeded into a new profile |
| `skills/agent-chromium/` | the skill installed into agents |
| `scripts/` | build, smoke test, release, and `guarded-run.sh` for first runs of new builds |
