# Agent-Chromium

A browser for you and your coding agents to share. It is
[ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium) repackaged as its
own app, with Bitwarden and the Chrome Web Store extension built in, and
[agent-browser](https://github.com/vercel-labs/agent-browser) wired to it. Claude Code, Codex,
ChatGPT, Claude Desktop and other agents drive it through `agent-browser`, in the same window and
logins you use yourself.

It installs next to any other Chromium or Chrome and never touches their data: its own app name,
bundle ID and profile folder.

## Install

Needs macOS 13 or later (Apple Silicon or Intel) and [Homebrew](https://brew.sh).

```sh
brew tap ursamageor/agent-chromium
brew trust ursamageor/agent-chromium
brew install --cask agent-chromium
agent-chromium setup
```

`brew trust` is Homebrew's opt-in for third-party taps. `agent-chromium setup` points agent-browser
at this browser (it writes `~/.agent-browser/config.json` only if you don't have one yet) and then
asks, one at a time, whether to install the agent skill for the agents it finds. It installs
nothing unasked. Homebrew installs agent-browser as a dependency; on a Mac it has no prebuilt
package for, it compiles it, which takes a few minutes.

Try it:

```sh
agent-browser open https://example.com    # opens a tab in the Agent-Chromium window
agent-chromium status                     # running? on which port?
```

## How it works

- **One browser, one profile, shared.** Your logins, cookies and Bitwarden live in
  `~/Library/Application Support/Agent-Chromium`. You use the app like any browser; agents attach
  to the same running browser.
- **Agents get their own tabs.** Each agent-browser session opens a new tab and only sees its own
  tabs. Your tabs are never navigated. Agent tabs stay open after the agent is done, so you can see
  what it did.
- **Started on demand.** If the browser isn't running, the first agent-browser command starts it.
  Nothing runs at login.
- **First launch** opens the search engine settings: ungoogled-chromium ships with no search
  engine, and the choice can't be preset. Pick one once; it sticks.
- **Extensions:** Bitwarden (pinned to the toolbar) and
  [chromium-web-store](https://github.com/NeverDecaf/chromium-web-store), which lets you install
  extensions from the Chrome Web Store. It checks those for updates and shows a count on its
  toolbar icon; click it to update, then confirm.

## Security

- **While Agent-Chromium runs, any program on this Mac can control it** through the
  remote-debugging port on `127.0.0.1:9222`, including your logged-in sessions. That is how agents
  connect. The port is not reachable from the network. Quit the app when your agents are done with
  it. To run it without the port, start it from a terminal with
  `AGENT_CHROMIUM_NO_DEBUG=1 agent-chromium`.
- **The app is signed ad hoc, not with a Developer ID.** Renaming the app breaks upstream's
  signature, so the build checks that signature first (the upstream DMG must be signed by
  ungoogled-chromium's Developer ID team) and then re-signs. The cask clears Homebrew's quarantine
  flag so Gatekeeper lets it open.
- **Expect a keychain prompt** ("Chromium Safe Storage") after each upgrade, because the new build
  has a new signature; choose Always Allow. If you also use ungoogled-chromium, you get it on the
  first launch too: both browsers use that same keychain item, though their profiles stay separate.

## Updating and removing

```sh
brew upgrade --cask agent-chromium              # new browser and bundled extensions; profile kept
brew uninstall --cask agent-chromium            # removes the app, keeps your profile
brew uninstall --cask --zap agent-chromium      # also deletes the profile and installed skills
```

Bitwarden and chromium-web-store come with the app and update with it.

## Building

Maintainer notes. Releases are repackaged, not compiled: the latest signed upstream DMG goes in, a
zip per architecture comes out. Needs `gh`.

```sh
scripts/build-app.sh          # download, verify, repackage: dist/Agent-Chromium-<ver>-<arch>.zip
scripts/smoke-test.sh --app build/arm64/Agent-Chromium.app   # throwaway-profile test, ~25 s
scripts/release.sh            # put the zips' checksums into the cask (dry run)
scripts/release.sh --publish  # create the GitHub release; then commit and push the cask
```

For a local install before publishing, create a dev tap once
(`brew tap-new local/agent-chromium --no-git && brew trust local/agent-chromium`); `build-app.sh`
copies a cask pointing at the local zips into it, then
`brew install --cask local/agent-chromium/agent-chromium`. To re-release the same upstream build
with changes of our own, build with `--revision 1` (then 2, …): the version becomes `<ver>_1`.
`--version <ver>` builds a specific upstream release instead of the latest.

| Path | What |
|---|---|
| `Casks/agent-chromium.rb` | the cask (the only file Homebrew reads) |
| `extensions/*.lock` | bundled extensions, pinned by URL and sha256 |
| `launcher/` | launcher stub and script (flags, profile, `agent-chromium` CLI), `setup.sh` |
| `prefs/initial_preferences.json` | settings seeded into a new profile |
| `skills/agent-chromium/` | the skill installed into agents |
| `scripts/` | build, smoke test, release, and `guarded-run.sh` for first runs of new builds |

## License

The code in this repository is MIT licensed, see [LICENSE](LICENSE). The release zips also contain
third-party software under its own licenses (BSD-3-Clause, GPL-3.0, MIT), listed in
[THIRD_PARTY.md](THIRD_PARTY.md).
