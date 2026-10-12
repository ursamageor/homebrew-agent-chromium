#!/bin/bash
# Set up ~/.agent-chromium and wire agent-browser to it. The browser's profile is the app's own
# data folder, so the app opened from Finder and the app launched by agent-browser are one browser.
#
#   scripts/setup-agent-browser.sh [--app <path>] [--dir <path>] [--profile <path>] [--no-config]
#                                  [--force] [--skills ask|yes|no] [--welcome|--no-welcome]
#
#   --app <path>      the app to point at (default /Applications/Agent-Chromium.app; a build/<arch>
#                     app works for testing)
#   --dir <path>      our folder (default ~/.agent-chromium)
#   --profile <path>  the profile folder (default ~/Library/Application Support/Agent-Chromium, the
#                     app's own data folder, which a Finder launch uses too)
#   --no-config       install extensions, profile and skills but leave the configs alone
#   --force           reinstall extensions even when the installed version is the latest
#   --skills          install the agent skill: ask (default on a terminal), yes, or no (default
#                     otherwise). Never installed unasked; an existing copy is refreshed.
#   --welcome         open the welcome page in the browser at the end (default: only when the
#                     profile was just created); --no-welcome never does
#
# What it sets up, idempotently:
#
#   <dir>/extensions/<name>-<version>.crx   each extensions/<name>.lock, as a CRX. The newest
#                                version is resolved at run time (Chrome Web Store update check, or
#                                GitHub release), the download is checked against the sha256 the
#                                source records for it, and older versions are deleted.
#   <profile>/External Extensions/<id>.json   points Chromium at the CRX. Chromium installs it
#                                into the profile on its next start, as an ordinary installed
#                                extension, and updates it when the version here goes up. It
#                                arrives switched off: macOS Chromium asks once, per extension,
#                                to enable anything that did not come from the store.
#   <profile>/Default/Preferences   seeded from prefs/initial_preferences.json only when the
#                                profile has no Default/ yet (an existing profile is yours). The
#                                "First Run" marker is created with it, so a Dock launch skips
#                                ungoogled-chromium's first-run page.
#   <dir>/welcome.html           the welcome page (prefs/welcome.html): the few settings Chromium
#                                will not let us preset, opened in the browser once the profile
#                                is new, with the pages it names in the next tabs.
#   <dir>/bin/chromium           what agent-browser launches: drops two flags agent-browser always
#                                adds, then runs the app (see the script for which and why).
#   <dir>/bin/check              tells whether the browser is closed, launched by agent-browser,
#                                or opened by the user (which agent-browser cannot drive); --quit
#                                quits a user-opened one so the next command can relaunch it.
#   <dir>/config.json            executablePath, profile, args, headed. An existing file with
#                                different content is backed up to config.json.bak-<time>.
#   ~/.agent-browser/config.json symlink to <dir>/config.json (a regular file there is backed up).
#   agent skill (opt-in, last)   skills/agent-chromium into ~/.agents/skills (Codex and most
#                                agents), ~/.claude/skills (Claude Code), and Claude Desktop
#                                (opens a .skill file in the app, which shows its install screen).
#
# Nothing starts the browser; agent-browser launches it per session (`agent-browser open <url>`).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

app="/Applications/Agent-Chromium.app"
dir="$HOME/.agent-chromium"
profile="$HOME/Library/Application Support/Agent-Chromium"
write_config=1
force=0
skills="auto"
welcome="auto"

log() { printf '==> %s\n' "$*" >&2; }
say() { printf '  %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app)       app="${2%/}"; shift 2 ;;
    --dir)       dir="${2%/}"; shift 2 ;;
    --profile)   profile="${2%/}"; shift 2 ;;
    --no-config) write_config=0; shift ;;
    --force)     force=1; shift ;;
    --skills)    skills="${2:-}"; shift 2 ;;
    --skills=*)  skills="${1#*=}"; shift ;;
    --welcome)   welcome="yes"; shift ;;
    --no-welcome) welcome="no"; shift ;;
    -h|--help)   sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
