#!/bin/bash
# Smoke test an Agent-Chromium app on a throwaway profile: bundle, first launch, the agent-browser
# plugin, an agent-browser battery, and the browser lifecycle.
#
#   scripts/smoke-test.sh [--app <path>] [--port <n>] [--keep]
#
# --app   the app to test (default /Applications/Agent-Chromium.app; a build/<arch>/ app works too,
#         x86_64 runs under Rosetta)
# --port  remote-debugging port for the test browser (default 9555)
# --keep  leave the temp dir (profile, logs, screenshots) for inspection instead of deleting it
#
# Never touches a real profile: the browser gets a temp data dir and its own port, agent-browser a
# temp config and its own namespace, and the run fails if the browser opens anything in the daily
# Chromium or the real Agent-Chromium data folders. A window opens while it runs. Both can stay
# open meanwhile. Not covered: the plugin cold-starting the browser (that goes through `open -a`,
# which would reach a running real instance), and anything that needs eyes (see the testing notes).
# Needs agent-browser, curl, python3. Runs every check and reports; exit status 1 if any failed.
set -uo pipefail

app="/Applications/Agent-Chromium.app"
port=9555
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --app)  app="${2%/}"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --keep) keep=1; shift ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BITWARDEN_ID="nkanlecjgnbjkjanadbbedolemolellk"
WEB_STORE_ID="ocaahdebbfolfmndjeplogmgcagdmblk"
stub="$app/Contents/MacOS/Chromium"
for tool in agent-browser curl python3 lsof nc; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 1; }
done
[ -x "$stub" ] || { echo "no app at $app" >&2; exit 1; }
nc -z -w 1 127.0.0.1 "$port" 2>/dev/null && { echo "port $port is in use; pass --port" >&2; exit 1; }

tmp="$(mktemp -d /tmp/agent-chromium-smoke.XXXXXX)"
udd="$tmp/User Data"
ns="smoke$$"
cfg="$tmp/agent-browser.json"
site="$tmp/site"
browser_pid=""
http_pid=""

# --- Reporting ----------------------------------------------------------------------------------
passed=0
failed=0
failures=()
ok()   { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
bad()  { failed=$((failed + 1)); failures+=("$1"); printf '  FAIL  %s%s\n' "$1" "${2:+  ($2)}"; }
section() { printf '\n%s\n' "$1"; }
# expect <description> <expected> <actual>
expect() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
# expect_match <description> <regex> <actual>
expect_match() { if [[ "$3" =~ $2 ]]; then ok "$1"; else bad "$1" "no match for /$2/ in '${3:0:200}'"; fi; }
# check <description> <command...>: passes when the command succeeds
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

# --- Helpers ------------------------------------------------------------------------------------
env_vars=(AGENT_CHROMIUM_USER_DATA_DIR="$udd" AGENT_CHROMIUM_DEBUG_PORT="$port" AGENT_CHROMIUM_SKIP_SETUP=1)
cli() { env "${env_vars[@]}" "$stub" "$@"; }
ab()  { agent-browser --config "$cfg" --namespace "$ns" "$@"; }
cdp() { curl -sf --max-time 3 "http://127.0.0.1:$port/$1"; }
# Page targets as "id<TAB>url" lines; extension workers as their URLs.
pages()   { cdp json/list | python3 -c 'import json,sys
for t in json.load(sys.stdin):
    if t["type"] == "page": print(t["id"] + "\t" + t["url"])'; }
workers() { cdp json/list | python3 -c 'import json,sys
for t in json.load(sys.stdin):
    if t["type"] == "service_worker": print(t["url"])'; }
has_page()   { pages 2>/dev/null | grep -qF "$1"; }
no_page()    { ! has_page "$1"; }
has_worker() { workers 2>/dev/null | grep -qF "$1"; }
title_is()   { [ "$(ab --session "$1" get title 2>&1)" = "$2" ]; }
not_running() { ! cli status; }
pinned_ids() {
  python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1])).get("extensions",{}).get("pinned_extensions",[])))' \
    "$udd/Default/Preferences" 2>/dev/null
}
lock_pid() { local t; t="$(readlink "$udd/SingletonLock" 2>/dev/null)" && printf '%s' "${t##*-}"; }
# wait_for <seconds> <command...>
wait_for() {
  local n=$(( $1 * 4 )); shift
  for _ in $(seq 1 "$n"); do "$@" >/dev/null 2>&1 && return 0; sleep 0.25; done
  return 1
}
gone() { ! kill -0 "$1" 2>/dev/null; }
start_browser() {  # a standalone launch, as from the Dock, on the throwaway profile
  env "${env_vars[@]}" "$stub" >>"$tmp/browser.log" 2>&1 &
  browser_pid=$!
  disown "$browser_pid"   # no job-control noise when the lifecycle tests kill it
  wait_for 40 cdp json/version
}
stop_browser() {
  [ -n "$browser_pid" ] && kill -0 "$browser_pid" 2>/dev/null || return 0
  kill -TERM "$browser_pid" 2>/dev/null || true
  wait_for 15 gone "$browser_pid" || kill -KILL "$browser_pid" 2>/dev/null || true
}

