# Updating and uninstalling

## Updating

```sh
brew upgrade --cask agent-chromium    # the browser; your profile is kept
brew upgrade agent-browser            # agent-browser updates on its own schedule
"$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"   # the extensions
```

A plain `brew upgrade` does the first two. The setup script fetches the latest Bitwarden (from the
Chrome Web Store) and chromium-web-store (from GitHub) and writes the new versions into the profile's
`External Extensions` folder; Chromium installs the update on its next start. Everything else it
finds in place (profile, config, skills) it leaves alone or refreshes. Extensions you installed from
the Chrome Web Store yourself don't update with any of this: chromium-web-store shows a count on its
toolbar icon when updates are waiting.

After a browser upgrade, the first launch may show a keychain prompt for "Chromium Safe Storage":
click **Always Allow**. The upgraded app has a new signature, and the keychain asks again before
handing it the key that protects your cookies.

## Uninstalling

Quit Agent-Chromium first (`agent-browser close`), then pick one:

```sh
brew uninstall --cask agent-chromium          # removes the app, keeps your profile and ~/.agent-chromium
brew uninstall --cask --zap agent-chromium    # also deletes the profile, extensions, config and skills
```

`--zap` deletes:

- `~/Library/Application Support/Agent-Chromium`, the profile: logins, cookies, bookmarks,
  extensions; and the app's cache in `~/Library/Caches/Agent-Chromium`, its preferences in
  `~/Library/Preferences` and saved window state in `~/Library/Saved Application State`
  (`org.agent-chromium.browser`)
- `~/.agent-chromium`: the extension files, the config, the `bin` scripts
- the skills: `~/.agents/skills/agent-chromium`, `~/.claude/skills/agent-chromium`

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
- **The keychain item** "Chromium Safe Storage". Your daily Chromium shares it, so it must stay.
- **The skill in Claude Desktop**, if you installed it there. Remove it in Claude's settings.
- **The tap.** `brew untap ursamageor/agent-chromium` removes it.