done
case "$skills" in
  auto) if [ -t 0 ] && [ -t 1 ]; then skills="ask"; else skills="no"; fi ;;
  ask|yes|no) ;;
  *) die "--skills takes ask, yes or no" ;;
esac
for tool in curl shasum zip plutil python3; do need "$tool"; done

chromium="$app/Contents/MacOS/Chromium"
[ -x "$chromium" ] || die "no browser at $chromium (install the agent-chromium cask or pass --app)"
app_version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" 2>/dev/null || echo 0)"
command -v agent-browser >/dev/null 2>&1 || say "agent-browser is not on PATH yet (brew install agent-browser)"

ext_root="$dir/extensions"
external="$profile/External Extensions"
mkdir -p "$ext_root" "$dir/bin" "$external"

# --- Extensions ---------------------------------------------------------------------------------
# Each extensions/<name>.lock is a shell fragment: NAME, ID (the extension ID, which names the
# External Extensions file), SOURCE, and per source:
#   webstore   nothing else: the Chrome Web Store's update check for ID gives version, URL and sha256
#   github     REPO (owner/repo), TAG_PREFIX (which of the repo's releases count), ASSET (regex for
#              the .crx asset); GitHub's digest for the asset gives the sha256

# <id>: prints "version url sha256" from the Web Store's update check, or nothing when it cannot be
# reached. The same request Chrome makes; the store answers for extensions it lists.
resolve_webstore() {
  local xml
  xml="$(mktemp)"
  curl -fsSL --max-time 20 -o "$xml" \
    "https://clients2.google.com/service/update2/crx?response=updatecheck&acceptformat=crx3&prodversion=$app_version&x=id%3D$1%26installsource%3Dondemand%26uc" \
    2>/dev/null || { rm -f "$xml"; return 0; }
  python3 -I - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
ns = {"u": "http://www.google.com/update2/response"}
for uc in root.iter("{http://www.google.com/update2/response}updatecheck"):
    if uc.get("status") == "ok" and uc.get("codebase") and uc.get("hash_sha256"):
        print(uc.get("version"), uc.get("codebase"), uc.get("hash_sha256"))
        break
PY
  rm -f "$xml"
}

# <repo> <tag prefix> <asset regex>: prints "version url sha256" for the newest matching
# release, or nothing when GitHub cannot be reached. A token in GITHUB_TOKEN or GH_TOKEN lifts
# the anonymous rate limit (60 requests an hour per IP).
resolve_github() {
  local auth=() json
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  [ -z "$token" ] || auth=(-H "Authorization: Bearer $token")
  json="$(mktemp)"
  curl -fsSL --max-time 20 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} \
    -o "$json" "https://api.github.com/repos/$1/releases?per_page=50" 2>/dev/null || { rm -f "$json"; return 0; }
  python3 -I - "$json" "$2" "$3" <<'PY'
import json, re, sys
path, prefix, asset_re = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
try:
    releases = json.load(open(path))
except Exception:
    sys.exit(0)
# The API lists releases newest first.
for r in releases:
    tag = r.get("tag_name", "")
    if r.get("draft") or r.get("prerelease") or not tag.startswith(prefix):
        continue
    for a in r.get("assets", []):
        if asset_re.search(a.get("name", "")):
            digest = a.get("digest") or ""
            print(tag[len(prefix):], a["browser_download_url"], digest.removeprefix("sha256:"))
            sys.exit(0)
PY
  rm -f "$json"
}

# <crx> <id> <version>: the External Extensions entry. Chromium reads these on every start.
write_external() {
  printf '{"external_crx": "%s", "external_version": "%s"}\n' "$1" "$3" > "$external/$2.json"
}