cleanup() {
  ab close --all >/dev/null 2>&1 || true
  stop_browser
  [ -n "$http_pid" ] && kill "$http_pid" 2>/dev/null || true
  # agent-browser keeps per-namespace state under ~/.agent-browser; drop ours.
  find "$HOME/.agent-browser" -maxdepth 2 -name "*$ns*" -exec rm -rf {} + 2>/dev/null || true
  rmdir "$HOME/.agent-browser/namespaces" 2>/dev/null || true   # only if no other namespace uses it
  if [ "$keep" -eq 1 ]; then echo "kept $tmp"; else rm -rf "$tmp"; fi
}
trap cleanup EXIT

# --- Fixtures -----------------------------------------------------------------------------------
mkdir -p "$site"
cat > "$site/index.html" <<'EOF'
<!doctype html><title>Smoke A</title>
<input id="name" aria-label="Name">
<button id="go" onclick="out.textContent = 'hello ' + document.getElementById('name').value">Go</button>
<p id="out"></p>
<label><input type="checkbox" id="cb"> Agree</label>
<select id="sel" aria-label="Pick"><option value="a">Alpha</option><option value="b">Beta</option></select>
<a id="next" href="page2.html">Next page</a>
EOF
cat > "$site/page2.html" <<'EOF'
<!doctype html><title>Smoke B</title><h1>Second page</h1>
EOF
http_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
python3 -m http.server "$http_port" --bind 127.0.0.1 --directory "$site" >/dev/null 2>&1 &
http_pid=$!
disown "$http_pid"
base="http://127.0.0.1:$http_port"

# The plugin wrapper pins the plugin to the throwaway profile; the config is what setup.sh writes,
# minus executablePath.
cat > "$tmp/plugin.sh" <<EOF
#!/bin/bash
export AGENT_CHROMIUM_USER_DATA_DIR="$udd" AGENT_CHROMIUM_DEBUG_PORT="$port" AGENT_CHROMIUM_SKIP_SETUP=1
exec "$stub" "\$@"
EOF
chmod +x "$tmp/plugin.sh"
cat > "$cfg" <<EOF
{
  "provider": "agent-chromium",
  "plugins": [
    { "name": "agent-chromium", "command": "$tmp/plugin.sh", "args": ["plugin"], "capabilities": ["browser.provider"] }
  ]
}
EOF

printf 'Smoke test: %s\n  profile %s, port %s, agent-browser %s\n' "$app" "$udd" "$port" \
  "$(agent-browser --version | awk '{print $2}')"

# --- 1. Bundle ----------------------------------------------------------------------------------
section "Bundle"
contents="$app/Contents"
res="$contents/Resources"
check "signature valid" codesign --verify --deep --strict "$app"
expect "bundle ID" "org.agent-chromium.browser" "$(plutil -extract CFBundleIdentifier raw "$contents/Info.plist")"
expect "data folder name" "Agent-Chromium" "$(plutil -extract CrProductDirName raw "$contents/Info.plist")"
expect_match "browser binary arch" '^(arm64|x86_64)$' "$(lipo -archs "$contents/MacOS/Chromium-bin")"
check "Bitwarden carries the fixed-ID key" plutil -extract key raw "$res/extensions/bitwarden/manifest.json"
check "chromium-web-store bundled" test -f "$res/extensions/chromium-web-store/manifest.json"
check "notices and licenses bundled" test -f "$res/agent-chromium/THIRD_PARTY.md" -a -d "$res/agent-chromium/licenses"
check "skill bundled" test -f "$res/agent-chromium/skills/agent-chromium/SKILL.md" -a -f "$res/agent-chromium/agent-chromium.skill"
version="$(cat "$res/agent-chromium/VERSION" 2>/dev/null || true)"
expect_match "VERSION file" '^[0-9.]+-[0-9.]+(_[0-9]+)?$' "$version"

