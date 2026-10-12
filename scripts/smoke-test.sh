#!/bin/bash
# Smoke test an Agent-Chromium app: the bundle, then the whole user-side flow on throwaway
# folders: setup-agent-browser.sh into them, a config pointing at them, an agent-browser launch,
# the extensions Chromium installs from them, the tabs, the profile after quit.
#
#   scripts/smoke-test.sh [--app <path>] [--keep]
#
# --app   the app to test (default /Applications/Agent-Chromium.app; a build/<arch>/ app works too,
#         x86_64 runs under Rosetta)
# --keep  leave the temp dir (folders, config, logs) for inspection instead of deleting it
#
# Never touches a real profile, ~/.agent-chromium or ~/.agent-browser/config.json: the setup runs
# with --dir, --profile and --no-config into a temp folder, agent-browser gets --config and its own
# session, and the run fails if the daily Chromium's or the real Agent-Chromium's profile changed
# meanwhile. A window opens while it runs; both real browsers can stay open meanwhile. Needs
# network (the extensions are downloaded), agent-browser, curl, python3. Runs every check and
# reports; exit status 1 if any failed.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="/Applications/Agent-Chromium.app"
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --app)  app="${2%/}"; shift 2 ;;
    --keep) keep=1; shift ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BITWARDEN_ID="nngceckbapebfimnlniiiahkandclblb"
WEB_STORE_ID="ocaahdebbfolfmndjeplogmgcagdmblk"
contents="$app/Contents"
chromium="$contents/MacOS/Chromium"
for tool in agent-browser curl python3 codesign lipo plutil; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 1; }
done
[ -x "$chromium" ] || { echo "no app at $app" >&2; exit 1; }

tmp="$(mktemp -d /tmp/agent-chromium-smoke.XXXXXX)"
dir="$tmp/agent-chromium"
profile="$tmp/profile"
config="$tmp/config.json"
session="smoke-$$"
pass=0; fail=0
section() { printf '\n== %s\n' "$*"; }
ok()      { pass=$((pass + 1)); printf '  ok   %s\n' "$*"; }
bad()     { fail=$((fail + 1)); printf '  FAIL %s\n' "$*"; }
check()   { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }
expect()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected '$3', got '$2'"; fi; }
expect_match() { if [[ "$3" =~ $2 ]]; then ok "$1"; else bad "$1: '$2' not in '${3:0:300}'"; fi; }
expect_no_match() { if [[ "$3" =~ $2 ]]; then bad "$1: '$2' found in '${3:0:300}'"; else ok "$1"; fi; }
ab() { agent-browser --config "$config" "$@"; }
mtime() { stat -f '%m' "$1" 2>/dev/null || echo none; }
# <id> <field>: that field of the extension's entry in Secure Preferences, JSON-encoded.
ext_pref() {
  python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])).get("extensions",{}).get("settings",{}).get(sys.argv[2]); print(json.dumps(s.get(sys.argv[3])) if s else "absent")' \
    "$profile/Default/Secure Preferences" "$1" "$2" 2>/dev/null
}
pins() {
  python3 -I -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["extensions"].get("pinned_extensions",[])))' \
    "$profile/Default/Preferences" 2>/dev/null
}

daily_prefs="$HOME/Library/Application Support/Chromium/Default/Preferences"
real_prefs="$HOME/Library/Application Support/Agent-Chromium/Default/Preferences"
daily_before="$(mtime "$daily_prefs")"
real_before="$(mtime "$real_prefs")"
ab_config_before="$(mtime "$HOME/.agent-browser/config.json")"

cleanup() {
  ab close >/dev/null 2>&1 || true
  pkill -TERM -f "user-data-dir=$profile" 2>/dev/null || true
  rm -f "$HOME/.agent-browser/$session".{config,target} 2>/dev/null
  if [ "$keep" -eq 1 ]; then echo "kept $tmp"; else rm -rf "${tmp:?}"; fi
}
trap cleanup EXIT

