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
~/.agent-chromium/bin/check               # closed, agent, or user (see below)
agent-browser open https://example.com    # the first command of a session launches the browser
```

Don't pass launch flags (`--headless`, `--profile`, `--executable-path`, `--extension`, `--args`,
`--provider`) unless the user asks: the config sets them, and a command with a different set makes
agent-browser relaunch the browser, which fails while it is open. `--extension` would also switch
off the extensions installed in the profile. For a command's syntax, `agent-browser <command>
--help` is enough.

## If the user opened the browser themselves

`~/.agent-chromium/bin/check`, before the first browser command of a task, prints:

- `closed`: nothing is running; your first command launches the browser.
- `agent`: launched by agent-browser; drive it. It may hold tabs the user is using: do your work
  in `agent-browser tab new <url>`, not in their tab.
- `user`: the user opened Agent-Chromium from the Dock or Finder. That browser has no debugging
  port and holds the profile, so agent-browser cannot attach to it and cannot launch another.
  Ask the user: "Agent-Chromium is open. OK to restart it so I can use it?" Then
  `~/.agent-chromium/bin/check --quit`, which quits it normally, and go on with agent-browser.
  Their tabs come back if "Continue where you left off" is set in the browser's startup
  settings. After a restore, agent-browser attaches to all tabs and starts on one of them, not
  necessarily the one the user was looking at: run `agent-browser tab list`, open a new tab for
  your own work, and if the task is about something already open, confirm with the user which
  tab before acting in it.

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
close it when work is definitively done or when asked. A headed browser is never closed by the
idle timeout. Downloads land in `~/Downloads` without a prompt.

## One browser at a time

The profile can be open in one browser only. Every command without `--session` uses the
`default` session, which is the one browser; don't start other sessions on this config, they
would fight over the profile. If a launch fails with the profile in use, another session has it
(`agent-browser close` ends the default one) or the user has (see above).

## Check with the user first

This browser is logged in as the user. Before any action that is hard to undo, stop and ask, and
act only after an explicit yes for that action:

- **Sending**: messages, email, forms that notify someone, posts, comments.
- **Paying**: purchases, transfers, subscriptions, anything with a card or an account balance.
- **Deleting**: files, records, messages, accounts, anything the site calls remove or delete.
- **Changing account state**: passwords, email addresses, permissions, sharing, sign-outs.

Say what you are about to do, on which site, with what values, and wait. A yes for one action is
not a yes for the next. If a page does something you did not expect (a payment step appears, a
confirmation names the wrong thing), stop and tell the user rather than continuing.

## Rules of the shared profile

- It is the user's real profile. Never sign out of sites, clear data, change settings, or
  install or remove extensions unless asked.
- The first launch after setup has Bitwarden and Chromium Web Store installed but switched off
  until the user approves them once in `chrome://extensions`. If the Bitwarden icon is missing,
  that is why: `agent-browser open chrome://extensions` and ask the user to flip the switches;
  don't flip them yourself. For the rest of the one-time setup, open the welcome page:
  `agent-browser open "file://$HOME/.agent-chromium/welcome.html"`.
- A number on the chromium-web-store toolbar icon means extension updates are waiting. Updating
  is the user's call (it asks them to confirm); mention it if they ask, don't act on it.
- Bitwarden may be locked. If a login form needs credentials, ask the user to unlock Bitwarden
  or fill the form themselves; do not guess passwords.
- Your window is visible. Narrate what you are doing on sites where it matters.

## agent-browser's own skills

agent-browser ships skills of its own, matching the installed version (`agent-browser skills
list`). The one worth having installed is **core**, its usage guide: snapshot and refs, waiting,
forms, tabs, data extraction, troubleshooting. Install it as a symlink, so `brew upgrade` keeps it
current:

```bash
ln -s "$(agent-browser skills path core)" ~/.agents/skills/agent-browser-core    # Codex, most agents
ln -s "$(agent-browser skills path core)" ~/.claude/skills/agent-browser-core    # Claude Code
```

One part of it does not apply here: it tells agents to always use a named session and to persist
state with `--restore`. On this setup that means a second browser on the same profile, which fails
on the profile lock. Use the default session, as above. Without installing it, `agent-browser
skills get core` prints it (38 KB).

The others, for reference; none is needed for everyday browsing:

| Skill | For |
|---|---|
| `derive-client` | reverse-engineer a site's internal API from recorded browser traffic |
| `dogfood` | systematically explore and test a web app for bugs and UX problems |
| `electron` | automate Electron desktop apps (VS Code, Slack, Discord, Figma, …) |
| `slack` | work in a Slack workspace through the browser |
| `webmcp-gen` | build and validate experimental WebMCP tools for a web app |
| `protected-vercel-deployments` | open Vercel deployments behind deployment protection |
| `vercel-sandbox`, `agentcore` | run agent-browser on a Vercel Sandbox or AWS AgentCore cloud browser instead |

`agent-browser skills get <name>` prints any of them.

## What is where

- App: `/Applications/Agent-Chromium.app` (plain ungoogled-chromium under its own name).
- Profile: `~/Library/Application Support/Agent-Chromium`, the app's own data folder. Its
  `External Extensions/` folder tells Chromium which extensions to install from
  `~/.agent-chromium/extensions/`.
- `~/.agent-chromium/`: `config.json`, `extensions/` (the CRX files), `bin/chromium` (what
  agent-browser launches: the app, minus two flags), `bin/check`, `welcome.html`.
- To repair the setup or update the extensions:
  `"$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"`.