# --- 2. First launch ----------------------------------------------------------------------------
section "First launch (fresh profile)"
start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
if start_browser; then
  ok "browser answers on 127.0.0.1:$port ($(( $(python3 -c 'import time; print(int(time.time()*1000))') - start_ms )) ms)"
else
  bad "browser answers on 127.0.0.1:$port" "see $tmp/browser.log"; exit 1
fi
expect "launcher process is the browser (stub exec'd through)" "$browser_pid" "$(lock_pid)"
cmdline="$(ps -o command= -p "$browser_pid")"
expect_match "runs Chromium-bin" 'MacOS/Chromium-bin' "$cmdline"
expect_match "flag: profile dir" "--user-data-dir=$udd" "$cmdline"
expect_match "flag: debug port" "--remote-debugging-port=$port" "$cmdline"
expect_match "flag: CRX installs prompt" '--extension-mime-request-handling=always-prompt' "$cmdline"
expect_match "flag: no default-browser check" '--no-default-browser-check' "$cmdline"
check "Bitwarden running under its fixed ID" wait_for 15 has_worker "$BITWARDEN_ID"
check "chromium-web-store running" wait_for 15 has_worker "$WEB_STORE_ID"
check "search-engine settings tab opened" wait_for 15 has_page "chrome://settings/search"
expect_match "Bitwarden pinned in the seeded profile" "$BITWARDEN_ID" "$(pinned_ids)"
expect_match "status reports it" "running \(pid $browser_pid\).*127.0.0.1:$port" "$(cli status 2>&1 | head -n 1)"
user_tabs="$(pages)"   # the "user's" tabs: must survive everything agents do below
expect_match "user tabs recorded for the untouched check" 'chrome://settings/search' "$user_tabs"

# --- 3. Plugin ----------------------------------------------------------------------------------
section "agent-browser plugin"
manifest="$(printf '{"type":"plugin.manifest"}' | cli plugin)"
expect_match "manifest offers browser.provider" '"capabilities":\["browser.provider"\]' "$manifest"
launch="$(printf '{"type":"browser.launch"}' | cli plugin 2>/dev/null)"
expect_match "browser.launch returns a page endpoint" "\"cdpUrl\":\"ws://127.0.0.1:$port/devtools/page/[^\"]+\",\"directPage\":true" "$launch"
probe_id="$(sed -nE 's|.*devtools/page/([^"]+)".*|\1|p' <<<"$launch")"
check "  ... as a fresh about:blank tab" has_page "$probe_id	about:blank"
cdp "json/close/$probe_id" >/dev/null || true
expect_match "unknown request fails cleanly" '"success":false' "$(printf '{"type":"nope"}' | cli plugin)"

