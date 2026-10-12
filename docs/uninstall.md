# Updating and uninstalling

## Updating

```sh
brew upgrade --cask agent-chromium    # the browser; your profile is kept
brew upgrade agent-browser            # agent-browser updates on its own schedule
"$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"   # the extensions
```

A plain `brew upgrade` does the first two. The setup script fetches the latest Bitwarden and
chromium-web-store releases and replaces the installed copies; everything else it finds in place
(profile, config, skills) it leaves alone or refreshes. Extensions you installed from the Chrome Web
Store don't update with any of this: chromium-web-store shows a count on its toolbar icon when
updates are waiting.

## Uninstalling

Quit Agent-Chromium first (`agent-browser close`), then pick one:

```sh
brew uninstall --cask agent-chromium          # removes the app, keeps ~/.agent-chromium
brew uninstall --cask --zap agent-chromium    # also deletes the profile, extensions, config and skills
```

`--zap` deletes:

- `~/.agent-chromium`: the profile, the extensions, the config and the downloads
- the skills: `~/.agents/skills/agent-chromium`, `~/.claude/skills/agent-chromium`
- the app's own data and cache folders, `~/Library/Application Support/Agent-Chromium` and
  `~/Library/Caches/Agent-Chromium` (only used when the app is opened from Finder, without
  agent-browser), and its preferences and saved window state in `~/Library/Preferences` and
  `~/Library/Saved Application State` (`org.agent-chromium.browser`)

## What stays

Neither command removes these:

- **agent-browser and its dependencies** (Node and about two dozen libraries). Other tools may use them.
  To remove them too:

  ```sh
  brew uninstall agent-browser
  brew autoremove                   # dependencies nothing else needs any more
  ```

- **`~/.agent-browser/config.json`**, the symlink to the deleted config. agent-browser commands fail
  until you remove it or point it elsewhere: `rm ~/.agent-browser/config.json`.
- **The skill in Claude Desktop**, if you installed it there. Remove it in Claude's settings.
- **The tap.** `brew untap ursamageor/agent-chromium` removes it.