# --- 1. Bundle ----------------------------------------------------------------------------------
section "Bundle: $app"
check "only the real Chromium binary in MacOS" test "$(ls "$contents/MacOS" | tr '\n' ' ')" = "Chromium "
check "nothing of ours in Resources" test ! -e "$contents/Resources/agent-chromium" -a ! -e "$contents/Resources/extensions"
expect "bundle ID" "$(plutil -extract CFBundleIdentifier raw "$contents/Info.plist")" "org.agent-chromium.browser"
expect "CrProductDirName" "$(plutil -extract CrProductDirName raw "$contents/Info.plist")" "Agent-Chromium"
expect "CFBundleName" "$(plutil -extract CFBundleName raw "$contents/Info.plist")" "Agent-Chromium"
check "signature verifies (deep, strict)" codesign --verify --deep --strict "$app"
expect_match "single-arch binary" '^(arm64|x86_64)$' "$(lipo -archs "$chromium")"

# --- 2. Setup into the temp folders ------------------------------------------------------------
section "Setup into $dir, profile $profile"
if "$repo/scripts/setup-agent-browser.sh" --app "$app" --dir "$dir" --profile "$profile" --no-config --skills no --no-welcome >"$tmp/setup.log" 2>&1; then
  ok "setup-agent-browser.sh ran"
else
  bad "setup-agent-browser.sh failed: $(tail -n 3 "$tmp/setup.log" | tr '\n' ' ')"
fi
check "welcome page copied" test -s "$dir/welcome.html"
check "First Run marker seeded (no ungoogled first-run page on a Dock launch)" test -f "$profile/First Run"
bw_crx="$(ls "$dir"/extensions/bitwarden-*.crx 2>/dev/null | head -n 1)"
ws_crx="$(ls "$dir"/extensions/chromium-web-store-*.crx 2>/dev/null | head -n 1)"
check "Bitwarden CRX downloaded" test -s "$bw_crx"
check "chromium-web-store CRX downloaded" test -s "$ws_crx"
check "versions recorded" test -s "$dir/extensions/bitwarden.version" -a -s "$dir/extensions/chromium-web-store.version"
expect_match "Bitwarden external entry points at its CRX" "\"external_crx\": \"$bw_crx\"" "$(cat "$profile/External Extensions/$BITWARDEN_ID.json" 2>/dev/null)"
expect_match "chromium-web-store external entry points at its CRX" "\"external_crx\": \"$ws_crx\"" "$(cat "$profile/External Extensions/$WEB_STORE_ID.json" 2>/dev/null)"
expect "profile seeded with the pins" "$(pins)" "$BITWARDEN_ID,$WEB_STORE_ID"
check "bin/chromium and bin/check are executable" test -x "$dir/bin/chromium" -a -x "$dir/bin/check"
check "config not written (--no-config)" test ! -e "$dir/config.json"
expect "~/.agent-browser/config.json untouched by --no-config" "$(mtime "$HOME/.agent-browser/config.json")" "$ab_config_before"

python3 -I - "$config" "$session" "$dir/bin/chromium" "$profile" <<'PY'
import json, sys
out, session, chromium, profile = sys.argv[1:]
json.dump({"session": session, "executablePath": chromium, "profile": profile,
           "args": "--extension-mime-request-handling=always-prompt,about:blank", "headed": True},
          open(out, "w"), indent=2)
PY

# --- 3. Launch through agent-browser ----------------------------------------------------------
section "Launch (session $session)"
expect "bin/check before launch" "$("$dir/bin/check" 2>&1)" "closed"
expect_match "open https://example.com" 'example\.com' "$(ab open https://example.com 2>&1)"
sleep 2
pid="$(pgrep -f "user-data-dir=$profile" | head -n 1 || true)"
check "browser process is up" test -n "$pid"
cmdline="$(ps -o args= -p "${pid:-0}" 2>/dev/null || true)"
expect_match "runs the app's binary (bin/chromium exec'd it)" "^$chromium " "$cmdline"
expect_match "data dir is the temp profile" "user-data-dir=$profile" "$cmdline"
expect_match "CRX install flag" 'extension-mime-request-handling=always-prompt' "$cmdline"
expect_no_match "no --use-mock-keychain (real keychain, like a Finder launch)" 'use-mock-keychain' "$cmdline"
expect_no_match "no --disable-default-apps (external extensions load)" 'disable-default-apps' "$cmdline"
expect_no_match "no --load-extension (extensions live in the profile)" 'load-extension' "$cmdline"
check "headed (no --headless)" test "${cmdline/--headless/}" = "$cmdline"
expect "bin/check while launched" "$("$dir/bin/check" 2>&1)" "agent"