for lock in "$repo"/extensions/*.lock; do
  [ -f "$lock" ] || continue
  NAME="" ID="" SOURCE="" REPO="" TAG_PREFIX="" ASSET=""
  # shellcheck disable=SC1090
  . "$lock"
  [ -n "$NAME" ] && [ -n "$ID" ] && [ -n "$SOURCE" ] || die "incomplete lock: $lock"
  version_file="$ext_root/$NAME.version"
  installed="$(cat "$version_file" 2>/dev/null || true)"
  installed_crx="$ext_root/$NAME-$installed.crx"
  # The unpacked copy of the previous layout is not used any more.
  [ -d "$ext_root/$NAME" ] && rm -rf "${ext_root:?}/${NAME:?}"

  case "$SOURCE" in
    webstore) resolved="$(resolve_webstore "$ID")"; where="the Chrome Web Store" ;;
    github)   [ -n "$REPO" ] && [ -n "$ASSET" ] || die "incomplete lock: $lock"
              resolved="$(resolve_github "$REPO" "$TAG_PREFIX" "$ASSET")"; where="GitHub ($REPO)" ;;
    *)        die "$lock: SOURCE must be webstore or github" ;;
  esac
  read -r VERSION URL SHA256 <<<"$resolved" || true
  if [ -z "${VERSION:-}" ]; then
    if [ -n "$installed" ] && [ -f "$installed_crx" ]; then
      log "Extension $NAME: cannot reach $where, keeping installed $installed"
      write_external "$installed_crx" "$ID" "$installed"
      continue
    fi
    die "$NAME: cannot resolve the latest version from $where (offline? rate-limited?)"
  fi
  [ -n "${SHA256:-}" ] || die "$NAME: $where records no sha256 for $URL; refusing to install unverified"

  crx="$ext_root/$NAME-$VERSION.crx"
  if [ "$force" -eq 0 ] && [ "$installed" = "$VERSION" ] && [ -f "$crx" ]; then
    log "Extension $NAME $VERSION is the latest, already installed"
    write_external "$crx" "$ID" "$VERSION"
    continue
  fi
  log "Extension $NAME $VERSION${installed:+ (installed: $installed)}"
  say "downloading $URL"
  curl -fsSL -o "$crx.part" "$URL"
  printf '%s  %s\n' "$SHA256" "$crx.part" | shasum -a 256 -c - >/dev/null \
    || { rm -f "$crx.part"; die "sha256 mismatch for $URL against the sha256 $where records"; }
  [ "$(head -c 4 "$crx.part")" = "Cr24" ] || { rm -f "$crx.part"; die "$NAME: $URL is not a CRX file"; }
  mv "$crx.part" "$crx"
  printf '%s\n' "$VERSION" > "$version_file"
  write_external "$crx" "$ID" "$VERSION"
  # Older versions of this extension are no longer needed.
  find "$ext_root" -maxdepth 1 -name "$NAME-*.crx" ! -name "$NAME-$VERSION.crx" -delete
  say "installed $crx"
done

# --- Profile ------------------------------------------------------------------------------------
# Seeded once: Chromium adopts whatever Default/Preferences holds the first time it opens a data
# dir (for keys outside its tamper protection; the toolbar pins are). After that the profile is
# the user's and is never touched again.
seeded=0
if [ -d "$profile/Default" ]; then
  log "Profile $profile exists, left as is"
else
  log "Seeding profile $profile"
  mkdir -p "$profile/Default"
  cp "$repo/prefs/initial_preferences.json" "$profile/Default/Preferences"
  # Without this marker a Dock launch shows chrome://ungoogled-first-run; the welcome page
  # replaces it. (agent-browser launches pass --no-first-run anyway.)
  touch "$profile/First Run"
  seeded=1
fi
cp "$repo/prefs/welcome.html" "$dir/welcome.html"

# --- bin ----------------------------------------------------------------------------------------
# agent-browser cannot be told to leave these two flags out, and Chromium has no way to cancel a
# flag once given, so the config points agent-browser at this script instead of the binary.
cat > "$dir/bin/chromium" <<EOF
#!/bin/sh
# Launched by agent-browser in place of the app (written by setup-agent-browser.sh). It drops:
#   --use-mock-keychain     agent-browser's fixed fake key for cookies. The app opened from Finder
#                           uses the real keychain; with two keys, each launch loses the other's
#                           cookies. The real keychain is also the stronger of the two.
#   --disable-default-apps  makes Chromium skip the External Extensions folder, which is how the
#                           extensions get installed.
for a in "\$@"; do
  case "\$a" in --use-mock-keychain|--disable-default-apps) ;; *) set -- "\$@" "\$a" ;; esac
  shift
done
exec "$chromium" "\$@"
EOF
chmod +x "$dir/bin/chromium"

cat > "$dir/bin/check" <<EOF
#!/bin/sh
# Is Agent-Chromium's profile in use, and by whom? (written by setup-agent-browser.sh)
#   closed   nothing has it: agent-browser's next command launches the browser
#   agent    launched by agent-browser (has a debugging port): drive it
#   user     opened by the user, from Finder or the Dock: no debugging port, and the profile is
#            locked, so agent-browser's launch fails. Exit status 1.
#   check --quit   quits a user-opened browser (a normal Quit; its tabs come back on the next
#                  launch if "Continue where you left off" is set) and waits for the lock to go.
profile="$profile"
lock="\$profile/SingletonLock"
pid="\$(readlink "\$lock" 2>/dev/null | sed 's/.*-//')"
if [ -z "\$pid" ] || ! kill -0 "\$pid" 2>/dev/null; then echo closed; exit 0; fi
port="\$(head -n 1 "\$profile/DevToolsActivePort" 2>/dev/null)"
# The port file outlives the browser that wrote it, so it has to answer.
if [ -n "\$port" ] && curl -sf --max-time 2 "http://127.0.0.1:\$port/json/version" >/dev/null 2>&1; then
  echo agent; exit 0
fi
if [ "\${1:-}" != "--quit" ]; then echo user; exit 1; fi
osascript -e 'quit app id "org.agent-chromium.browser"' >/dev/null
for _ in \$(seq 1 60); do [ -L "\$lock" ] || { echo closed; exit 0; }; sleep 0.5; done
echo "still open: the browser did not quit (a dialog may be waiting)" >&2; exit 1
EOF
chmod +x "$dir/bin/check"
log "Wrote $dir/bin/chromium and $dir/bin/check"

# --- Config -------------------------------------------------------------------------------------
config="$dir/config.json"
new="$(python3 -I - "$dir/bin/chromium" "$profile" <<'PY'
import json, sys
chromium, profile = sys.argv[1:]
print(json.dumps({
    "$schema": "https://agent-browser.dev/schema.json",
    "executablePath": chromium,
    "profile": profile,
    # --extension-mime-request-handling: lets chromium-web-store (and the user) install CRX
    # files; ungoogled-chromium downloads them as plain files otherwise. A chrome://flags entry,
    # so it cannot live in preferences.
    # about:blank: Chromium opens a bare URL on its command line as the startup tab, instead of
    # chrome://newtab/. agent-browser adopts existing tabs after launch but skips chrome:// ones,
    # so without this it opened its own tab and left the new-tab page behind.
    "args": "--extension-mime-request-handling=always-prompt,about:blank",
    "headed": True,
}, indent=2))
PY
)"
if [ "$write_config" -eq 1 ]; then
  if [ -f "$config" ] && [ "$(cat "$config")" != "$new" ]; then
    backup="$config.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$config" "$backup"
    say "backed up the previous config to $backup"
  fi
  printf '%s\n' "$new" > "$config"
  log "Wrote $config"
  sed 's/^/  /' "$config" >&2

  # agent-browser reads ~/.agent-browser/config.json; make that a symlink to ours.
  ab_config="$HOME/.agent-browser/config.json"
  mkdir -p "$HOME/.agent-browser"
  if [ -L "$ab_config" ] && [ "$(readlink "$ab_config")" = "$config" ]; then
    log "$ab_config already points at it"
  else
    if [ -e "$ab_config" ] && [ ! -L "$ab_config" ]; then
      backup="$ab_config.bak-$(date +%Y%m%d-%H%M%S)"
      mv "$ab_config" "$backup"
      say "moved the previous $ab_config to $backup"
    fi
    ln -sfn "$config" "$ab_config"
    log "$ab_config -> $config"
  fi
fi

# --- Agent skill (opt-in, last) ------------------------------------------------------------------
skill_src="$repo/skills/agent-chromium"
[ -f "$skill_src/SKILL.md" ] || die "skill missing at $skill_src"

confirm() {  # <question>: yes/no per --skills; asks on a terminal in ask mode.
  local answer
  case "$skills" in yes) return 0 ;; no) return 1 ;; esac
  printf '  %s [y/N] ' "$1" >&2
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
offer_skill_dir() {  # <label> <skills dir>: copies the skill folder in; an existing copy is refreshed.
  local label="$1" target="$2/agent-chromium" verb="installed"
  if [ -d "$target" ]; then
    verb="updated"
  elif ! confirm "$label: install the agent-chromium skill to $target?"; then
    say "$label: skipped (re-run with --skills yes to install)"
    return
  fi
  rm -rf "${target:?}"
  mkdir -p "$2"
  cp -R "$skill_src" "$target"
  say "$label: $verb $target"
}

log "Agent skill"
offer_skill_dir "Shared agent skills (Codex, ChatGPT, most other agents)" "$HOME/.agents/skills"
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  offer_skill_dir "Claude Code" "$HOME/.claude/skills"
else
  say "Claude Code: not found (looked for ~/.claude and the claude command)"
fi
claude_app=""
for a in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
  [ -d "$a" ] && { claude_app="$a"; break; }
done
if [ -z "$claude_app" ]; then
  say "Claude Desktop: not found"
elif confirm "Claude Desktop: open the agent-chromium skill in Claude to install it?"; then
  # Claude Desktop takes a .skill file (the skill folder zipped, folder at the top level) opened
  # with the app, which shows its own install screen. -a: ChatGPT also claims .skill.
  skill_file="$(mktemp -d)/agent-chromium.skill"
  (cd "$repo/skills" && zip -qrX "$skill_file" agent-chromium -x '*/.*')
  if open -a "$claude_app" "$skill_file"; then
    say "Claude Desktop: opened the skill in Claude; confirm the install there"
  else
    say "Claude Desktop: could not open Claude; run: open -a Claude \"$skill_file\""
  fi
