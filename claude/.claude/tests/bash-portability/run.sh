#!/usr/bin/env bash
# Bash 3.2 portability test.
#
# Hooks are launched as `bash <path>` from settings.json, so the interpreter is
# whatever `bash` resolves to on PATH -- on macOS that is /bin/bash 3.2.57, and
# the shebang is bypassed entirely. Bash 4 syntax therefore cannot be used in
# any file that runs this way.
#
# The failure is near-silent: `${var,,}` raises "bad substitution" on stderr,
# the expansion yields an empty string, and the check it feeds simply never
# matches. permission-policy.sh's entire check_web_fetch was dead this way --
# webhook hosts, oversized query strings and local-path URLs went unflagged --
# and nothing surfaced it until its suite was run.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

# Every scan below shells out to git, so establish that git works here first.
# Distinguish "not a repo" from "git is broken": an unusable git toolchain (a
# macOS Xcode licence prompt, for instance) exits non-zero too, and blaming the
# repository sends the reader to the wrong place.
if ! _git_err="$(cd "$REPO" && git rev-parse --git-dir 2>&1 >/dev/null)"; then
  if [[ -n "$_git_err" ]]; then
    bad "git is unusable here, so this check cannot run: $_git_err"
  else
    bad "$REPO is not a git repository; this check cannot run"
  fi
  echo; echo "bash-portability: FAILURES"; exit 1
fi

# Bash 4+ constructs, with what to use instead:
#   ${x,,} ${x^^} ${x,} ${x^}  -> to_lower from lib/portability.sh, or tr
#   ${a[k],,}                  -> same, on a subscripted element
#   -A associative arrays      -> indexed arrays (numeric keys are sparse-safe),
#                                 parallel arrays, or a different data shape
#   mapfile / readarray        -> while IFS= read -r ... done < <(...)
#   coproc                     -> a named pipe, or a background job
#
# The -A branch deliberately covers every declaring keyword and any flag
# cluster containing A (declare -gA, local -Ar, ...). A bare `declare -A` regex
# missed a live `local -A` in lib/notify-pane.sh.
#
# NOT yet detected: `local -n` / `declare -n` namerefs (bash 4.3+). There are
# ten live sites in codex/.codex/hooks/, which codex invokes the same way
# (`bash "$HOME/.codex/hooks/..."`), and atomic-commits.sh already dies there
# with "local: -n: invalid option". Rewriting ten pass-by-reference sites is
# its own change, so the detector lands with that fix rather than failing this
# suite for a class this branch does not repair. Add the branch below when
# codex is clean:
#   |(declare|typeset|local)[[:space:]]+-[A-Za-z]*n([[:space:]]|$)
BASH4='\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,|\^\^|,|\^)\}'
BASH4="$BASH4"'|(declare|typeset|local|readonly|export)[[:space:]]+-[A-Za-z]*A([[:space:]]|$)'
BASH4="$BASH4"'|mapfile|readarray|coproc[[:space:]]'

# Files carrying their own BASH_VERSINFO guard are exempt: they have ensured a
# bash 4+ interpreter before using bash 4 syntax, which is the actual rule. A
# standalone script can re-exec under a newer bash; a hook sourced by another
# hook cannot, so it must stay 3.2-clean.
#
# The exemption requires executable code, not a mention. A comment reading
# "BASH_VERSINFO[0] < 4" used to exempt an entire file, and the pattern also
# rejected two legitimate spellings -- braced ${BASH_VERSINFO[0]} and the -lt
# form -- so both are accepted now, and an `exec` must appear within a few
# lines of the comparison.
VERCHECK='BASH_VERSINFO\[0\]\}?["'"'"']?[[:space:]]*(<|-lt)[[:space:]]*4'
guarded=""
while IFS= read -r _cand; do
  [[ -n "$_cand" ]] || continue
  # Keep the comparison line plus the following window, and treat the guard as
  # real only if it re-execs within it. A commented mention has no exec beneath
  # it. The window is wide enough for a candidate loop that version-checks each
  # entry before exec'ing, which is what the picker does.
  if grep -hE -A15 "$VERCHECK" "$REPO/$_cand" 2>/dev/null \
    | grep -qE '^[[:space:]]*[^#]*\bexec[[:space:]]'; then
    guarded="${guarded}${_cand}"$'\n'
  fi
done <<<"$(cd "$REPO" && git grep -lE "$VERCHECK" -- '*.sh' 'bin/.local/bin/*' 2>/dev/null || true)"

# Comment lines are excluded: this suite, portability.sh, and CLAUDE.md all
# name these constructs while documenting them.
# This suite is excluded from its own scan: it names every banned
# construct in order to search for them, so it would always flag itself.
SELF=':!claude/.claude/tests/bash-portability'

hits="$(cd "$REPO" && git grep -nE "$BASH4" -- '*.sh' 'bin/.local/bin/*' "$SELF" \
  2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"

# Drop hits from guarded files, matching on the path before the first colon.
if [[ -n "$guarded" && -n "$hits" ]]; then
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    hits="$(printf '%s\n' "$hits" | grep -v "^${g}:" || true)"
    ok "$g declares a bash 4+ guard; exempt"
  done <<<"$guarded"
fi

if [[ -z "$hits" ]]; then
  ok "no bash 4+ constructs in tracked shell files"
else
  while IFS= read -r line; do
    [[ -n "$line" ]] && bad "bash 4+ construct: $line"
  done <<<"$hits"
fi

# A control character as an IFS separator is a separate 3.2 trap, and a
# nastier one because the character is invisible in a diff. bash 3.2's `read`
# accepts the assignment and then declines to split on it, leaving the
# separator inside the first variable. read-once.sh joined seven fields on SOH
# and every one of them landed in SESSION_ID, so the hook exited 0 on every
# call. $'\t' and $'\n' are fine and are spelled with letters, so they do not
# match these fixed strings.
ctrl_ifs="$(cd "$REPO" && git grep -nF -e "IFS=\$'\\x" -e "IFS=\$'\\0" \
  -- '*.sh' 'bin/.local/bin/*' "$SELF" 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"

if [[ -z "$ctrl_ifs" ]]; then
  ok "no control-character IFS separators"
else
  while IFS= read -r line; do
    [[ -n "$line" ]] && bad "control-character IFS (bash 3.2 will not split on it): $line"
  done <<<"$ctrl_ifs"
fi

# to_lower is the sanctioned replacement, so prove it works under the oldest
# interpreter this repo supports rather than only under the one running here.
PORT="$REPO/claude/.claude/lib/portability.sh"
if [[ ! -f "$PORT" ]]; then
  bad "missing $PORT"
elif [[ ! -x /bin/bash ]]; then
  bad "/bin/bash absent; cannot verify to_lower on the system interpreter"
else
  got="$(/bin/bash -c "source '$PORT'; to_lower 'MiXeD CaSe'" 2>&1)"
  if [[ "$got" == "mixed case" ]]; then
    ok "to_lower works on /bin/bash ($(/bin/bash -c 'echo $BASH_VERSION'))"
  else
    bad "to_lower on /bin/bash produced '$got' (want 'mixed case')"
  fi
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "bash-portability: all passed"
else
  echo "bash-portability: FAILURES"
fi
exit $fail
