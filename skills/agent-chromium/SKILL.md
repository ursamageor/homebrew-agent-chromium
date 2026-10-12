---
name: agent-chromium
description: Drive the user's Agent-Chromium browser with the agent-browser CLI. Use whenever a task needs a real browser on this Mac — browsing, logging in, filling forms, screenshots, reading pages — including anything behind the user's own logins (Bitwarden is installed).
---

# Agent-Chromium

Agent-Chromium is a second Chromium on this Mac, separate from the user's daily browser, set up
for agents. agent-browser launches it: `~/.agent-browser/config.json` (a symlink to
`~/.agent-chromium/config.json`) names the app and its profile. The profile is the app's own,
the same one the user gets when they open Agent-Chromium from the Dock, so logins, cookies and
the Bitwarden and Chromium Web Store extensions are there either way. The browser runs with a
visible window: the user sees what you do.

## Start

```bash
~/.agent-chromium/bin/check          # closed, agent, or user (see below)
agent-browser skills get core        # agent-browser's own instructions, matching the installed version
agent-browser open https://example.com
```

Nothing to start by hand: the first command of a session launches the browser. Do not pass
`--cdp`, `--provider`, `--executable-path`, `--profile`, or `--extension` unless the user asks;
the config already has them.

## If the user opened the browser themselves

Run `~/.agent-chromium/bin/check` before the first browser command of a task. It prints:

- `closed`: nothing is running; your first command launches the browser.
- `agent`: launched by agent-browser; drive it.
- `user`: the user opened Agent-Chromium from the Dock or Finder. That browser has no debugging
  port and holds the profile, so agent-browser cannot attach to it and cannot launch another.
  Ask the user: "Agent-Chromium is open. OK to quit and reopen it so I can use it?" Then
  `~/.agent-chromium/bin/check --quit`, which quits it normally, and go on with agent-browser.
  Their tabs come back if "Continue where you left off" is set in the browser's startup
  settings. After a restore, agent-browser attaches to all tabs and starts on one of them, not
  necessarily the one the user was looking at: run `agent-browser tab list`, and if a task is
  about something already open, confirm with the user which tab before acting in it.

Never quit the browser without asking; never force-kill it.

## Typical flow

```bash
agent-browser open https://example.com
agent-browser snapshot                    # accessibility tree with element refs
agent-browser click @e12
agent-browser fill @e7 "text"
agent-browser screenshot /tmp/page.png
agent-browser tab new https://other.example
agent-browser close                       # quits the browser; the profile keeps logins
```

`close` quits the browser, so leave it open while the user may want to look at what you did, and
close it when you are done or when asked. A headed browser is never closed by the idle timeout.

## One browser at a time

The profile can be open in one browser only. Every command without `--session` uses the
`default` session, which is the one browser; don't start other sessions on this config, they
would fight over the profile. If a launch fails with the profile in use, another session has it
(`agent-browser close` ends the default one) or the user has (see above).

## Rules of the shared profile

- It is the user's real profile. Never sign out of sites, clear data, change settings, or
  install or remove extensions unless asked.
- The first launch after setup has Bitwarden and Chromium Web Store installed but switched off
  until the user approves them once in `chrome://extensions`. If the Bitwarden icon is missing,
  that is why: ask the user to switch them on there, or offer to open the page for them.
- A number on the chromium-web-store toolbar icon means extension updates are waiting. Updating
  is the user's call (it asks them to confirm); mention it if they ask, don't act on it.
- Bitwarden may be locked. If a login form needs credentials, ask the user to unlock Bitwarden
  or fill the form themselves; do not guess passwords.
- Your window is visible. Tell the user what you are about to do on sites where actions have
  consequences (sending, paying, deleting).

## What is where

- App: `/Applications/Agent-Chromium.app` (plain ungoogled-chromium under its own name).
- Profile: `~/Library/Application Support/Agent-Chromium`, the app's own data folder. Its
  `External Extensions/` folder tells Chromium which extensions to install from
  `~/.agent-chromium/extensions/`.
- `~/.agent-chromium/`: `config.json`, `extensions/` (the CRX files), `bin/chromium` (what
  agent-browser launches: the app, minus two flags), `bin/check`.
- To repair the setup or update the extensions:
  `"$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"`.
