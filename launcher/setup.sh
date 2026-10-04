#!/bin/bash
# Agent-Chromium setup: wire the installed app into agent-browser and, if wanted, into the
# user's coding agents. Idempotent; safe to re-run.
#
#   agent-chromium setup [--skills ask|yes|no]
#
# 1. ~/.agent-browser/config.json   agent-browser uses `agent-chromium plugin` as its browser
#                                   provider: attaches to the running browser, starting it first
#                                   if needed. Written only if absent; an existing file is the
#                                   user's and the entries to add are printed instead.
# 2. agent skills (last, opt-in)    offer, in order: ~/.agents/skills (Codex CLI, ChatGPT and
#                                   Codex desktop, most other harnesses), ~/.claude/skills
#                                   (Claude Code), and Claude Desktop (opens agent-chromium.skill
#                                   in the app, which shows its install screen). Default: ask
#                                   when on a terminal, otherwise no. Never installed unasked.
#
# Nothing here starts the browser or registers anything with launchd. The cask cannot run this
# (Homebrew's install sandbox fakes $HOME), so it is a post-install step; the launcher also runs
# it with --skills no on the first standalone launch of each version.
set -euo pipefail

skills="auto"
while [ $# -gt 0 ]; do
  case "$1" in
    --skills) skills="${2:-}"; shift 2 ;;
    --skills=*) skills="${1#*=}"; shift ;;
    -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "agent-chromium setup: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$skills" in
  auto) if [ -t 0 ] && [ -t 1 ]; then skills="ask"; else skills="no"; fi ;;
  ask|yes|no) ;;
  *) echo "agent-chromium setup: --skills takes ask, yes or no" >&2; exit 2 ;;
esac

resources="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # Contents/Resources
contents="$(cd "$resources/.." && pwd)"
stub="$contents/MacOS/Chromium"
skill_src="$resources/agent-chromium/skills/agent-chromium"

say()   { printf '  %s\n' "$*"; }
head1() { printf '\n%s\n' "$*"; }

# --- 1. agent-browser config ---------------------------------------------------------------------
head1 "agent-browser"
config="$HOME/.agent-browser/config.json"
plugin_entry="{ \"name\": \"agent-chromium\", \"command\": \"$stub\", \"args\": [\"plugin\"], \"capabilities\": [\"browser.provider\"] }"
if [ -f "$config" ]; then
  say "kept existing $config"
  say "make sure it has:  \"provider\": \"agent-chromium\","
  say "  and in \"plugins\": $plugin_entry"
else
  mkdir -p "$(dirname "$config")"
  cat > "$config" <<EOF
{
  "\$schema": "https://agent-browser.dev/schema.json",
  "executablePath": "$stub",
  "headed": true,
  "provider": "agent-chromium",
  "plugins": [
    $plugin_entry
  ]
}
EOF
  say "wrote $config (provider agent-chromium: attach, starting the browser if needed)"
fi

# --- 2. Skills (opt-in, last) --------------------------------------------------------------------
skill_file="$resources/agent-chromium/agent-chromium.skill"

# <question>: yes/no per --skills; asks on a terminal in ask mode.
confirm() {
  local answer
  case "$skills" in
    yes) return 0 ;;
    no)  return 1 ;;
  esac
  printf '  %s [y/N] ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# <label> <skills dir>: copies the skill folder in. An existing copy is refreshed without asking.
offer_skill_dir() {
  local label="$1" dir="$2" verb="installed"
  if [ -d "$dir/agent-chromium" ]; then
    verb="updated"
  elif ! confirm "$label: install the agent-chromium skill to $dir/agent-chromium?"; then
    say "$label: skipped (run \`agent-chromium setup --skills yes\` to install)"
    return
  fi
  rm -rf "$dir/agent-chromium"
  mkdir -p "$dir"
  cp -R "$skill_src" "$dir/agent-chromium"
  say "$label: $verb $dir/agent-chromium"
}

head1 "Agent skills"
offer_skill_dir "Shared agent skills (Codex, ChatGPT, most other agents)" "$HOME/.agents/skills"

if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  offer_skill_dir "Claude Code" "$HOME/.claude/skills"
else
  say "Claude Code: not found (looked for ~/.claude and the claude command)"
fi

claude_app=""
for app in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
  [ -d "$app" ] && { claude_app="$app"; break; }
done
if [ -z "$claude_app" ]; then
  say "Claude Desktop: not found"
elif [ ! -f "$skill_file" ]; then
  say "Claude Desktop: found, but $skill_file is missing from this build"
elif confirm "Claude Desktop: open the agent-chromium skill in Claude to install it?"; then
  # Opens the app's own install screen; the user confirms there. -a: ChatGPT also claims .skill.
  if open -a "$claude_app" "$skill_file"; then
    say "Claude Desktop: opened the skill in Claude; confirm the install there"
  else
    say "Claude Desktop: could not open Claude; run: open -a Claude \"$skill_file\""
  fi
else
  say "Claude Desktop: skipped (install later with: open -a Claude \"$skill_file\")"
fi

head1 "Done. Try:  agent-browser open https://example.com"
