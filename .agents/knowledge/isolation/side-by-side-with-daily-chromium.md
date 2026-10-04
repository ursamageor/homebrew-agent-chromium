# Running a second Chromium side by side with the daily ungoogled-chromium

Findings from 2026-09-30, moved here from the notebook on 2026-10-03. The question was how to install
a second Chromium-family browser without it colliding with ursamageor's daily ungoogled-chromium, and the
answers shape how Agent-Chromium is built. Read this before changing how the app is built, installed,
or launched.

## The collision

- The daily browser is Homebrew's `ungoogled-chromium` cask (152.0.7977.82-1.1 at the time). It is
  installed as `/Applications/Chromium.app`, with `CFBundleIdentifier` `org.chromium.Chromium` and
  data in `~/Library/Application Support/Chromium`.
- It is **Developer ID signed** (Team `B9A88FL5XJ`, hardened runtime, library validation). The signing
  identifier is `io.ungoogled-software.ungoogled-chromium`, which differs from the bundle ID.
- Homebrew's `chromium` cask installs the same `/Applications/Chromium.app`, with the same bundle ID
  and the same data folder. Each cask declares `conflicts_with` the other.
- The `chromium` cask has been **disabled since 2026-09-01** (`fails_gatekeeper_check`), so
  `brew install --cask chromium` no longer works.
- Google Chrome doesn't collide: it uses `Google Chrome.app`, `com.google.Chrome`, and
  `~/Library/Application Support/Google/Chrome`.

## What controls each path

| What | Controlled by |
|---|---|
| `.app` name | cask `app ..., target:`; renaming the folder keeps the signature valid |
| Data and cache folders | `CrProductDirName` in the outer `Info.plist` (how Chrome Canary gets its own) |
| Prefs plist, saved state, Launch Services, default browser, privacy permissions | `CFBundleIdentifier` |
| Menu bar name | `CFBundleName`; some built-in strings still say "Chromium" |
| Keychain item `Chromium Safe Storage` | **built into the binary**; a plist edit can't change it |

`CrProductDirName` sets the folder under both `Application Support` and `Caches`. A value with a space
works (Canary uses `Google/Chrome Canary`). Editing `Info.plist` breaks the outer signature, so the app
must be re-signed afterwards.

## Verified on 2026-09-30

Setup: an APFS clone of the daily app (`cp -Rc`), renamed to `Chromium IsoTest.app`. `Info.plist` was
edited to set `CFBundleIdentifier=org.chromium.Chromium.isotest`, add `CrProductDirName=Chromium-IsoTest`,
and set `CFBundleName`. Then `xattr -cr` and `codesign --force --deep --sign -` (the result passed
`codesign --verify --deep --strict`).

1. **The data folder moved.** The clone was launched with
   `--no-startup-window --use-mock-keychain --no-first-run` under `sandbox-exec`, which denied read and
   write access to the real `Chromium` data and cache folders. It created
   `~/Library/Application Support/Chromium-IsoTest` (with a full `Default/` profile) and
   `~/Library/Caches/Chromium-IsoTest`. The running daily browser was not affected.
2. **Pages still load after the ad-hoc re-sign.** `--headless=new --dump-dom 'data:text/html,...'`
   returned the page.

Things about the test setup to know before repeating it:

- Chromium's helpers print "Failed to initialize sandbox" (GPU exits with code 6) when the browser runs
  inside `sandbox-exec`. The cause is the nested sandbox, not the plist patch. For the same reason the
  no-window instance quit on its own within about 10 seconds.
- Without `--user-data-dir`, `--headless=new` also followed the patched name. It created
  `Chromium-IsoTest-headless` (`<CrProductDirName>-headless`) under both `Application Support` and
  `Caches`. Each run makes a temporary `scoped_dir*` profile. On exit it was deleted from
  `Application Support`, but its `Default/Cache` stayed behind in `Caches`. So headless runs don't
  keep a profile and can't stand in for a normal run. Remember the `-headless` folders when cleaning
  up.
- `--use-mock-keychain` avoids a keychain prompt for the re-signed copy. Only use it with the sandbox
  guard in place: if the patch failed, the mock key could not decrypt the real profile's cookies.
- Full visible runs of the installed Agent-Chromium followed (2026-09-30 to 10-01, see the testing
  notes): the daily `Default/` mtime stayed unchanged throughout.

## How Agent-Chromium resolves it

- **Patched once, at build time.** `scripts/build-app.sh` sets `CFBundleIdentifier`
  (`org.agent-chromium.browser`), `CFBundleName`/`CFBundleDisplayName` and `CrProductDirName`
  (`Agent-Chromium`), re-signs ad hoc and zips the result; the cask installs that zip. The first idea,
  a tap cask that patches the upstream app in `postflight`, was dropped: Ruby `postflight` is legacy
  in third-party taps, declarative steps run in a sandbox, and building once lets the upstream
  signature be checked (Developer ID team `B9A88FL5XJ`) before it is replaced.
- **Explicit `--user-data-dir` for every standalone launch.** Chromium refuses
  `--remote-debugging-port` on its default data dir, so the launcher (`launcher/launch.sh`, run for
  Dock, `open -a` and CLI launches alike) always passes the stable dir. The plist patch still matters:
  it separates Launch Services, preferences and saved state, and keeps the default dir off the daily
  one should a launch ever skip the flag.
- **Extensions are bundled unpacked** and loaded with `--load-extension`.
- `plutil -replace` works whether or not the key already exists. `PlistBuddy Add` fails if it does.
- Brew adds a quarantine flag, and an ad-hoc signed app with that flag gets blocked by Gatekeeper.
  The cask's `postflight_steps` run `xattr -cr`. (Avoid `--no-quarantine`; recent Homebrew deprecated
  it.)

## Costs of re-signing

- **Re-signing ad-hoc removes the Developer ID signature, hardened runtime, and library validation.**
  For ungoogled-chromium that is a real downgrade from how it ships. Weigh it against the next point.
- **Every upgrade creates a new ad-hoc signature.** Expect a keychain prompt ("Always Allow") and a
  Little Snitch "program has been modified" alert after each upgrade.
- **The keychain key is shared.** Both builds use the same `Chromium Safe Storage` item, so the agent
  build can decrypt cookies encrypted with the daily build's key. Only the data folders are separate.
