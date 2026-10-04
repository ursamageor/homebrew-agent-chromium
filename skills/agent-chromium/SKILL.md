---
name: agent-chromium
description: Drive the user's Agent-Chromium browser with the agent-browser CLI. Use whenever a task needs a real browser on this Mac — browsing, logging in, filling forms, screenshots, reading pages — including anything behind the user's own logins (Bitwarden is installed).
---

# Agent-Chromium

Agent-Chromium is the user's own Chromium, set up so agents can drive it. It is one browser
process with one stable profile: the user's logins, cookies, and the Bitwarden extension are in
it. Every agent-browser command attaches to that browser (starting it in the background if it is
not running). Each agent-browser session gets its own new tab in the user's window and only sees
its own tabs; the user's tabs are never navigated. The user sees what you do.

## Start

```bash
agent-browser skills get core   # agent-browser's own instructions, matching the installed version
agent-browser open https://example.com
```

Nothing to start by hand: `~/.agent-browser/config.json` names `agent-chromium` as the browser
provider. Do not pass `--cdp`, `--provider`, `--executable-path`, or `--profile` unless the user
asks.

## Typical flow

```bash
agent-browser open https://example.com
agent-browser snapshot                    # accessibility tree with element refs
agent-browser click @e12
agent-browser fill @e7 "text"
agent-browser screenshot /tmp/page.png
agent-browser tab new https://other.example # more tabs, still only yours
agent-browser close                       # ends your session; the browser and your tabs stay open
```

Your tabs stay open after `close` so the user can see where you left off; close ones you no longer
need with `agent-browser tab close`. If agent-browser's daemon has been idle a while, your next
command opens a fresh tab rather than reusing the old one; `agent-browser open` the URL again.

## Rules of the shared profile

- It is the user's real profile. Never sign out of sites, clear data, change settings, or
  install or remove extensions unless asked.
- A number on the chromium-web-store toolbar icon means extension updates are waiting. Updating
  is the user's call (it asks them to confirm); mention it if they ask, don't act on it.
- Bitwarden may be locked. If a login form needs credentials, ask the user to unlock Bitwarden
  or fill the form themselves; do not guess passwords.
- Your tabs are visible. Tell the user what you are about to do on sites where actions have
  consequences (sending, paying, deleting).
- If agent-browser cannot connect: `agent-chromium status`, then `agent-chromium ensure`, then
  retry. `agent-chromium setup` rewrites the agent-browser config if it was changed.

## What is where

- App: `/Applications/Agent-Chromium.app`; CLI: `agent-chromium` (`status`, `ensure`, `setup`).
- Profile: `~/Library/Application Support/Agent-Chromium/User Data`.
- Remote debugging: `127.0.0.1:9222` while the browser runs (`agent-chromium status` shows it).
- Extensions: chromium-web-store (installs more from the Chrome Web Store), Bitwarden.
