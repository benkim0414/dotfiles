#!/usr/bin/env bash
# caveman default-mode test.
#
# The caveman plugin resolves its level in this order:
#   CAVEMAN_DEFAULT_MODE env
#   -> repo-local .caveman/config.json or .caveman.json, walking up from cwd
#   -> user config (~/.config/caveman/config.json)
#   -> 'full'
#
# The stowed user config pins 'off'. Each assertion below guards one way a
# higher-priority source could silently override it.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
CONFIG="$REPO/caveman/.config/caveman/config.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

# The stowed user config must pin the default to 'off'. 'off' is a member of
# the plugin's VALID_MODES, so it is accepted rather than ignored as garbage.
if [[ ! -f "$CONFIG" ]]; then
  bad "missing $CONFIG"
elif ! jq empty "$CONFIG" 2>/dev/null; then
  bad "$CONFIG is not valid JSON"
else
  mode="$(jq -r '.defaultMode // empty' "$CONFIG")"
  if [[ "$mode" == "off" ]]; then
    ok "user config defaultMode = off"
  else
    bad "user config defaultMode = '${mode:-<unset>}' (want off)"
  fi
fi

# A repo-local config outranks the user config, so one committed anywhere in
# this repo would silently re-enable compression for every session run here.
repo_local="$(cd "$REPO" && git ls-files -- \
  '.caveman.json' '*/.caveman.json' \
  '.caveman/config.json' '*/.caveman/config.json')"
if [[ -z "$repo_local" ]]; then
  ok "no repo-local caveman config tracked"
else
  bad "repo-local caveman config outranks user config: ${repo_local//$'\n'/ }"
fi

# The environment variable outranks every file, so an export in the shell
# config would defeat the user config on every machine that stows zsh.
if grep -rn 'CAVEMAN_DEFAULT_MODE' "$REPO/zsh" >/dev/null 2>&1; then
  bad "CAVEMAN_DEFAULT_MODE set in the zsh package (env outranks user config)"
else
  ok "CAVEMAN_DEFAULT_MODE not set in zsh package"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "caveman-default-off: all passed"
else
  echo "caveman-default-off: FAILURES"
fi
exit $fail
