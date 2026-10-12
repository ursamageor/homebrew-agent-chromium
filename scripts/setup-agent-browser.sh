#!/bin/bash
# Set up ~/.agent-chromium and wire agent-browser to it. Everything the browser needs at launch
# lives in that one folder; agent-browser reads it through a symlink.
#
#   scripts/setup-agent-browser.sh [--app <path>] [--dir <path>] [--no-config] [--force]
#                                  [--skills ask|yes|no]
#
#   --app <path>    the app to point at (default /Applications/Agent-Chromium.app; a build/<arch>
#                   app works for testing)
#   --dir <path>    our folder (default ~/.agent-chromium)
#   --no-config     install extensions, profile and skills but leave the configs alone
#   --force         reinstall extensions even when the installed version is the latest
#   --skills        install the agent skill: ask (default on a terminal), yes, or no (default
#                   otherwise). Never installed unasked; an existing copy is refreshed.
#
# What it sets up, idempotently:
#
#   <dir>/extensions/<name>/     each extensions/<name>.lock, unpacked. The newest matching
#                                GitHub release is resolved at run time (so every run brings the
#                                latest), the download is checked against the sha256 digest
#                                GitHub records for the asset, the reserved _metadata dir is
#                                dropped, and KEY (if any) is written into manifest.json so the
#                                extension ID is fixed (unpacked IDs otherwise hash the path).
#   <dir>/extensions/<name>.version   the installed version; a run that resolves the same version
#                                skips the download. Offline, what is installed is kept.
#   <dir>/profiles/default/      the persistent profile. Seeded from prefs/initial_preferences.json
#                                only when it has no Default/ yet (an existing profile is yours).
#   <dir>/config.json            executablePath, profile, extensions, args, headed. An existing
#                                file with different content is backed up to config.json.bak-<time>.
#   ~/.agent-browser/config.json symlink to <dir>/config.json (a regular file there is backed up).
#   agent skill (opt-in, last)   skills/agent-chromium into ~/.agents/skills (Codex and most
#                                agents), ~/.claude/skills (Claude Code), and Claude Desktop
#                                (opens a .skill file in the app, which shows its install screen).
#
# Nothing starts the browser; agent-browser launches it per session (`agent-browser open <url>`).
# Extensions force a visible window: Chromium does not run content scripts headless.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

app="/Applications/Agent-Chromium.app"
dir="$HOME/.agent-chromium"
write_config=1
force=0
skills="auto"

log() { printf '==> %s\n' "$*" >&2; }
say() { printf '  %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app)       app="${2%/}"; shift 2 ;;
    --dir)       dir="${2%/}"; shift 2 ;;
    --no-config) write_config=0; shift ;;
    --force)     force=1; shift ;;
    --skills)    skills="${2:-}"; shift 2 ;;
    --skills=*)  skills="${1#*=}"; shift ;;
    -h|--help)   sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
done
case "$skills" in
  auto) if [ -t 0 ] && [ -t 1 ]; then skills="ask"; else skills="no"; fi ;;
  ask|yes|no) ;;
  *) die "--skills takes ask, yes or no" ;;
esac
for tool in curl shasum unzip zip plutil od python3; do need "$tool"; done

chromium="$app/Contents/MacOS/Chromium"
[ -x "$chromium" ] || die "no browser at $chromium (install the agent-chromium cask or pass --app)"
command -v agent-browser >/dev/null 2>&1 || say "agent-browser is not on PATH yet (brew install agent-browser)"

ext_root="$dir/extensions"
profile="$dir/profiles/default"
downloads="$dir/downloads"
mkdir -p "$ext_root" "$profile" "$downloads"

# --- Extensions ---------------------------------------------------------------------------------
# Each extensions/<name>.lock is a shell fragment: NAME, REPO (GitHub owner/repo), TAG_PREFIX
# (which of the repo's releases count), ASSET (regex for the asset to install), and optionally
# ROOT (subdirectory inside the archive that holds manifest.json) and KEY (public key written into
# manifest.json, which fixes the extension ID).
crx_to_zip() {  # CRX3 = "Cr24" + u32 version + u32 header length + header + zip
  local crx="$1" zip="$2" header_len
  [ "$(head -c 4 "$crx")" = "Cr24" ] || die "not a CRX file: $crx"
  header_len="$(od -An -t u4 -j 8 -N 4 "$crx" | tr -d ' ')"
  tail -c +$((12 + header_len + 1)) "$crx" > "$zip"
}

