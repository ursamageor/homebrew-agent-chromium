# Updating and uninstalling

## Updating

```sh
brew upgrade --cask agent-chromium    # the browser and its bundled extensions; your profile is kept
brew upgrade agent-browser            # agent-browser updates on its own schedule
```

A plain `brew upgrade` does both. After a browser upgrade, expect one keychain prompt ("Chromium Safe
Storage"); choose Always Allow. Extensions you installed from the Chrome Web Store don't update with
the app: chromium-web-store shows a count on its toolbar icon when updates are waiting.

## Uninstalling

Quit Agent-Chromium first, then pick one:

```sh
brew uninstall --cask agent-chromium          # removes the app, keeps your profile
brew uninstall --cask --zap agent-chromium    # also deletes the profile and the installed skills
```

`--zap` deletes:

- the profile: `~/Library/Application Support/Agent-Chromium`
- the cache: `~/Library/Caches/Agent-Chromium`
- the app's preferences and saved window state in `~/Library/Preferences` and
  `~/Library/Saved Application State` (`org.agent-chromium.browser`)
- the skills: `~/.agents/skills/agent-chromium`, `~/.claude/skills/agent-chromium`,
  `~/.codex/skills/agent-chromium`

## What stays

Neither command removes these:

- **agent-browser and its dependencies** (Node and about two dozen libraries). Other tools may use them.
  To remove them too:

  ```sh
  brew uninstall agent-browser
  brew autoremove                   # dependencies nothing else needs any more
  ```

- **`~/.agent-browser/config.json`**, agent-browser's config. `agent-chromium setup` wrote it if you
  had none; it still points at the removed app, so agent-browser commands fail until you change it.
  Delete it if you don't use agent-browser any more, or remove the `agent-chromium` entries.
- **The skill in Claude Desktop**, if you installed it there. Remove it in Claude's settings.
- **The "Chromium Safe Storage" keychain item.** ungoogled-chromium uses the same item, so leave it if
  you have that browser. Otherwise you can delete it in Keychain Access.
- **The tap.** `brew untap ursamageor/agent-chromium` removes it.
