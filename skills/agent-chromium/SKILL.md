---
name: agent-chromium
description: Drive the user's Agent-Chromium browser with the agent-browser CLI. Use whenever a task needs a real browser on this Mac — browsing, logging in, filling forms, screenshots, reading pages — including anything behind the user's own logins (Bitwarden is installed).
---

# Agent-Chromium

Agent-Chromium is a second Chromium on this Mac, separate from the user's daily browser, set up
for agents. agent-browser launches it: `~/.agent-browser/config.json` (a symlink to
`~/.agent-chromium/config.json`) names the app, a persistent profile, and the extensions. The
profile keeps the user's logins and cookies between sessions, and the Bitwarden extension is
loaded. The browser runs with a visible window: the user sees what you do.

## Start

```bash
agent-browser skills get core   # agent-browser's own instructions, matching the installed version
agent-browser open https://example.com
```

Nothing to start by hand: the first command of a session launches the browser. Do not pass
`--cdp`, `--provider`, `--executable-path`, `--profile`, or `--extension` unless the user asks;
the config already has them.

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
would fight over the profile. If a launch fails with the profile in use, another session has it:
`agent-browser close` ends the default one.

## Rules of the shared profile

- It is the user's real profile. Never sign out of sites, clear data, change settings, or
  install or remove extensions unless asked.
- A number on the chromium-web-store toolbar icon means extension updates are waiting. Updating
  is the user's call (it asks them to confirm); mention it if they ask, don't act on it.
- Bitwarden may be locked. If a login form needs credentials, ask the user to unlock Bitwarden
  or fill the form themselves; do not guess passwords.
- Your window is visible. Tell the user what you are about to do on sites where actions have
  consequences (sending, paying, deleting).

## What is where

- App: `/Applications/Agent-Chromium.app` (plain ungoogled-chromium under its own name).
- Everything else: `~/.agent-chromium/` — `config.json`, `profiles/default` (the profile),
  `extensions/` (unpacked: chromium-web-store, which installs more from the Chrome Web Store,
  and Bitwarden).
- To repair the setup or update the extensions:
  `"$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"`.
