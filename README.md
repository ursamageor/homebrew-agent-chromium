# Agent-Chromium

One install that gives a Mac a fast browser your coding agents can control. It was made first for the
people I do IT support for, but anyone can use it.

It is two things, installed together with Homebrew, plus one setup script:

- [agent-browser](https://github.com/vercel-labs/agent-browser) by Vercel, the command-line tool that
  Claude Code, Codex, Claude Desktop, ChatGPT and other agents use to drive a browser.
- **Agent-Chromium**, [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium)
  under its own name, bundle ID and data folder, so it installs next to any other Chromium or Chrome
  and never touches their data. Nothing else about the app is changed.
- **The setup script**, which puts everything the browser needs at launch into `~/.agent-chromium`:
  the Bitwarden and Chrome Web Store extensions, a profile with a few settings, and the agent-browser
  config that names them all.

agent-browser launches the browser when an agent needs it, with a visible window, so you can watch,
log in, answer a CAPTCHA or unlock Bitwarden. The profile keeps your logins between sessions.

## Install

Written so you can hand it to your agent. Needs macOS 13 or later, on Apple Silicon or Intel.

1. **Homebrew.** Check with `command -v brew`. If it's missing, install it from [brew.sh](https://brew.sh):

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   It asks for the Mac's admin password, so the user runs it in Terminal, not the agent. At the end it
   prints two commands that put `brew` on the PATH; run them.

2. **Agent-Chromium:**

   ```sh
   brew install --cask ursamageor/agent-chromium/agent-chromium
   ```

   The full name taps `ursamageor/agent-chromium` and trusts the cask in one step; Homebrew asks for
   that trust for anything outside its own taps. Later commands can use the short name
   `agent-chromium`. Homebrew also shows agent-browser's note to run `agent-browser install`: skip
   it, that downloads a browser you don't need here.

3. **Setup:**

   ```sh
   "$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"
   ```

   This downloads the latest Bitwarden and chromium-web-store releases from GitHub (checked against
   the checksums GitHub records for them) into `~/.agent-chromium/extensions`, creates the profile in
   `~/.agent-chromium/profiles/default` with the settings below, writes
   `~/.agent-chromium/config.json`, and links `~/.agent-browser/config.json` to it (an existing
   config is backed up first). Then it asks, one at a time, whether to install the agent-chromium
   skill for each agent it finds. Run by an agent, without a terminal, it installs no skills; with
   `--skills yes` it installs all of them without asking. Re-run it any time to update the extensions.

4. **Test:**

   ```sh
   agent-browser open https://example.com    # launches Agent-Chromium with that page
   agent-browser close                       # quits it; the profile keeps everything
   ```

### After installing (by hand, once)

- **Search engine.** ungoogled-chromium ships with none and the choice can't be preset. In the
  Agent-Chromium window, open `chrome://settings/search` and pick **DuckDuckGo**: quick results, and it
  doesn't track you. The choice sticks.
- **Bitwarden.** Click the Bitwarden icon in the toolbar and log in. Your account's region (US, EU or
  self-hosted) is picked on the login screen. Then see [Bitwarden settings](#bitwarden) below.

## What's included

- **agent-browser**, Homebrew's standard package, the same as `brew install agent-browser`. It brings
  its own dependencies, Node among them, and updates with `brew upgrade`.
- **Agent-Chromium** in `/Applications`: ungoogled-chromium with its own name, bundle ID and data
  folder. No launcher, no bundled extensions, no settings inside the app.
- **`~/.agent-chromium`**, written by the setup script:
  - `config.json`, the agent-browser config: which app, which profile, which extensions, which
    flags. `~/.agent-browser/config.json` is a symlink to it.
  - `extensions/`: Bitwarden and chromium-web-store, unpacked, loaded on every launch.
  - `profiles/default/`: your profile. Logins, cookies, bookmarks and extensions you add live there.
    It starts with these settings: no welcome or import screens, Chromium's own password manager and
    Translate off, Do Not Track on, downloads saved without asking, both extensions pinned to the
    toolbar.
- **Skills**, only where you said yes during setup: `~/.agents/skills/agent-chromium`,
  `~/.claude/skills/agent-chromium`, and Claude Desktop's own skill list.

Nothing starts at login and nothing runs in the background. agent-browser starts the browser on the
first command of a session and quits it on `agent-browser close`.

## Defaults

### A visible window

The browser runs with a normal window so you can see what your agents do, and step in to log in,
answer a CAPTCHA or unlock Bitwarden. There is no headless mode with the extensions loaded: Chromium
doesn't run extensions headless, so agent-browser always opens a window for this config.

One browser at a time: the profile can be open in one browser only, so every agent uses agent-browser's
default session and shares that window. A second agent-browser session on the same config fails to
launch.

### Chrome Web Store

ungoogled-chromium can't install from the Chrome Web Store by itself.
[chromium-web-store](https://github.com/NeverDecaf/chromium-web-store) adds that: open an extension's
store page and click Add to Chromium.

Extensions update differently than in Chrome, which updates them silently. Here nothing updates on
its own:

- **Bitwarden and chromium-web-store** update when you re-run the setup script, which fetches the
  latest release of each.
- **Extensions you install from the store** are checked by chromium-web-store, which shows a count
  on its toolbar icon. Click it to update, then confirm. The icon comes pinned to the toolbar so the
  count stays in view; unpin it and you won't see updates waiting.

### Bitwarden

Bitwarden is the password manager most of the people I support already use, so it comes installed
and pinned to the toolbar. Chromium's own password manager is off, so the two don't compete.

Suggested settings (Bitwarden → Settings):

- **Account security → Vault timeout:** a short one, such as 15 minutes, with the action **Lock**.
  While the vault is unlocked, anything that controls the browser could reach it, agents included.
- **Autofill → Autofill on page load:** leave it off, so pages your agents visit aren't filled
  without you.

### Your changes stay

Changes you make in Chromium persist: settings, extensions you install, and anything else you
change. The setup script seeds the profile once and never touches it again, and upgrades replace the
app, never the profile.

The exception is Bitwarden and chromium-web-store: `config.json` loads them on every launch, so they
can't be uninstalled from the browser. Remove them from the `extensions` list in the config instead.
Disabling them in the browser sticks, too.

## Security

- **While Agent-Chromium runs, any program on this Mac can control it.** agent-browser launches it with
  a remote-debugging port (a random one, written to `DevToolsActivePort` in the profile), logged-in
  sessions included. The port isn't reachable from the network. `agent-browser close` quits the
  browser when your agents are done.
- **The profile's cookies are not protected by your keychain.** agent-browser launches every browser
  with a fixed mock key instead of the keychain, so there is no keychain prompt, and anyone who can
  read `~/.agent-chromium/profiles` can read the cookies. Treat that folder like a password store.
- **The app isn't signed with an Apple Developer ID.** The build checks ungoogled-chromium's own
  signature and then re-signs the renamed app ad hoc. The cask clears Homebrew's quarantine flag, so
  macOS opens it without a warning. Install it with Homebrew; a zip downloaded by hand gets blocked.

## More

- [Updating and uninstalling](docs/uninstall.md)
- [Building it yourself](docs/building.md), from a clone or a fork

## License

The code in this repository is MIT licensed, see [LICENSE](LICENSE). The app is ungoogled-chromium
(BSD-3-Clause), and the setup script downloads Bitwarden (GPL-3.0) and chromium-web-store (MIT) from
their own releases; see [THIRD_PARTY.md](THIRD_PARTY.md).