# --- 4. agent-browser battery -------------------------------------------------------------------
section "agent-browser (session a)"
a() { ab --session a "$@" 2>&1; }
b() { ab --session b "$@" 2>&1; }
a open "$base/index.html" >/dev/null
expect "open + get title" "Smoke A" "$(a get title)"
expect "get url" "$base/index.html" "$(a get url)"
snap="$(a snapshot)"
expect_match "snapshot has refs" 'button "Go" \[ref=e[0-9]+\]' "$snap"
a fill "#name" "ursamageor" >/dev/null
expect "fill + get value" "ursamageor" "$(a get value '#name')"
a click "#go" >/dev/null
expect "click + get text" "hello ursamageor" "$(a get text '#out')"
go_ref="$(grep -oE 'button "Go" \[ref=e[0-9]+\]' <<<"$snap" | grep -oE 'e[0-9]+' | head -n 1)"
a fill "#name" "ref" >/dev/null
a click "@$go_ref" >/dev/null
expect "click by snapshot ref" "hello ref" "$(a get text '#out')"
a check "#cb" >/dev/null
expect "check + is checked" "true" "$(a is checked '#cb')"
a select "#sel" "Beta" >/dev/null
expect "select by label + get value" "b" "$(a get value '#sel')"
expect "eval" "2" "$(a eval '1+1')"
a find text "Next page" click >/dev/null
check "find text + click navigates" wait_for 5 title_is a "Smoke B"
a back >/dev/null
expect "back" "Smoke A" "$(a get title)"
a forward >/dev/null
expect "forward" "Smoke B" "$(a get title)"
a reload >/dev/null
expect "reload" "Smoke B" "$(a get title)"
a screenshot "$tmp/shot.png" >/dev/null
expect "screenshot is a PNG" "89504e47" "$(head -c 4 "$tmp/shot.png" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
a cookies set smoke yes --url "$base/" >/dev/null
expect_match "cookies set + get" 'smoke' "$(a cookies get)"
a storage local set smokekey smokeval >/dev/null
expect_match "localStorage set + get" 'smokeval' "$(a storage local get smokekey)"
a tab new "$base/index.html" >/dev/null
expect "tab new: session has 2 tabs" "2" "$(a tab list | grep -cE '127.0.0.1:'"$http_port")"

section "agent-browser (two sessions in parallel)"
a tab 0 >/dev/null
a open "$base/index.html" >/dev/null & pa=$!
b open "$base/page2.html" >/dev/null & pb=$!
wait "$pa" "$pb"
expect "session a kept its page" "Smoke A" "$(a get title)"
expect "session b got its own" "Smoke B" "$(b get title)"
expect "session b sees only its own tab" "1" "$(b tab list | grep -cE '127.0.0.1:'"$http_port")"
expect "session a still sees its 2 tabs" "2" "$(a tab list | grep -cE '127.0.0.1:'"$http_port")"
a eval 'document.title = "changed by a"' >/dev/null
expect "a's change doesn't leak into b" "Smoke B" "$(b get title)"

section "After the agents"
a close >/dev/null; b close >/dev/null
check "close leaves the browser running" cdp json/version
expect_match "agent tabs stay for the user to see" 'Smoke' "$(cdp json/list)"
missing=""
while IFS=$'\t' read -r id url; do
  [ -n "$id" ] || continue
  pages | grep -qF "$id	$url" || missing+=" $url"
done <<<"$user_tabs"
expect "user's tabs untouched (same tabs, same URLs)" "" "${missing# }"

# --- 5. Isolation -------------------------------------------------------------------------------
section "Isolation"
# The browser process and its helpers (renderers, GPU, network service are its children).
procs="$browser_pid$(pgrep -P "$browser_pid" | sed 's/^/,/' | tr -d '\n')"
open_files="$(lsof -p "$procs" -Fn 2>/dev/null | sed -n 's/^n//p')"
expect "no daily Chromium files open" "" "$(grep -F "$HOME/Library/Application Support/Chromium/" <<<"$open_files" | head -n 1)"
expect "no real Agent-Chromium profile files open" "" "$(grep -F "$HOME/Library/Application Support/Agent-Chromium/" <<<"$open_files" | head -n 1)"
check "profile created in the throwaway dir" test -f "$udd/Default/Preferences"

# --- 6. Lifecycle -------------------------------------------------------------------------------
section "Lifecycle"
pid="$browser_pid"
kill -TERM "$pid"
if wait_for 15 gone "$pid"; then ok "SIGTERM quits it"; else bad "SIGTERM quits it"; fi
check "status: not running after quit" not_running
expect_match "Bitwarden pin survives a quit" "$BITWARDEN_ID" "$(pinned_ids)"
if start_browser; then ok "restarts on the existing profile"; else bad "restarts on the existing profile"; fi
check "  ... without reopening the settings tab" no_page "chrome://settings/search"
pid="$browser_pid"
kill -KILL "$pid"; wait_for 5 gone "$pid" || true
check "stale lock after a crash: status says not running" not_running
if start_browser; then ok "starts again over the stale lock"; else bad "starts again over the stale lock"; fi
expect "  ... and owns the lock" "$browser_pid" "$(lock_pid)"

# --- Summary ------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$passed" "$failed"
for f in ${failures[@]+"${failures[@]}"}; do printf '  failed: %s\n' "$f"; done
[ "$failed" -eq 0 ]
