#!/bin/bash
# Agent-Chromium launcher: the one place where launch flags are decided.
#
# Runs for every launch path. Contents/MacOS/Chromium is a stub that execs this script (Dock,
# Spotlight, `open -a`, launchd, Playwright's executablePath), and the `agent-chromium` CLI is a
# symlink to that stub. The script adds what every launch needs, seeds a fresh data dir, and passes
# the caller's own arguments through. Settings that are not flags live in initial_preferences.json.
#
# CLI subcommands (first argument):
#   agent-chromium status   is the resident browser up? prints its version endpoint
#   agent-chromium ensure   start the browser if it is not running
#   agent-chromium plugin   agent-browser browser-provider plugin (stdin/stdout JSON)
#   agent-chromium setup    (re)write agent-browser config and agent skills
#
# Environment:
#   AGENT_CHROMIUM_USER_DATA_DIR  data dir for standalone launches (default below)
#   AGENT_CHROMIUM_DEBUG_PORT     remote-debugging port for standalone launches (default 9222)
#   AGENT_CHROMIUM_NO_DEBUG=1     do not open a remote-debugging port
#   AGENT_CHROMIUM_VERBOSE=1      print the final command line to stderr
set -euo pipefail

resources="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # Contents/Resources
contents="$(cd "$resources/.." && pwd)"                          # Contents
app_bundle="$(cd "$contents/.." && pwd)"                         # Agent-Chromium.app
chromium="$contents/MacOS/Chromium-bin"
extensions_dir="$resources/extensions"
prefs_template="$resources/agent-chromium/initial_preferences.json"

default_user_data_dir="${AGENT_CHROMIUM_USER_DATA_DIR:-$HOME/Library/Application Support/Agent-Chromium/User Data}"
debug_port="${AGENT_CHROMIUM_DEBUG_PORT:-9222}"

[ -x "$chromium" ] || { echo "agent-chromium: browser binary missing at $chromium" >&2; exit 1; }

# --- CLI subcommands -----------------------------------------------------------------------------
# Which process owns the stable profile: Chromium keeps a SingletonLock symlink in the data dir
# whose target is "<hostname>-<pid>". A live pid there is our browser (a stale lock after a
# crash points at a dead pid and Chromium replaces it on the next start).
resident_pid() {
  local target pid
  target="$(readlink "$default_user_data_dir/SingletonLock" 2>/dev/null)" || return 1
  pid="${target##*-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  printf '%s' "$pid"
}
# Its remote-debugging port: the configured one, unless the browser had to fall back to an
# ephemeral port (then Chromium wrote DevToolsActivePort, port on the first line; it writes
# that file only for port 0).
resident_port() {
  local file="$default_user_data_dir/DevToolsActivePort"
  if [ -f "$file" ]; then head -n 1 "$file"; else printf '%s' "$debug_port"; fi
}
resident_running() {
  resident_pid >/dev/null || return 1
  curl -sf --max-time 1 "http://127.0.0.1:$(resident_port)/json/version" >/dev/null 2>&1
}
port_busy() { nc -z -w 1 127.0.0.1 "$1" >/dev/null 2>&1; }

cmd_status() {
  if resident_running; then
    echo "Agent-Chromium is running (pid $(resident_pid)); remote debugging on 127.0.0.1:$(resident_port)"
    curl -sf --max-time 1 "http://127.0.0.1:$(resident_port)/json/version"
    echo
  elif resident_pid >/dev/null; then
    echo "Agent-Chromium is running (pid $(resident_pid)) but remote debugging is not answering on" \
         "127.0.0.1:$(resident_port); it may have been launched with AGENT_CHROMIUM_NO_DEBUG=1"
    return 1
  else
    echo "Agent-Chromium is not running (start it with: agent-chromium ensure)"
    return 1
  fi
}

cmd_ensure() {
  if resident_running; then
    echo "Agent-Chromium already running on 127.0.0.1:$(resident_port)"
    return 0
  fi
  if resident_pid >/dev/null; then
    echo "agent-chromium: Agent-Chromium is running (pid $(resident_pid)) without remote debugging;" \
         "quit it and retry" >&2
    return 1
  fi
  # -g: don't steal focus. A normal window opens: --no-startup-window would avoid that but puts
  # Chromium in background mode, where Quit (Dock, Cmd-Q, brew's uninstall quit:) is ignored
  # (verified 2026-10-01). --agent-chromium-quiet-start is ours (stripped by this launcher): no
  # first-run settings tab when an agent starts the browser. `open` hands the process to launchd.
  open -g -a "$app_bundle" --args --agent-chromium-quiet-start
  ensure_started=1
  for _ in $(seq 1 40); do
    if resident_running; then
      echo "Agent-Chromium started; remote debugging on 127.0.0.1:$(resident_port)"
      return 0
    fi
    sleep 0.5
  done
  echo "agent-chromium: browser did not come up within 20s" >&2
  return 1
}