else
  say "Claude Desktop: skipped (re-run with --skills yes to install)"
fi

# --- Welcome page -------------------------------------------------------------------------------
# Opened through agent-browser with this config (whether or not it was written: a temp copy
# otherwise), on the default session, so the browser the user sees is the one agents will use.
# The welcome page gets a tab first, then the three chrome:// pages it names, then back to it.
[ "$welcome" = "auto" ] && { [ "$seeded" -eq 1 ] && welcome="yes" || welcome="no"; }
if [ "$welcome" = "yes" ]; then
  if ! command -v agent-browser >/dev/null 2>&1; then
    say "welcome page: agent-browser is not on PATH; open $dir/welcome.html in Agent-Chromium yourself"
  else
    if [ "$write_config" -eq 1 ]; then
      welcome_config="$dir/config.json"
    else
      welcome_config="$(mktemp -t agent-chromium-welcome).json"
      printf '%s\n' "$new" > "$welcome_config"
    fi
    log "Opening the welcome page in Agent-Chromium"
    if agent-browser --config "$welcome_config" open "file://$dir/welcome.html" >/dev/null 2>&1; then
      for url in chrome://extensions chrome://settings/onStartup chrome://settings/search; do
        agent-browser --config "$welcome_config" tab new "$url" >/dev/null 2>&1 || true
      done
      agent-browser --config "$welcome_config" tab t1 >/dev/null 2>&1 || true
      say "the browser is open on the welcome page; the settings it names are in the next tabs"
      [ "$write_config" -eq 1 ] || say "(launched with the temporary config $welcome_config)"
    else
      say "could not launch the browser (is it already open from the Dock? quit it and re-run with --welcome)"
    fi
  fi
fi

log "Done. Try:  agent-browser open https://example.com"
say "The first time, switch Bitwarden and Chromium Web Store on in chrome://extensions:"
say "Chromium asks once for extensions that did not come from the store. $dir/welcome.html has the details."