# <repo> <tag prefix> <asset regex>: prints "version url sha256" for the newest matching
# release, or nothing when GitHub cannot be reached. A token in GITHUB_TOKEN or GH_TOKEN lifts
# the anonymous rate limit (60 requests an hour per IP).
resolve_latest() {
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

extension_dirs=()
for lock in "$repo"/extensions/*.lock; do
  [ -f "$lock" ] || continue
  NAME="" REPO="" TAG_PREFIX="" ASSET="" ROOT="" KEY=""
  # shellcheck disable=SC1090
  . "$lock"
  [ -n "$NAME" ] && [ -n "$REPO" ] && [ -n "$ASSET" ] || die "incomplete lock: $lock"
  dest="$ext_root/$NAME"
  version_file="$ext_root/$NAME.version"
  extension_dirs+=("$dest")
  installed="$(cat "$version_file" 2>/dev/null || true)"

  read -r VERSION URL SHA256 <<<"$(resolve_latest "$REPO" "$TAG_PREFIX" "$ASSET")" || true
  if [ -z "${VERSION:-}" ]; then
    if [ -n "$installed" ] && [ -f "$dest/manifest.json" ]; then
      log "Extension $NAME: cannot reach GitHub, keeping installed $installed"
      continue
    fi
    die "$NAME: cannot resolve the latest release of $REPO (offline? rate-limited?)"
  fi
  [ -n "${SHA256:-}" ] || die "$NAME: GitHub records no sha256 digest for $URL; refusing to install unverified"

  if [ "$force" -eq 0 ] && [ "$installed" = "$VERSION" ] && [ -f "$dest/manifest.json" ]; then
    log "Extension $NAME $VERSION is the latest, already installed"
    continue
  fi
  log "Extension $NAME $VERSION${installed:+ (installed: $installed)}"

  archive="$downloads/$NAME-$VERSION.${URL##*.}"
  if [ ! -f "$archive" ]; then
    say "downloading $URL"
    curl -fsSL -o "$archive.part" "$URL" && mv "$archive.part" "$archive"
  fi
  printf '%s  %s\n' "$SHA256" "$archive" | shasum -a 256 -c - >/dev/null \
    || die "sha256 mismatch for $archive against GitHub's digest (delete it to re-download)"

  zip="$archive"
  case "$archive" in
    *.crx) zip="${archive%.crx}.zip"; crx_to_zip "$archive" "$zip" ;;
  esac

  rm -rf "${dest:?}"
  rm -f "${version_file:?}"
  mkdir -p "$dest"
  unzip -q -o "$zip" -d "$dest"
  if [ -n "$ROOT" ]; then
    [ -f "$dest/$ROOT/manifest.json" ] || die "$NAME: no manifest.json under $ROOT"
    tmp="$dest.tmp"; mv "$dest/$ROOT" "$tmp"; rm -rf "${dest:?}"; mv "$tmp" "$dest"
  fi
  [ -f "$dest/manifest.json" ] || die "$NAME: manifest.json not at the archive root; set ROOT in $lock"
  # Chromium refuses to load an unpacked extension that contains a reserved "_metadata" dir.
  rm -rf "${dest:?}/_metadata"
  if [ -n "$KEY" ]; then
    plutil -replace key -string "$KEY" "$dest/manifest.json" || die "$NAME: could not add key to manifest.json"
  fi
  printf '%s\n' "$VERSION" > "$version_file"
  # Older downloads of this extension are no longer needed.
  find "$downloads" -maxdepth 1 -name "$NAME-*" ! -name "$NAME-$VERSION.*" -delete
  say "installed $dest"
done

# --- Profile ------------------------------------------------------------------------------------
# Seeded once: Chromium adopts whatever Default/Preferences holds the first time it opens a data
# dir (for keys outside its tamper protection; the toolbar pins are). After that the profile is
# the user's and is never touched again.
if [ -d "$profile/Default" ]; then
  log "Profile $profile exists, left as is"
else
  log "Seeding profile $profile"
  mkdir -p "$profile/Default"
  cp "$repo/prefs/initial_preferences.json" "$profile/Default/Preferences"
fi

# --- Config -------------------------------------------------------------------------------------
if [ "$write_config" -eq 1 ]; then
  config="$dir/config.json"
  new="$(python3 -I - "$chromium" "$profile" "${extension_dirs[@]}" <<'PY'
import json, sys
chromium, profile, *exts = sys.argv[1:]
print(json.dumps({
    "$schema": "https://agent-browser.dev/schema.json",
    "executablePath": chromium,
    "profile": profile,
    "extensions": exts,
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

log "Done. Try:  agent-browser open https://example.com"
