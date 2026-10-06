# Agent-Chromium

One install that gives a Mac a fast browser your coding agents can control. It was made first for the
people I do IT support for, but anyone can use it.

It is two things, installed together with Homebrew:

- [agent-browser](https://github.com/vercel-labs/agent-browser) by Vercel, the command-line tool that
  Claude Code, Codex, Claude Desktop, ChatGPT and other agents use to drive a browser.
- **Agent-Chromium**, a browser app built from
  [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), repackaged with a few
  settings and extensions already in place.

You and your agents share the browser: same window, same logins. Agents work in tabs of their own. It
installs next to any other Chromium or Chrome and never touches their data.

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
   agent-chromium setup
   ```

   This points agent-browser at Agent-Chromium (it writes `~/.agent-browser/config.json`, only if
   there is none yet). Then it asks, one at a time, whether to install the agent-chromium skill for
   each agent it finds. Run by an agent, without a terminal, it installs no skills; with
   `--skills yes` it installs all of them without asking.

4. **Test:**

   ```sh
   agent-browser open https://example.com    # opens a tab in the Agent-Chromium window
   agent-chromium status                     # running? on which port?
   ```

### After installing (by hand, once)

- **Search engine.** Open Agent-Chromium from Applications or Spotlight. The first time, it opens the
  search engine settings, because ungoogled-chromium ships with none and the choice can't be preset.
  Pick **DuckDuckGo**: quick results, and it doesn't track you. The choice sticks.
- **Bitwarden.** Click the Bitwarden icon in the toolbar and log in. Your account's region (US, EU or
  self-hosted) is picked on the login screen. Then see [Bitwarden settings](#bitwarden) below.

## What's included

- **agent-browser**, Homebrew's standard package, the same as `brew install agent-browser`. It brings
  its own dependencies, Node among them, and updates with `brew upgrade`. Only its config file is
  ours, written by `agent-chromium setup`.
- **Agent-Chromium** in `/Applications`: ungoogled-chromium with its own name, bundle ID and profile,
  so it can sit next to another Chromium. It adds:
  - **settings** for a new profile: no welcome or import screens, no default-browser nagging,
    Chromium's own password manager and Translate off, Do Not Track on, downloads saved without
    asking;
  - **extensions:** Bitwarden and the Chrome Web Store extension (see [Defaults](#defaults));
  - the **`agent-chromium` command**, which agent-browser uses to find and start the browser.
- **Your profile**, created on first launch: `~/Library/Application Support/Agent-Chromium/User Data`.
  Logins, cookies, bookmarks and extensions live there. Upgrades keep it.
- **Skills**, only where you said yes during setup: `~/.agents/skills/agent-chromium`,
  `~/.claude/skills/agent-chromium`, and Claude Desktop's own skill list.

Nothing starts at login and nothing runs in the background. If the browser isn't running, the first
agent-browser command starts it.

## Defaults

### A visible window

The browser runs with a normal window so you can see what your agents do, and step in to log in,
answer a CAPTCHA or unlock Bitwarden. Agents open tabs of their own and never touch yours; their tabs
stay open when they're done.

For runs where nobody needs to watch, quit Agent-Chromium and start it headless. It uses the same
profile and port, so agent-browser connects to it the same way:

```sh
agent-chromium --headless &               # no window, no Dock icon
agent-browser open https://example.com
agent-chromium status                     # shows the pid; stop it with: kill <pid>
```

Only one of the two can run at a time, since they share the profile. Headless, there's no toolbar, so
Bitwarden can't be unlocked. Not checked yet: whether sites you're logged into in the window stay
logged in headless.

### Chrome Web Store

ungoogled-chromium can't install from the Chrome Web Store by itself.
[chromium-web-store](https://github.com/NeverDecaf/chromium-web-store) adds that: open an extension's
store page and click Add to Chromium.

Extensions update differently than in Chrome, which updates them silently. Here nothing updates on
its own:

- **Bitwarden and chromium-web-store** come with the app and update with `brew upgrade --cask
  agent-chromium`.
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
change. Upgrades replace the app, never the profile, so all of it stays as it is after `brew upgrade`;
the settings above only seed a new profile.

The exception is the packaged extensions, Bitwarden and chromium-web-store. They are part of the app
and load on every start, so they can't be uninstalled. You can disable them, though, and that sticks.

## Security

- **While Agent-Chromium runs, any program on this Mac can control it** through the remote-debugging
  port on `127.0.0.1:9222`, logged-in sessions included. That's how agents connect. The port isn't
  reachable from the network. Quit the app when your agents are done. To start it without the port:
  `AGENT_CHROMIUM_NO_DEBUG=1 agent-chromium`.
- **The app isn't signed with an Apple Developer ID.** The build checks ungoogled-chromium's own
  signature and then re-signs the renamed app ad hoc. The cask clears Homebrew's quarantine flag, so
  macOS opens it without a warning. Install it with Homebrew; a zip downloaded by hand gets blocked.
- **Expect a keychain prompt** ("Chromium Safe Storage") after each upgrade; choose Always Allow. If
  you also use ungoogled-chromium, it appears on the first launch too: both use that keychain item,
  though their profiles stay separate.

## More

- [Updating and uninstalling](docs/uninstall.md)
- [Building it yourself](docs/building.md), from a clone or a fork

## License

The code in this repository is MIT licensed, see [LICENSE](LICENSE). The app also contains
third-party software under its own licenses (BSD-3-Clause, GPL-3.0, MIT), listed in
[THIRD_PARTY.md](THIRD_PARTY.md).
