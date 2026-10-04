#!/bin/bash
# Launch Agent-Chromium with macOS's sandbox denying every access to the daily Chromium's folders.
#
#   scripts/guarded-run.sh [chromium args...]
#
# For the first runs of a new build, when the data-dir behavior is unproven: if anything in the
# launcher or plist patch is wrong, the browser fails with EPERM instead of touching the daily
# profile. Watch denials with:
#   log stream --style compact --predicate 'eventMessage CONTAINS "deny" AND eventMessage CONTAINS "Chromium"'
#
# Chromium's own helper sandbox cannot start inside sandbox-exec (nested sandboxes: "Failed to
# initialize sandbox", the GPU helper exits and Chromium quits), so the browser runs with
# --no-sandbox here. Diagnostic use only; never launch it that way otherwise.
set -euo pipefail

app="${AGENT_CHROMIUM_APP:-/Applications/Agent-Chromium.app}"
[ -x "$app/Contents/MacOS/Chromium" ] || { echo "no app at $app (set AGENT_CHROMIUM_APP)" >&2; exit 1; }

profile="(version 1)
(allow default)
(deny file* (subpath \"$HOME/Library/Application Support/Chromium\"))
(deny file* (subpath \"$HOME/Library/Caches/Chromium\"))
(deny file* (subpath \"$HOME/Library/Saved Application State/org.chromium.Chromium.savedState\"))
(deny file* (literal \"$HOME/Library/Preferences/org.chromium.Chromium.plist\"))"

export AGENT_CHROMIUM_VERBOSE=1
exec sandbox-exec -p "$profile" "$app/Contents/MacOS/Chromium" --no-sandbox "$@"