port="$(head -n 1 "$profile/DevToolsActivePort" 2>/dev/null || true)"
pages="$(curl -sf --max-time 2 "http://127.0.0.1:${port:-0}/json/list" 2>/dev/null \
  | python3 -I -c 'import json,sys; print("\n".join(t["url"] for t in json.load(sys.stdin) if t["type"]=="page"))' 2>/dev/null)"
expect_match "example.com is a page" 'https://example\.com/' "$pages"
check "no orphaned chrome://newtab tab" test "${pages/chrome:\/\/newtab/}" = "$pages"
expect_match "snapshot of example.com has element refs" 'ref=' "$(ab snapshot 2>&1)"

# Chromium installs the external extensions shortly after start, switched off until approved.
for _ in $(seq 1 30); do
  [ -d "$profile/Default/Extensions/$BITWARDEN_ID" ] && [ -d "$profile/Default/Extensions/$WEB_STORE_ID" ] && break
  sleep 0.5
done
check "Bitwarden installed into the profile" test -d "$profile/Default/Extensions/$BITWARDEN_ID"
check "chromium-web-store installed into the profile" test -d "$profile/Default/Extensions/$WEB_STORE_ID"

# Approve them the way the user does: the switches on chrome://extensions.
ab open chrome://extensions >/dev/null 2>&1; sleep 2
switches="$(ab snapshot 2>&1 | sed -nE 's/.*switch "Off" \[checked=false, ref=(e[0-9]+)\].*/\1/p')"
expect "two extensions waiting to be switched on" "$(printf '%s\n' "$switches" | grep -c .)" "2"
for ref in $switches; do ab click "@$ref" >/dev/null 2>&1; sleep 1; done
expect_no_match "both switched on" 'switch "Off"' "$(ab snapshot 2>&1)"
sleep 1
expect_match "Bitwarden popup renders" 'Bitwarden' "$(ab open "chrome-extension://$BITWARDEN_ID/popup/index.html" >/dev/null 2>&1; sleep 2; ab snapshot 2>&1)"

# --- 4. Quit ------------------------------------------------------------------------------------
section "Quit"
expect_match "agent-browser close" 'closed' "$(ab close 2>&1)"
sleep 2
check "browser process gone" test -z "$(pgrep -f "user-data-dir=$profile" || true)"
expect "bin/check after quit" "$("$dir/bin/check" 2>&1)" "closed"
expect "pins kept after quit" "$(pins)" "$BITWARDEN_ID,$WEB_STORE_ID"
expect "Bitwarden is an external-pref install (location 2)" "$(ext_pref "$BITWARDEN_ID" location)" "2"
expect "chromium-web-store is an external-pref install (location 2)" "$(ext_pref "$WEB_STORE_ID" location)" "2"
expect_match "Bitwarden stays enabled on disk" '^(null|\[\])$' "$(ext_pref "$BITWARDEN_ID" disable_reasons)"
expect_match "chromium-web-store stays enabled on disk" '^(null|\[\])$' "$(ext_pref "$WEB_STORE_ID" disable_reasons)"
check "profile survives (persistent, not temp)" test -d "$profile/Default"

# --- 5. Nothing real was touched ----------------------------------------------------------------
section "Isolation"
expect "daily Chromium profile untouched" "$(mtime "$daily_prefs")" "$daily_before"
expect "real Agent-Chromium profile untouched" "$(mtime "$real_prefs")" "$real_before"
expect "~/.agent-browser/config.json untouched" "$(mtime "$HOME/.agent-browser/config.json")" "$ab_config_before"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
