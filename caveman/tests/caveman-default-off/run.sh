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
REPO="$(cd "$HERE/../../.." && pwd)"
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

# Every check below shells out to git, so establish that git works here
# first. Without this, a git failure leaves the result variables empty and
# each assertion reports ok -- passing precisely when it cannot look.
if ! (cd "$REPO" && git rev-parse --git-dir >/dev/null 2>&1); then
  bad "$REPO is not a git repository; the checks below cannot run"
  echo
  echo "caveman-default-off: FAILURES"
  exit 1
fi

# A repo-local config outranks the user config, so one committed anywhere in
# this repo would silently re-enable compression for every session run here.
# Git's default pathspec omits WM_PATHNAME, so '*' crosses '/' and these four
# patterns cover every depth.
repo_local="$(cd "$REPO" && git ls-files -- \
  '.caveman.json' '*/.caveman.json' \
  '.caveman/config.json' '*/.caveman/config.json')"
if [[ -z "$repo_local" ]]; then
  ok "no repo-local caveman config tracked"
else
  bad "repo-local caveman config outranks user config: ${repo_local//$'\n'/ }"
fi

# The environment variable outranks every file, so an assignment anywhere the
# repo can export from defeats the user config. Search the whole repo rather
# than one package: zsh is not the only export vector -- settings.base.json
# has an env block, which is how CLAUDE_GIT_WORKFLOW is set. Match only
# assignment-shaped occurrences, and exclude the docs and this suite, all of
# which name the variable while documenting it.
env_hits="$(cd "$REPO" && git grep -lE '(export[[:space:]]+)?CAVEMAN_DEFAULT_MODE=' -- \
  . ':!docs' ':!CLAUDE.md' ':!caveman/tests' ':!claude/.claude/tests' 2>/dev/null)"
if [[ -z "$env_hits" ]]; then
  ok "CAVEMAN_DEFAULT_MODE not assigned anywhere in the repo"
else
  bad "CAVEMAN_DEFAULT_MODE assigned in: ${env_hits//$'\n'/ }"
fi

# The settings env block exports without an '=' sign, so the grep above
# cannot see it.
for settings in "$REPO/claude/.claude/settings.base.json" \
                "$REPO/claude/.claude/settings.overlay.json"; do
  [[ -f "$settings" ]] || continue
  if jq -e '.env.CAVEMAN_DEFAULT_MODE // empty' "$settings" >/dev/null 2>&1; then
    bad "CAVEMAN_DEFAULT_MODE exported from $(basename "$settings") env block"
  else
    ok "$(basename "$settings") env block does not set CAVEMAN_DEFAULT_MODE"
  fi
done

echo
if [[ $fail -eq 0 ]]; then
  echo "caveman-default-off: all passed"
else
  echo "caveman-default-off: FAILURES"
fi
exit $fail