# agent-browser browser-provider plugin (protocol agent-browser.plugin.v1): one JSON request on
# stdin, one JSON response on stdout, nothing else on stdout. Configured by setup.sh as the
# default provider, so every agent-browser command attaches to Agent-Chromium, starting it first
# when needed. Each session gets its own new tab. browser.close is a no-op: the browser is the
# user's, agents never close it (agent-browser does not call it for attached browsers anyway).
ensure_started=0
cmd_plugin() {
  local input type port ws id
  input="$(cat)"
  type="$(printf '%s' "$input" | grep -o '"type":"[^"]*"' | head -n 1 | cut -d'"' -f4)"
  reply() { printf '{"protocol":"agent-browser.plugin.v1","success":true,%s}' "$1"; }
  fail()  { printf '{"protocol":"agent-browser.plugin.v1","success":false,"error":"%s"}' "$1"; exit 0; }
  case "$type" in
    plugin.manifest)
      reply '"manifest":{"name":"agent-chromium","capabilities":["browser.provider"],"description":"Attach to the running Agent-Chromium, starting it first if needed"}' ;;
    browser.launch)
      cmd_ensure >&2 || fail "Agent-Chromium did not start"
      port="$(resident_port)"
      # A fresh tab for this agent session, handed over as a page endpoint (directPage). Bound
      # to a browser endpoint, agent-browser takes over an existing tab instead: it navigated
      # the user's tabs and two sessions fought over the same one (verified 2026-09-30).
      ws="$(curl -sf --max-time 2 -X PUT "http://127.0.0.1:$port/json/new?about:blank" \
            | grep -o '"webSocketDebuggerUrl": *"[^"]*"' | head -n 1 | sed 's/.*"\(ws[^"]*\)"/\1/')"
      [ -n "$ws" ] || fail "could not open a tab on 127.0.0.1:$port"
      # If we just started the browser, its startup new-tab page is empty clutter next to the
      # agent's tab; close it. Never when the browser was already running (those tabs are the
      # user's).
      if [ "$ensure_started" -eq 1 ]; then
        for id in $(curl -sf --max-time 2 "http://127.0.0.1:$port/json/list" \
                    | grep -B3 '"url": "chrome://newtab/"' | grep -o '"id": "[^"]*"' | cut -d'"' -f4); do
          curl -sf --max-time 2 "http://127.0.0.1:$port/json/close/$id" >/dev/null 2>&1
        done
      fi
      reply "\"browser\":{\"cdpUrl\":\"$ws\",\"directPage\":true}" ;;
    browser.close)
      reply '"data":{}' ;;
    *)
      fail "unsupported request type: $type" ;;
  esac
}

case "${1:-}" in
  status) cmd_status; exit $? ;;
  ensure) cmd_ensure; exit $? ;;
  plugin) cmd_plugin; exit $? ;;
  setup)  shift; exec "$resources/agent-chromium/setup.sh" "$@" ;;
  help|--help|-h)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

# --- Sort the caller's arguments -----------------------------------------------------------------
user_data_dir=""
driven=0            # a driver (Playwright, hence agent-browser) is attached over a CDP pipe
has_debug_port=0
quiet_start=0       # started by `ensure`/the plugin: no first-run settings tab
caller_load=""
caller_except=""
args=()

for arg in "$@"; do
  case "$arg" in
    --user-data-dir=*)             user_data_dir="${arg#*=}"; args+=("$arg") ;;
    --remote-debugging-pipe*)      driven=1; args+=("$arg") ;;
    --remote-debugging-port=*)     has_debug_port=1; args+=("$arg") ;;
    --load-extension=*)            caller_load="${arg#*=}" ;;
    --disable-extensions-except=*) caller_except="${arg#*=}" ;;
    # Playwright passes this by default. Dropped: the bundled extensions are the point of this app.
    --disable-extensions)          ;;
    --agent-chromium-quiet-start)  quiet_start=1 ;;
    *)                             args+=("$arg") ;;
  esac
done

