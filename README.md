# Agent-Chromium

One install that gives a Mac a fast browser your coding agents can control. It was made first for the
people I do IT support for, but anyone can use it.

It is two things, installed together with Homebrew, plus one setup script:

- [agent-browser](https://github.com/vercel-labs/agent-browser) by Vercel, the command-line tool that
  Claude Code, Codex, Claude Desktop, ChatGPT and other agents use to drive a browser.
- **Agent-Chromium**, [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium)
  under its own name, bundle ID and data folder, so it installs next to any other Chromium or Chrome
  and never touches their data. Nothing else about the app is changed.
- **The setup script**, which fetches the Bitwarden and Chrome Web Store extensions, seeds the
  browser's profile with a few settings, and writes the agent-browser config that ties it together.

agent-browser launches the browser when an agent needs it, with a visible window, so you can watch,
log in, answer a CAPTCHA or unlock Bitwarden. It is the same browser, with the same profile, that
you get by opening Agent-Chromium from the Dock: your logins and extensions are there either way.

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

   This downloads the latest Bitwarden (from the Chrome Web Store) and chromium-web-store (from
   GitHub), each checked against the checksum its source publishes, into
   `~/.agent-chromium/extensions`, and tells Chromium to install them from there. It creates the
   profile with the settings below, writes `~/.agent-chromium/config.json`, and links
   `~/.agent-browser/config.json` to it (an existing config is backed up first). Then it asks, one
   at a time, whether to install the agent-chromium skill for each agent it finds. Run by an agent,
   without a terminal, it installs no skills; with `--skills yes` it installs all of them without
   asking. Re-run it any time to update the extensions.

   When the profile is new, it ends by opening Agent-Chromium on a welcome page with the four
   settings below, each in its own tab next to it. A keychain prompt for "Chromium Safe Storage"
   may appear with that first launch: click **Always Allow**. That's the key that protects the
   browser's cookies.

4. **Test:**

   ```sh
   agent-browser open https://example.com    # opens that page in Agent-Chromium
   agent-browser close                       # quits it; the profile keeps everything
   ```

### After installing (by hand, once)

Chromium protects these settings against being preset, so they're a few clicks in the
Agent-Chromium window. The welcome page walks through them (`~/.agent-chromium/welcome.html`, and
`setup-agent-browser.sh --welcome` opens it again):

- **Extensions.** Open `chrome://extensions` and switch on **Bitwarden** and **Chromium Web Store**.
  They are installed but off: Chromium asks once for any extension that didn't come from the store.
- **Startup.** In `chrome://settings/onStartup` pick **Continue where you left off**, so your tabs
  come back whenever the browser is restarted, by you or by an agent.
- **Search engine.** ungoogled-chromium ships with none. In `chrome://settings/search` pick
  **DuckDuckGo**: quick results, and it doesn't track you.
- **Bitwarden.** Click the Bitwarden icon in the toolbar and log in. Your account's region (US, EU or
  self-hosted) is picked on the login screen. Then see [Bitwarden settings](#bitwarden) below.

## What's included

- **agent-browser**, Homebrew's standard package, the same as `brew install agent-browser`. It brings
  its own dependencies, Node among them, and updates with `brew upgrade`.
- **Agent-Chromium** in `/Applications`: ungoogled-chromium with its own name, bundle ID and data
  folder. No launcher, no bundled extensions, no settings inside the app.
- **Your profile** in `~/Library/Application Support/Agent-Chromium`, the app's own data folder.
  Logins, cookies, bookmarks and extensions live there. It starts with these settings: no welcome or
  import screens, Chromium's own password manager and Translate off, Do Not Track on, downloads saved
  without asking, both extensions pinned to the toolbar. Its `External Extensions` folder is how the
  setup script hands Chromium the two extensions to install.
- **`~/.agent-chromium`**, written by the setup script:
  - `config.json`, the agent-browser config: what to launch, which profile, which flags.
    `~/.agent-browser/config.json` is a symlink to it.
  - `extensions/`: the Bitwarden and chromium-web-store CRX files, as published.
  - `bin/chromium`, what agent-browser launches. It runs the app minus two flags agent-browser
    always adds (see [Security](#security)). `bin/check` tells an agent whether the browser is
    closed, launched by agent-browser, or opened by you.
- **Skills**, only where you said yes during setup: `~/.agents/skills/agent-chromium`,
  `~/.claude/skills/agent-chromium`, and Claude Desktop's own skill list.

Nothing starts at login and nothing runs in the background. agent-browser starts the browser on the
first command of a session and quits it on `agent-browser close`.

## Defaults

### A visible window

The browser runs with a normal window so you can see what your agents do, and step in to log in,
answer a CAPTCHA or unlock Bitwarden.

One browser at a time: the profile can be open in one browser only. Every agent uses agent-browser's
default session and shares that window. If you opened Agent-Chromium yourself, from the Dock, an
agent can't attach to it (that browser has no debugging port); the skill tells agents to ask you
before quitting and reopening it. With "Continue where you left off" set, your tabs come back.

### Chrome Web Store

ungoogled-chromium can't install from the Chrome Web Store by itself.
[chromium-web-store](https://github.com/NeverDecaf/chromium-web-store) adds that: open an extension's
store page and click Add to Chromium.

Extensions update differently than in Chrome, which updates them silently. Here nothing updates on
its own:

- **Bitwarden and chromium-web-store** update when you re-run the setup script, which fetches the
  latest version of each; Chromium installs it on the next start.
- **Extensions you install from the store** are checked by chromium-web-store, which shows a count
  on its toolbar icon. Click it to update, then confirm. The icon comes pinned to the toolbar so the
  count stays in view; unpin it and you won't see updates waiting.

### Bitwarden

Bitwarden is the password manager most of the people I support already use, so it comes installed
and pinned to the toolbar. It's the Chrome Web Store build, under its store ID, so the Bitwarden
desktop app recognises it (for unlocking with Touch ID). Chromium's own password manager is off, so
the two don't compete.

Suggested settings (Bitwarden → Settings):

- **Account security → Vault timeout:** a short one, such as 15 minutes, with the action **Lock**.
  While the vault is unlocked, anything that controls the browser could reach it, agents included.
- **Autofill → Autofill on page load:** leave it off, so pages your agents visit aren't filled
  without you.

### Your changes stay

Changes you make in Chromium persist: settings, extensions you install, and anything else you
change. The setup script seeds the profile once and never touches it again, and upgrades replace the
app, never the profile. Bitwarden and chromium-web-store are ordinary installed extensions: disable
or remove them like any other. (Re-running the setup script reinstalls a removed one; delete its
file from the profile's `External Extensions` folder to stop that.)

## Security

- **While Agent-Chromium runs under an agent, any program on this Mac can control it.** agent-browser
  launches it with a remote-debugging port (a random one, written to `DevToolsActivePort` in the
  profile), logged-in sessions included. The port isn't reachable from the network, and a browser
  you open yourself has no port. `agent-browser close` quits the browser when your agents are done.
- **Cookies are protected by your keychain.** agent-browser normally launches browsers with a fixed
  fake key instead of the keychain, so that automated runs never see a prompt; `bin/chromium` drops
  that flag. The real key lives in your login keychain and is only released to apps you've approved,
  which is why the "Chromium Safe Storage" prompt appears once, and again after each upgrade. The
  item is shared with any other Chromium on the Mac; the data folders stay separate.
- **The app isn't signed with an Apple Developer ID.** The build checks ungoogled-chromium's own
  signature and then re-signs the renamed app ad hoc. The cask clears Homebrew's quarantine flag, so
  macOS opens it without a warning. Install it with Homebrew; a zip downloaded by hand gets blocked.

## More

- [Updating and uninstalling](docs/uninstall.md)
- [Building it yourself](docs/building.md), from a clone or a fork

## License

The code in this repository is MIT licensed, see [LICENSE](LICENSE). The app is ungoogled-chromium
(BSD-3-Clause), and the setup script downloads Bitwarden (GPL-3.0) from the Chrome Web Store and
chromium-web-store (MIT) from its GitHub releases; see [THIRD_PARTY.md](THIRD_PARTY.md).