# --- Bundled extensions --------------------------------------------------------------------------
bundled=""
if [ -d "$extensions_dir" ]; then
  for dir in "$extensions_dir"/*/; do
    dir="${dir%/}"
    [ -f "$dir/manifest.json" ] || continue
    bundled="${bundled:+$bundled,}$dir"
  done
fi

load="$bundled"
[ -n "$caller_load" ] && load="${load:+$load,}$caller_load"
[ -n "$load" ] && args+=("--load-extension=$load")
# If the caller restricted extensions to an allowlist, keep ours on it.
[ -n "$caller_except" ] && args+=("--disable-extensions-except=${bundled:+$bundled,}$caller_except")

# Lets chromium-web-store (and the user) install CRX files; ungoogled-chromium downloads them
# as plain files otherwise. This is a chrome://flags entry, so it cannot live in preferences.
args+=("--extension-mime-request-handling=always-prompt")

# "Chromium isn't your default browser" bar on every start. Only this flag (or an enterprise
# policy) turns it off; no user-level preference does.
args+=("--no-default-browser-check")

# --- Standalone launch: the stable profile, remote debugging on ---------------------------------
# A standalone launch is one no driver is attached to: Dock, Spotlight, `open -a`, the CLI.
# It uses the one stable data dir (explicit, because Chromium refuses remote debugging on
# the default dir) and opens the remote-debugging port that agent-browser attaches to.
if [ "$driven" -eq 0 ] && [ -z "$user_data_dir" ]; then
  user_data_dir="$default_user_data_dir"
  args+=("--user-data-dir=$user_data_dir")
fi
if [ "$driven" -eq 0 ] && [ "$has_debug_port" -eq 0 ] && [ -z "${AGENT_CHROMIUM_NO_DEBUG:-}" ]; then
  # Another browser on the port would leave us without remote debugging. Port 0 makes Chromium
  # pick a free one and write it to <data dir>/DevToolsActivePort, which resident_port() reads.
  if port_busy "$debug_port"; then
    echo "agent-chromium: port $debug_port is in use; using an ephemeral remote-debugging port" >&2
    debug_port=0
  fi
  args+=("--remote-debugging-port=$debug_port")
fi

# --- Seed a fresh data dir -----------------------------------------------------------------------
# Only when no profile exists yet: existing profiles belong to the user (or the driver).
if [ -n "$user_data_dir" ] && [ ! -d "$user_data_dir/Default" ]; then
  mkdir -p "$user_data_dir/Default"
  [ -f "$prefs_template" ] && cp "$prefs_template" "$user_data_dir/Default/Preferences"
  : > "$user_data_dir/First Run"    # sentinel: skips first-run UI, same as --no-first-run
  # The default search engine is a tamper-protected setting that cannot be seeded (ungoogled
  # ships "No Search"), so the very first standalone launch opens the page where the user picks
  # one. Chromium ignores chrome:// URLs on the command line, so a detached helper opens the tab
  # through the remote-debugging port once the browser answers (the exec below replaces this
  # shell; the helper outlives it). A launch by `ensure`/the plugin stays quiet.
  if [ "$driven" -eq 0 ] && [ "$quiet_start" -eq 0 ] && [ -z "${AGENT_CHROMIUM_NO_DEBUG:-}" ]; then
    (
      for _ in $(seq 1 60); do
        sleep 0.5
        if [ "$debug_port" = 0 ]; then
          p="$(head -n 1 "$user_data_dir/DevToolsActivePort" 2>/dev/null)" || continue
          [ -n "$p" ] || continue
        else
          p="$debug_port"
        fi
        if curl -sf --max-time 1 "http://127.0.0.1:$p/json/version" >/dev/null 2>&1; then
          curl -sf --max-time 2 -X PUT "http://127.0.0.1:$p/json/new?chrome://settings/search" >/dev/null 2>&1
          break
        fi
      done
    ) >/dev/null 2>&1 </dev/null &
  fi
fi

# --- Setup on the first standalone launch of each version ---------------------------------------
# Homebrew's install sandbox fakes $HOME, so the cask cannot write the agent-browser config;
# `agent-chromium setup` is the post-install step. As a safety net, the first standalone launch
# of each version writes the config too (never skills: that is opt-in and needs a terminal).
if [ "$driven" -eq 0 ] && [ -z "${AGENT_CHROMIUM_SKIP_SETUP:-}" ]; then
  version="$(cat "$resources/agent-chromium/VERSION" 2>/dev/null || echo unknown)"
  marker="$default_user_data_dir/../setup-version"
  if [ "$(cat "$marker" 2>/dev/null || true)" != "$version" ]; then
    "$resources/agent-chromium/setup.sh" --skills no >&2 || true
    mkdir -p "$(dirname "$marker")" && printf '%s\n' "$version" > "$marker"
  fi
fi

if [ -n "${AGENT_CHROMIUM_VERBOSE:-}" ]; then
  printf 'agent-chromium: exec %q' "$chromium" >&2
  for arg in ${args[@]+"${args[@]}"}; do printf ' %q' "$arg" >&2; done
  printf '\n' >&2
fi

exec "$chromium" ${args[@]+"${args[@]}"}
