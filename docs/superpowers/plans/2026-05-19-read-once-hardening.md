# Read-once hook hardening — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix correctness bugs in the read-once PreToolUse hook, add cache GC, add escalating deny wording with touch-bypass detection, make diff mode useful by default, and add a shell test suite — all driven from the design spec at `docs/superpowers/specs/2026-05-19-read-once-hardening-design.md`.

**Architecture:** Single hook file (`claude/.claude/hooks/read-once.sh`) plus its shared library (`claude/.claude/lib/read-once-cache.sh`) plus a new `SessionEnd` GC hook (`claude/.claude/hooks/read-once-gc.sh`). Test scaffolding lives under `claude/.claude/tests/read-once/`. Operator docs at `claude/.claude/docs/read-once.md`. No new runtime dependencies; pure bash + jq + GNU coreutils.

**Tech Stack:** Bash 3.2+/5.x, jq, GNU coreutils (realpath, sha1sum), BSD `stat` fallback, POSIX `find`. Tests are plain bash scripts; runner is `run.sh`.

---

## Task 1: Test suite scaffolding

**Files:**
- Create: `claude/.claude/tests/read-once/run.sh`
- Create: `claude/.claude/tests/read-once/helpers.sh`
- Create: `claude/.claude/tests/read-once/cases/.gitkeep`
- Create: `claude/.claude/tests/read-once/fixtures/.gitkeep`

- [ ] **Step 1: Write the runner**

Create `claude/.claude/tests/read-once/run.sh`:

```bash
#!/usr/bin/env bash
# Read-once hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh and uses assert_* helpers.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export HOOK="$HERE/../../hooks/read-once.sh"
export LIB="$HERE/../../lib/read-once-cache.sh"

[[ -f "$HOOK" ]] || { echo "missing hook: $HOOK" >&2; exit 2; }
[[ -f "$LIB"  ]] || { echo "missing lib: $LIB"   >&2; exit 2; }

pass=0; fail=0; failed_cases=()
for case in "$HERE"/cases/*.sh; do
  [[ -e "$case" ]] || continue
  name="$(basename "$case" .sh)"
  if ( cd "$HERE" && bash "$case" ); then
    printf "  PASS  %s\n" "$name"
    pass=$((pass+1))
  else
    printf "  FAIL  %s\n" "$name"
    fail=$((fail+1))
    failed_cases+=("$name")
  fi
done

printf "\n%d passed, %d failed\n" "$pass" "$fail"
if (( fail > 0 )); then
  printf "failed cases: %s\n" "${failed_cases[*]}"
  exit 1
fi
```

- [ ] **Step 2: Write the helpers**

Create `claude/.claude/tests/read-once/helpers.sh`:

```bash
#!/usr/bin/env bash
# Sourced by every case. Provides setup, teardown, fixtures, assertions.

set -uo pipefail

: "${HOOK:?HOOK must be set by run.sh}"
: "${LIB:?LIB must be set by run.sh}"

CASE_TMP="$(mktemp -d -t read-once-test.XXXXXX)"
export XDG_RUNTIME_DIR="$CASE_TMP"
export READ_ONCE_DISABLE=0
export READ_ONCE_DIFF=0          # tests opt in per-case
export READ_ONCE_GC_DISABLE=1    # never prune during a single test
mkdir -p "$CASE_TMP/claude"

cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# fixture_session writes SESSION_ID to stdout
fixture_session() {
  printf '11111111-1111-1111-1111-%012x' "$RANDOM"
}

# stdin_for TOOL FILE [OFFSET] [LIMIT] [COMMAND] [OUTPUT_MODE] -> JSON on stdout
stdin_for() {
  local tool="$1" file="${2:-}" offset="${3:-0}" limit="${4:--1}"
  local cmd="${5:-}" mode="${6:-}"
  jq -cn \
    --arg sid "$SESSION_ID" \
    --arg tool "$tool" \
    --arg fp "$file" \
    --argjson off "$offset" \
    --argjson lim "$limit" \
    --arg cmd "$cmd" \
    --arg mode "$mode" \
    '{session_id:$sid, tool_name:$tool,
      tool_input:{file_path:$fp, notebook_path:$fp, path:$fp,
                  offset:$off, limit:$lim, command:$cmd, output_mode:$mode}}'
}

# run_hook reads JSON from stdin, invokes the hook, prints stdout, returns exit code.
run_hook() { bash "$HOOK"; }

assert_exit() {
  local want="$1" got="$2"
  [[ "$want" == "$got" ]] || { echo "  exit want=$want got=$got" >&2; exit 1; }
}

assert_deny() {
  local out="$1"
  echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null \
    || { echo "  expected deny JSON, got: $out" >&2; exit 1; }
}

assert_allow() {
  local out="$1"
  [[ -z "$out" ]] || { echo "  expected silent allow, got: $out" >&2; exit 1; }
}

assert_deny_contains() {
  local out="$1" needle="$2"
  echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
    | grep -qF -- "$needle" \
    || { echo "  deny reason missing '$needle'; got: $out" >&2; exit 1; }
}

SESSION_ID="$(fixture_session)"
export SESSION_ID
```

- [ ] **Step 3: Stub a smoke case to exercise the runner**

Create `claude/.claude/tests/read-once/cases/00-smoke.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# A read on a non-existent file should pass through (stat fails → allow).
payload="$(stdin_for Read /no/such/path)"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"
assert_allow "$out"
```

- [ ] **Step 4: Add `.gitkeep` files and make runner executable**

```bash
chmod +x claude/.claude/tests/read-once/run.sh
touch claude/.claude/tests/read-once/cases/.gitkeep
touch claude/.claude/tests/read-once/fixtures/.gitkeep
```

- [ ] **Step 5: Run the suite**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `1 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/tests/read-once/run.sh \
        claude/.claude/tests/read-once/helpers.sh \
        claude/.claude/tests/read-once/cases/00-smoke.sh \
        claude/.claude/tests/read-once/cases/.gitkeep \
        claude/.claude/tests/read-once/fixtures/.gitkeep
git commit -m "test(read-once): add shell test scaffolding"
```

---

## Task 2: Drop `mcp__qmd__multi_get` from matcher (Spec A.1)

**Files:**
- Modify: `claude/.claude/settings.base.json`
- Modify: `claude/.claude/hooks/read-once.sh` (header comment only)
- Create: `claude/.claude/tests/read-once/cases/10-matcher-no-multiget.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/10-matcher-no-multiget.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# Verify the active matcher string in settings.base.json excludes multi_get.
settings="$(dirname "${BASH_SOURCE[0]}")/../../../settings.base.json"
matcher="$(jq -r '
  .hooks.PreToolUse[]
  | select(.hooks[]?.command | tostring | test("read-once.sh"))
  | .matcher
' "$settings")"
if echo "$matcher" | grep -q 'mcp__qmd__multi_get'; then
  echo "  matcher still contains mcp__qmd__multi_get: $matcher" >&2
  exit 1
fi
echo "$matcher" | grep -q 'mcp__qmd__get' \
  || { echo "  matcher should still contain mcp__qmd__get: $matcher" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  10-matcher-no-multiget` because current matcher includes `mcp__qmd__multi_get`.

- [ ] **Step 3: Edit `settings.base.json`**

Find the read-once entry and change its matcher from
`Read|NotebookRead|mcp__qmd__get|mcp__qmd__multi_get|Bash|Grep` to
`Read|NotebookRead|mcp__qmd__get|Bash|Grep`.

Use `jq` to do this safely:

```bash
jq '
  (.hooks.PreToolUse[]
   | select(.hooks[]?.command | tostring | test("read-once.sh"))
   | .matcher) |= sub("\\|mcp__qmd__multi_get";"")
' claude/.claude/settings.base.json > /tmp/settings.base.json.new
mv /tmp/settings.base.json.new claude/.claude/settings.base.json
```

- [ ] **Step 4: Update hook header comment**

In `claude/.claude/hooks/read-once.sh` change the matcher list in lines 2-3 from:

```
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get,
#   mcp__qmd__multi_get, Bash, Grep):
```

to:

```
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get, Bash, Grep):
# mcp__qmd__multi_get is intentionally NOT matched: its input is a glob
# `pattern`, not a path; expansion would exceed the 3s budget, and qmd
# already de-duplicates server-side.
```

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `2 passed, 0 failed`.

- [ ] **Step 6: Run claude-sync to regenerate active settings**

Run: `bash claude/bin/.local/bin/claude-sync || true`
(if claude-skills is not cloned, `claude-sync` copies base as-is — that is fine).

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/settings.base.json \
        claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/10-matcher-no-multiget.sh
git commit -m "fix(read-once): drop mcp__qmd__multi_get from matcher

multi_get input is a glob 'pattern', not a 'path'. The hook's jq
extractor reads file_path/notebook_path/path, gets empty, and fast-exits.
The matcher claimed coverage but the hook did nothing. Drop it and
document the carve-out."
```

---

## Task 3: Remove redundant bypass-log rotation (Spec A.4)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh:68-73`
- Create: `claude/.claude/tests/read-once/cases/11-bypass-log-no-rotation.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/11-bypass-log-no-rotation.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
hook="$(dirname "${BASH_SOURCE[0]}")/../../../hooks/read-once.sh"
if grep -qE 'mv "\$_log_file" "\$\{_log_file\}\.1"' "$hook"; then
  echo "  bypass-log rotation block is still present in hook" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  11-bypass-log-no-rotation`.

- [ ] **Step 3: Delete the rotation block in `read-once.sh`**

Remove lines 68-73:

```bash
    if [[ -f "$_log_file" ]]; then
      _sz=$(stat -c %s "$_log_file" 2>/dev/null || stat -f %z "$_log_file" 2>/dev/null || echo 0)
      if (( _sz > 52428800 )); then
        mv "$_log_file" "${_log_file}.1" 2>/dev/null || true
      fi
    fi
```

Replace with a single comment:

```bash
    # Filename is date-stamped, so rotation happens implicitly per day.
```

- [ ] **Step 4: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/11-bypass-log-no-rotation.sh
git commit -m "fix(read-once): remove redundant bypass-log rotation

The 50MB rollover moved log.log to log.log.1 but never trimmed log.1,
so growth was unbounded on the rolled file. The daily filename
already rotates per day; the size-check block was dead complexity."
```

---

## Task 4: realpath portability + Brewfile check (Spec A.6)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh:180-182` (header comment + fallback)
- Modify: `Brewfile` (verify `coreutils` present)
- Create: `claude/.claude/tests/read-once/cases/12-realpath-fallback.sh`

- [ ] **Step 1: Verify `coreutils` in Brewfile**

Run: `grep -E '^brew "coreutils"' Brewfile`
Expected: at least one match.

If missing, add `brew "coreutils"` in the alphabetical position in the CLI block.

- [ ] **Step 2: Write the failing test**

Create `claude/.claude/tests/read-once/cases/12-realpath-fallback.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# Simulate a missing realpath by overriding PATH; the hook must still allow
# and not crash. We use a temp file to be sure the hook reaches _check_path.
tmpf="$CASE_TMP/foo.txt"; echo "hello" > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
# Empty PATH still has the hook's bash builtins available.
out="$(PATH= printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"
assert_allow "$out"
```

- [ ] **Step 3: Run test to verify it fails or passes**

Run: `bash claude/.claude/tests/read-once/run.sh`
This may already pass (the existing fallback chain handles the absence
of realpath). If it passes, treat steps 4-5 as documentation-only.

- [ ] **Step 4: Update `_check_path` realpath fallback chain**

In `read-once.sh:179-182`, change:

```bash
  local abs
  abs=$(realpath -m "$file_path" 2>/dev/null \
    || grealpath -m "$file_path" 2>/dev/null \
    || echo "$file_path")
```

to:

```bash
  # realpath -m: GNU coreutils. grealpath -m: brew install coreutils on macOS.
  # readlink -f: GNU; final fallback returns the input unchanged (loses
  # symlink resolution but keeps the hook functional).
  local abs
  abs=$(realpath -m "$file_path" 2>/dev/null \
    || grealpath -m "$file_path" 2>/dev/null \
    || readlink -f "$file_path" 2>/dev/null \
    || echo "$file_path")
```

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `4 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/12-realpath-fallback.sh \
        Brewfile
git commit -m "fix(read-once): extend realpath fallback chain

Document the portability matrix (GNU coreutils / brew coreutils /
GNU readlink / passthrough) and add readlink -f as a third fallback.
Verify coreutils is in the Brewfile."
```

---

## Task 5: Accept `env`, `command`, `builtin`, VAR= prefixes (Spec A.5)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh:96` (Bash read-tool regex)
- Create: `claude/.claude/tests/read-once/cases/13-bash-prefixes.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/13-bash-prefixes.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/data.txt"; echo "line1" > "$tmpf"

# First read (cache miss) → allow.
payload="$(stdin_for Bash "" 0 -1 "FOO=bar cat $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_allow "$out"

# Second read with the same prefix → deny (cache hit).
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_deny "$out"

# command cat → also denied (uses same cache entry).
payload2="$(stdin_for Bash "" 0 -1 "command cat $tmpf")"
out="$(printf '%s' "$payload2" | run_hook)"; rc=$?
assert_deny "$out"

# env VAR=val cat → also denied.
payload3="$(stdin_for Bash "" 0 -1 "env FOO=bar cat $tmpf")"
out="$(printf '%s' "$payload3" | run_hook)"; rc=$?
assert_deny "$out"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  13-bash-prefixes` because the regex currently rejects
`FOO=bar`, `command`, and `env` prefixes.

- [ ] **Step 3: Extend the regex**

In `read-once.sh:96`, change:

```bash
  if ! [[ "$COMMAND" =~ ^[[:space:]]*(sudo[[:space:]]+)?(cat|head|tail|bat|view|less|more|sed)[[:space:]] ]]; then
```

to:

```bash
  # Optional leading prefixes:
  #   - one or more "VAR=value " assignments
  #   - "sudo "
  #   - "env [VAR=value ...] "
  #   - "command "
  #   - "builtin "
  # These all delegate to the next token, which we then identify as the
  # actual read-style tool.
  if ! [[ "$COMMAND" =~ ^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*)(sudo[[:space:]]+|env([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+)?(cat|head|tail|bat|view|less|more|sed)[[:space:]] ]]; then
```

The captured tool name is now in `BASH_REMATCH[5]` (was `[2]`). Update:

```bash
  READ_TOOL="${BASH_REMATCH[2]}"
```

to:

```bash
  READ_TOOL="${BASH_REMATCH[5]}"
```

Also update the `_rest` extraction. The current line:

```bash
  _rest="${COMMAND#*"$READ_TOOL"}"
```

is fragile if `$READ_TOOL` (e.g. `cat`) appears inside a `VAR=catsomething` assignment. Replace with a regex-based split:

```bash
  # _rest is everything after the first occurrence of "READ_TOOL ".
  # Anchor with a leading whitespace boundary to avoid matching VAR=cat...
  if [[ "$COMMAND" =~ (^|[[:space:]])"$READ_TOOL"[[:space:]](.*)$ ]]; then
    _rest="${BASH_REMATCH[2]}"
  else
    _rest=""
  fi
```

- [ ] **Step 4: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/13-bash-prefixes.sh
git commit -m "fix(read-once): accept env/command/builtin/VAR= prefixes

Previously 'FOO=bar cat file' and 'command cat file' slipped past the
Bash regex and cached reads were never recorded. The regex now accepts
optional leading variable assignments and the env/command/builtin
delegators. The _rest extraction is also reworked to avoid matching
the tool name inside a VAR= assignment."
```

---

## Task 6: Detect `sed -i` as write, not read (Spec A.2)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh:96-140` (sed branch)
- Create: `claude/.claude/tests/read-once/cases/14-sed-write.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/14-sed-write.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/data.txt"; echo "old" > "$tmpf"

# Pre-seed cache by reading the file via Read.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Now sed -i to edit it. This is a WRITE; must NOT be denied.
payload="$(stdin_for Bash "" 0 -1 "sed -i 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_exit 0 "$rc"; assert_allow "$out"

# BSD form: sed -i '' '...' file
payload="$(stdin_for Bash "" 0 -1 "sed -i '' 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Suffix form: sed -i.bak '...' file
payload="$(stdin_for Bash "" 0 -1 "sed -i.bak 's/old/new/' $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Stdin sed (no positional file): always allow.
payload="$(stdin_for Bash "" 0 -1 "sed 's/x/y/'")"
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
assert_allow "$out"

# Real read: sed 's/x/y/' file → first call allow, second call deny (cache hit).
payload="$(stdin_for Bash "" 0 -1 "sed 's/old/new/' $tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  14-sed-write` because current code treats `sed -i` as a read.

- [ ] **Step 3: Add `sed -i` detection in the Bash branch**

After the `READ_TOOL="${BASH_REMATCH[5]}"` line, add:

```bash
  # sed -i / --in-place / -i SUFFIX / -i '' is a WRITE, not a read.
  if [[ "$READ_TOOL" == "sed" ]]; then
    # Tokenize sed args (everything after "sed ").
    read -ra _sed_tokens <<< "$_rest" || true
    for _t in "${_sed_tokens[@]}"; do
      # Match -i, -iSUFFIX, --in-place, --in-place=SUFFIX
      if [[ "$_t" == "-i" || "$_t" == "--in-place" \
            || "$_t" =~ ^-i.+ || "$_t" =~ ^--in-place= ]]; then
        exit 0
      fi
    done
  fi
```

- [ ] **Step 4: Handle stdin sed (no positional file)**

The existing `[[ "${#FILE_ARGS[@]}" -gt 0 ]] || exit 0` line at end of
the Bash branch already covers this — a sed with no file arg yields an
empty FILE_ARGS and we exit 0. Verify by running the suite.

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `6 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/14-sed-write.sh
git commit -m "fix(read-once): treat sed -i as write, not read

Previously 'sed -i ... file' (GNU) and 'sed -i ''  ... file' (BSD)
were parsed as reads and could be denied when the target file was
already in the cache. Detect -i / --in-place / -iSUFFIX /
--in-place=SUFFIX and exit 0 immediately."
```

---

## Task 7: Header comment refresh — atomicity + range design (Spec A.7, A.8)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh` (header comment block)

- [ ] **Step 1: Replace the header comment block**

The current header (lines 1-39 of `read-once.sh`) describes the hook but
predates the matcher change, sed-i fix, and range-design decision.
Replace it with:

```bash
#!/usr/bin/env bash
# PreToolUse hook (matchers: Read, NotebookRead, mcp__qmd__get, Bash, Grep):
# Block redundant reads when the same file+range is already in this session's
# context. Based on the community "read-once" pattern (Boucle, egorfedorov).
# Extended to catch Bash file-read commands and Grep content-mode on cached files.
#
# Matcher carve-outs:
#   - mcp__qmd__multi_get: input is a glob 'pattern', not a path; expansion
#     would exceed the 3s budget. qmd already de-duplicates server-side.
#   - sed -i / --in-place: detected inside the Bash branch and allowed; it is
#     a write disguised as a Bash command.
#
# Cache (JSONL, append-only, last matching line wins per path):
#   ${XDG_RUNTIME_DIR:-$HOME/.cache}/claude/read-cache-<SESSION_ID>.jsonl
#   {"path":"/abs","mtime":1713200000,"ranges":[[0,-1]],"ts":1713203600,"denies":0}
#
#   Each rc_record line is well under PIPE_BUF (4096 bytes), so POSIX '>>'
#   appends are atomic on every Unix filesystem we care about.
#
#   Ranges are NOT coalesced. Each new (offset, limit) is appended to the
#   ranges array. Coverage is "does any single cached range fully contain the
#   requested range" — adjacent or overlapping but non-containing ranges
#   intentionally do not satisfy a query.
#
# Escape hatches (any true → allow + record fresh entry):
#   - mtime changed on disk (external edit invalidated the cached view)
#   - requested (offset,limit) not covered by any prior range
#   - now - ts >= READ_ONCE_TTL (default 1200s; guards context compaction;
#     TTL=0 disables caching)
#   - READ_ONCE_DISABLE=1 set in the environment
#   - no session_id / file missing / stat failure / corrupt cache
#
# Diff mode (READ_ONCE_DIFF=1 by default; set =0 to disable):
#   On mtime change for a Read call, return only the diff instead of a full
#   re-read. Falls back to full re-read when diff > READ_ONCE_DIFF_MAX (40)
#   lines, the snapshot is missing, the file is binary, or current size is
#   more than 4× snapshot size. Files larger than READ_ONCE_DIFF_MAX_BYTES
#   (262144 = 256KB) are never snapshotted. Snapshots stored under:
#   ${CACHE_DIR}/snapshots-${SESSION_ID}/
#   Bash and Grep bypass paths do not trigger diff mode.
#
# Cache GC:
#   - Opportunistic in-hook prune once per 24h (sentinel: .last-read-once-prune)
#     deletes read-cache-*.jsonl older than READ_ONCE_GC_DAYS (default 7).
#   - SessionEnd hook (read-once-gc.sh) prunes the just-ended session's cache
#     file and snapshot dir if the parent transcript is also gone or older.
#   - READ_ONCE_GC_DISABLE=1 disables both tiers.
#
# Touch-bypass detection:
#   'touch <path>' (or touch -m / -t / -d) on a path read in the last 5s and
#   still cached unchanged is treated as an attempted read-once bypass and
#   denied. A touch on a cold path is allowed. The deny on a subsequent read
#   escalates straight to the rank-3 wording.
#
# Deny wording escalation ladder (counter is per (session, path), stored in
# the JSONL 'denies' field; resets on every rc_record call):
#   0     "in context — use loaded content."
#   1-2   "STILL in context. Stop re-reading."
#   3-5   "DENY #N. Re-reads will keep failing. Change approach."
#   6+    "DENY #N — retry loop. Operator escape: READ_ONCE_DISABLE=1."
#
# Silent exit 0 = allow. JSON permissionDecision="deny" = block the tool call.
# Range semantics match Claude Code's Read tool: offset/limit are line counts;
# limit == -1 means "whole file from offset".
#
# Hot path: fires on every Read, Bash, and Grep. Per-tool fast-exits run before
# sourcing the shared library to minimise overhead on the non-cached common case.
# The Read fast path retains the same 4 jq forks as the original single-tool hook.
set -euo pipefail
```

- [ ] **Step 2: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: All prior tests still pass (header comment change has no
runtime effect).

- [ ] **Step 3: Commit**

```bash
git add claude/.claude/hooks/read-once.sh
git commit -m "docs(read-once): refresh hook header

Document matcher carve-outs (qmd multi_get, sed -i), JSONL atomicity
under PIPE_BUF, intentional non-coalescing of ranges, diff-mode
defaults and size guards, cache GC tiers, touch detection, and the
deny escalation ladder. The forthcoming features will plug into this
contract."
```

---

## Task 8: SessionEnd GC hook (Spec B.2)

**Files:**
- Create: `claude/.claude/hooks/read-once-gc.sh`
- Modify: `claude/.claude/settings.base.json`
- Create: `claude/.claude/tests/read-once/cases/20-gc-sessionend.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/20-gc-sessionend.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
GC_HOOK="$(dirname "${BASH_SOURCE[0]}")/../../../hooks/read-once-gc.sh"
[[ -x "$GC_HOOK" ]] || { echo "  GC hook missing/not exec: $GC_HOOK" >&2; exit 1; }

unset READ_ONCE_GC_DISABLE
cache_dir="$CASE_TMP/claude"
cache_file="$cache_dir/read-cache-$SESSION_ID.jsonl"
snap_dir="$cache_dir/snapshots-$SESSION_ID"
mkdir -p "$snap_dir"
echo '{"path":"/x","mtime":0,"ranges":[[0,-1]],"ts":0,"denies":0}' > "$cache_file"
touch "$snap_dir/dummy"

payload="$(jq -cn --arg sid "$SESSION_ID" '{session_id:$sid}')"
printf '%s' "$payload" | bash "$GC_HOOK"

[[ ! -e "$cache_file" ]] || { echo "  cache file should be gone" >&2; exit 1; }
[[ ! -e "$snap_dir"  ]] || { echo "  snap dir should be gone" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  20-gc-sessionend` because the hook does not exist yet.

- [ ] **Step 3: Write the GC hook**

Create `claude/.claude/hooks/read-once-gc.sh`:

```bash
#!/usr/bin/env bash
# SessionEnd hook: prune the just-ended session's read-once cache file and
# snapshot directory when its parent transcript is missing or older than
# READ_ONCE_GC_DAYS. Also sweeps orphan snapshot dirs.
#
# Operator opt-out: READ_ONCE_GC_DISABLE=1.
set -uo pipefail

[[ "${READ_ONCE_GC_DISABLE:-0}" == "1" ]] && exit 0

SESSION_ID=""
SESSION_ID="$(jq -r '.session_id // ""' 2>/dev/null)" || true
[[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 0

CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude"
GC_DAYS="${READ_ONCE_GC_DAYS:-7}"
CACHE_FILE="$CACHE_DIR/read-cache-$SESSION_ID.jsonl"
SNAP_DIR="$CACHE_DIR/snapshots-$SESSION_ID"

# 1. Drop the just-ended session unless its transcript is still fresh.
transcript_fresh=0
while IFS= read -r tx; do
  if [[ -n "$tx" ]] && \
     find "$tx" -mtime "-$GC_DAYS" -print -quit 2>/dev/null | grep -q .; then
    transcript_fresh=1
    break
  fi
done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "$SESSION_ID.jsonl" 2>/dev/null)

if (( transcript_fresh == 0 )); then
  rm -f -- "$CACHE_FILE"
  rm -rf -- "$SNAP_DIR"
fi

# 2. Orphan snapshot sweep: any snapshots-* dir with no matching cache file.
shopt -s nullglob
for d in "$CACHE_DIR"/snapshots-*; do
  sid="${d##*/snapshots-}"
  [[ -f "$CACHE_DIR/read-cache-$sid.jsonl" ]] || rm -rf -- "$d"
done

exit 0
```

Make it executable:

```bash
chmod +x claude/.claude/hooks/read-once-gc.sh
```

- [ ] **Step 4: Register the hook in `settings.base.json`**

Add to `hooks.SessionEnd` (create the array if absent):

```bash
jq '
  .hooks.SessionEnd =
    (.hooks.SessionEnd // []) +
    [{matcher:"", hooks:[{type:"command",
      command:"bash $HOME/.claude/hooks/read-once-gc.sh",
      timeout:3}]}]
' claude/.claude/settings.base.json > /tmp/sb.json
mv /tmp/sb.json claude/.claude/settings.base.json
```

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `7 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/read-once-gc.sh \
        claude/.claude/settings.base.json \
        claude/.claude/tests/read-once/cases/20-gc-sessionend.sh
git commit -m "feat(read-once): add SessionEnd GC hook

Prunes the just-ended session's read-cache and snapshot dir when its
parent transcript is missing or older than READ_ONCE_GC_DAYS (default
7). Also sweeps orphan snapshot dirs. Disable with
READ_ONCE_GC_DISABLE=1."
```

---

## Task 9: Opportunistic in-hook prune (Spec B.1)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh` (after fast-exits, before lib source)
- Create: `claude/.claude/tests/read-once/cases/21-gc-opportunistic.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/21-gc-opportunistic.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
unset READ_ONCE_GC_DISABLE

cache_dir="$CASE_TMP/claude"
mkdir -p "$cache_dir"
old_session="22222222-2222-2222-2222-222222222222"
old_cache="$cache_dir/read-cache-$old_session.jsonl"
echo '{}' > "$old_cache"
# Backdate 8 days
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null \
            || date -d '8 days ago' +%Y%m%d%H%M)" "$old_cache"

# Trigger the hook with any read; the in-hook prune should fire.
tmpf="$CASE_TMP/foo.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
# Give the backgrounded prune a moment to run.
sleep 1
[[ ! -e "$old_cache" ]] || { echo "  stale cache should be gone" >&2; exit 1; }
[[ -e "$cache_dir/.last-read-once-prune" ]] \
  || { echo "  prune sentinel missing" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  21-gc-opportunistic`.

- [ ] **Step 3: Add the prune block to `read-once.sh`**

Insert immediately after the existing `mkdir -p "$CACHE_DIR"` line (around line 162) and before the library source:

```bash
# Opportunistic prune: once per 24h, delete read-cache-*.jsonl + matching
# snapshot dirs older than READ_ONCE_GC_DAYS. Backgrounded so the hot path
# pays at most a single stat.
if [[ "${READ_ONCE_GC_DISABLE:-0}" != "1" ]]; then
  _sentinel="$CACHE_DIR/.last-read-once-prune"
  _need_prune=1
  if [[ -f "$_sentinel" ]]; then
    _s_mtime=$(stat -c %Y "$_sentinel" 2>/dev/null \
              || stat -f %m "$_sentinel" 2>/dev/null || echo 0)
    if (( NOW - _s_mtime < 86400 )); then _need_prune=0; fi
  fi
  if (( _need_prune )); then
    touch "$_sentinel" 2>/dev/null || true
    {
      _days="${READ_ONCE_GC_DAYS:-7}"
      find "$CACHE_DIR" -maxdepth 1 -name 'read-cache-*.jsonl' -type f \
        -mtime "+$_days" -delete 2>/dev/null || true
      # Orphan snapshot dirs whose matching cache file was just removed
      # (or never existed).
      for _d in "$CACHE_DIR"/snapshots-*; do
        [[ -d "$_d" ]] || continue
        _sid="${_d##*/snapshots-}"
        [[ -f "$CACHE_DIR/read-cache-$_sid.jsonl" ]] || rm -rf -- "$_d"
      done
    } &
    disown
  fi
fi
```

- [ ] **Step 4: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `8 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/21-gc-opportunistic.sh
git commit -m "feat(read-once): opportunistic in-hook prune

Backgrounded find once per 24h deletes read-cache-*.jsonl older than
READ_ONCE_GC_DAYS (default 7) plus any orphan snapshot dirs. Sentinel
file gates the work so the hot path costs at most one stat call."
```

---

## Task 10: Snapshot on every first read + size cap (Spec A.3, D.2, D.3, D.4)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh:200-244` (snapshot + diff logic)
- Create: `claude/.claude/tests/read-once/cases/30-snapshot-any-range.sh`
- Create: `claude/.claude/tests/read-once/cases/31-snapshot-size-cap.sh`
- Create: `claude/.claude/tests/read-once/cases/32-snapshot-dir-cap.sh`
- Create: `claude/.claude/tests/read-once/cases/33-diff-fallback.sh`

- [ ] **Step 1: Write the failing tests**

Create `cases/30-snapshot-any-range.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\nd\ne\n' > "$tmpf"
# First read is partial (offset=1, limit=2).
payload="$(stdin_for Read "$tmpf" 1 2)"
printf '%s' "$payload" | run_hook >/dev/null
# Snapshot must exist despite the partial first read.
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
[[ -d "$snap_dir" && -n "$(ls -A "$snap_dir")" ]] \
  || { echo "  snapshot not stored on partial first read" >&2; exit 1; }
```

Create `cases/31-snapshot-size-cap.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
export READ_ONCE_DIFF_MAX_BYTES=64
tmpf="$CASE_TMP/big.txt"
head -c 1024 /dev/urandom | base64 > "$tmpf"   # > 1KB > 64
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
# Snapshot should NOT exist for an oversize file.
if [[ -d "$snap_dir" ]] && [[ -n "$(ls -A "$snap_dir" 2>/dev/null)" ]]; then
  echo "  oversize file was snapshotted" >&2; exit 1
fi
```

Create `cases/32-snapshot-dir-cap.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
# Read 55 distinct files; snapshot dir should never exceed 50 entries.
for i in $(seq 1 55); do
  f="$CASE_TMP/f-$i.txt"
  echo "$i" > "$f"
  payload="$(stdin_for Read "$f")"
  printf '%s' "$payload" | run_hook >/dev/null
done
snap_dir="$CASE_TMP/claude/snapshots-$SESSION_ID"
n=$(ls "$snap_dir" 2>/dev/null | wc -l | tr -d ' ')
(( n <= 50 )) || { echo "  snapshot dir has $n entries (>50)" >&2; exit 1; }
```

Create `cases/33-diff-fallback.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
export READ_ONCE_DIFF=1
export READ_ONCE_DIFF_MAX=4
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\n' > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null   # cache + snapshot

# Replace contents entirely (big diff >4 lines).
printf 'X\nY\nZ\nW\nV\nU\n' > "$tmpf"
sleep 1   # ensure mtime change
out="$(printf '%s' "$payload" | run_hook)"; rc=$?
# Big diff → fallback to allow.
assert_exit 0 "$rc"; assert_allow "$out"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: four new cases fail.

- [ ] **Step 3: Rewrite the snapshot block**

Replace lines 200-211 (the first-read snapshot block) with:

```bash
  # First time seeing this path in this session.
  if [[ "$status" != "HIT" ]]; then
    rc_record "$abs" "$current_mtime" "[[${offset}, ${limit}]]"
    if [[ "${READ_ONCE_DIFF:-1}" == "1" ]]; then
      _max_bytes="${READ_ONCE_DIFF_MAX_BYTES:-262144}"
      if (( size <= _max_bytes )); then
        local snap_dir="${CACHE_DIR}/snapshots-${SESSION_ID}"
        mkdir -p "$snap_dir" 2>/dev/null || true
        local slug
        slug=$(rc_path_slug "$abs") || true
        if [[ -n "$slug" ]]; then
          cp -- "$abs" "${snap_dir}/${slug}" 2>/dev/null || true
          # Cap snapshot dir at 50 files; evict oldest by mtime.
          local _count
          _count=$(ls -1 "$snap_dir" 2>/dev/null | wc -l)
          if (( _count > 50 )); then
            ls -1t "$snap_dir" 2>/dev/null | tail -n +51 | \
              while IFS= read -r _f; do rm -f -- "$snap_dir/$_f"; done
          fi
        fi
      fi
    fi
    return 0
  fi
```

- [ ] **Step 4: Tighten the mtime-change diff path**

In the existing block (around lines 214-244) replace the diff fallback
condition with the four-rule check from Spec D.4. Replace:

```bash
        if [[ -n "$diff_out" && "$diff_lines" -le "$max_lines" ]]; then
```

with:

```bash
        # Fallback rules: missing diff, oversize diff, binary marker, or
        # current size > 4× snap size.
        local _snap_size _bin_marker=0
        _snap_size=$(stat -c %s "$snap" 2>/dev/null \
                     || stat -f %z "$snap" 2>/dev/null || echo 0)
        if [[ "$diff_out" == "Binary files"* ]]; then _bin_marker=1; fi
        if [[ -n "$diff_out" && "$diff_lines" -le "$max_lines" \
              && "$_bin_marker" -eq 0 \
              && "$size" -le $((_snap_size * 4)) ]]; then
```

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `12 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/30-snapshot-any-range.sh \
        claude/.claude/tests/read-once/cases/31-snapshot-size-cap.sh \
        claude/.claude/tests/read-once/cases/32-snapshot-dir-cap.sh \
        claude/.claude/tests/read-once/cases/33-diff-fallback.sh
git commit -m "fix(read-once): snapshot on every first read + size/dir caps

Previously snapshots were stored only when the first read was
offset=0 limit=-1, silently losing diff capability for any partial
first read. Snapshot unconditionally on first cache miss, subject
to READ_ONCE_DIFF_MAX_BYTES (default 256KB) and a 50-file snapshot
dir cap. Add binary-file and size-ratio fallback rules to the diff
path."
```

---

## Task 11: Diff mode default-on + token estimate (Spec D.1, D.5, D.6)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh` (default value + reason string)
- Create: `claude/.claude/tests/read-once/cases/34-diff-default-on.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/34-diff-default-on.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
# helpers.sh sets READ_ONCE_DIFF=0 explicitly; clear it to test the default.
unset READ_ONCE_DIFF
tmpf="$CASE_TMP/f.txt"
printf 'a\nb\nc\n' > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Small edit; diff mode should produce a diff-flavoured deny.
echo "d" >> "$tmpf"
sleep 1
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "Diff"

# Reason should mention ~tokens.
echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
  | grep -qE '~[0-9]+ tokens' \
  || { echo "  diff reason missing token estimate" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  34-diff-default-on`.

- [ ] **Step 3: Flip default**

Find every occurrence of `"${READ_ONCE_DIFF:-0}"` in `read-once.sh`
and change to `"${READ_ONCE_DIFF:-1}"`. Use:

```bash
sed -i.bak 's/\${READ_ONCE_DIFF:-0}/${READ_ONCE_DIFF:-1}/g' \
  claude/.claude/hooks/read-once.sh
rm claude/.claude/hooks/read-once.sh.bak
```

- [ ] **Step 4: Add token estimate to diff reason**

Find the existing diff `reason=` block and replace:

```bash
          local reason="read-once: ${abs} changed since last read (~${tokens} tokens). Diff (${diff_lines} lines) below — apply this instead of re-reading.
${diff_out}"
```

with:

```bash
          local _diff_tokens=$(( ${#diff_out} / 4 ))
          local reason="read-once: ${abs} changed since last read (file ~${tokens} tokens, diff ~${_diff_tokens} tokens, ${diff_lines} lines). Apply this diff instead of re-reading.
${diff_out}"
```

- [ ] **Step 5: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `13 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/34-diff-default-on.sh
git commit -m "feat(read-once): default diff mode on, surface diff token estimate

Telemetry shows zero opt-ins to READ_ONCE_DIFF=1 across 30+ days of
cache history; the feature was effectively dead. Default it on and
include a diff-side token estimate next to the file-side estimate in
the deny reason so the agent can see the savings."
```

---

## Task 12: denies counter schema (Spec C.1)

**Files:**
- Modify: `claude/.claude/lib/read-once-cache.sh` (`rc_record`, `rc_lookup`)
- Modify: `claude/.claude/hooks/read-once.sh` (`_check_path` carries `denies`)
- Create: `claude/.claude/tests/read-once/cases/40-denies-counter.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/40-denies-counter.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null    # cache miss
printf '%s' "$payload" | run_hook >/dev/null    # 1st deny
printf '%s' "$payload" | run_hook >/dev/null    # 2nd deny

cache="$CASE_TMP/claude/read-cache-$SESSION_ID.jsonl"
last_denies=$(jq -r 'select(.path|test("f.txt$"))|.denies // 0' "$cache" | tail -1)
(( last_denies == 2 )) || { echo "  expected denies=2, got $last_denies" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  40-denies-counter`.

- [ ] **Step 3: Extend `rc_record` to accept and write `denies`**

In `lib/read-once-cache.sh` replace `rc_record`:

```bash
rc_record() {
  local abs="$1" mtime="$2" ranges="$3" denies="${4:-0}"
  jq -cn \
    --arg path "$abs" \
    --argjson mtime "$mtime" \
    --argjson ranges "$ranges" \
    --argjson ts "$NOW" \
    --argjson denies "$denies" \
    '{path:$path,mtime:$mtime,ranges:$ranges,ts:$ts,denies:$denies}' \
    >> "$CACHE" 2>/dev/null || true
}
```

- [ ] **Step 4: Extend `rc_lookup` to surface `denies`**

Replace the jq filter in `rc_lookup` to also output the prior denies
count. Change the HIT branch from:

```bash
      "HIT\t\($prior.mtime)\t\($prior.ts)\t\($cov)\t\($prior.ranges + [[$o2, $l2]] | tojson)"
```

to:

```bash
      "HIT\t\($prior.mtime)\t\($prior.ts)\t\($cov)\t\($prior.ranges + [[$o2, $l2]] | tojson)\t\($prior.denies // 0)"
```

Update the consumer in `_check_path` to read the extra column. Replace:

```bash
  local status p_mtime p_ts covered extended
  status=NEW p_mtime=0 p_ts=0 covered=false extended="[[${offset}, ${limit}]]"
  IFS=$'\t' read -r status p_mtime p_ts covered extended < <(
    rc_lookup "$abs" "$offset" "$limit"
  ) || true
```

with:

```bash
  local status p_mtime p_ts covered extended p_denies
  status=NEW p_mtime=0 p_ts=0 covered=false extended="[[${offset}, ${limit}]]" p_denies=0
  IFS=$'\t' read -r status p_mtime p_ts covered extended p_denies < <(
    rc_lookup "$abs" "$offset" "$limit"
  ) || true
```

- [ ] **Step 5: Wire the counter into the deny path**

Just before calling `rc_deny` at the end of `_check_path`, add:

```bash
  # Increment denies counter for the next iteration.
  local _next_denies=$(( p_denies + 1 ))
  rc_record "$abs" "$current_mtime" \
    "$(jq -cn --argjson r "$(printf '%s' "$extended")" 'def fix(x): if x|type=="string" then x|fromjson else x end; fix($r)')" \
    "$_next_denies"
```

(That jq call re-parses the extended ranges if it arrived as a string;
no-op otherwise.)

Update `rc_deny` to accept and surface `denies`:

In `lib/read-once-cache.sh`, change `rc_deny`'s signature from `abs age size`
to `abs age size denies`:

```bash
rc_deny() {
  local abs="$1" age="$2" size="$3" denies="${4:-0}"
  local tokens=$(( size / 4 ))
  local reason="read-once: ${abs} already in context (deny #$((denies + 1)), read ${age}s ago, unchanged, ~${tokens} tokens). Use the content already loaded earlier in this conversation. To invalidate: edit the file, or request a different offset/limit."
  jq -cn --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}
```

And update the caller in `_check_path`:

```bash
  rc_deny "$abs" "$age" "$size" "$p_denies"
```

- [ ] **Step 6: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `14 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/lib/read-once-cache.sh \
        claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/40-denies-counter.sh
git commit -m "feat(read-once): track per-session deny counter

JSONL schema bump: each record carries a 'denies' field that
increments on each deny and resets on cache miss / mtime change /
range extension / TTL expiry. rc_lookup surfaces the prior count to
the caller; rc_deny mentions it in the wording."
```

---

## Task 13: Escalation ladder (Spec C.2)

**Files:**
- Modify: `claude/.claude/lib/read-once-cache.sh` (`rc_deny`)
- Create: `claude/.claude/tests/read-once/cases/41-escalation-ladder.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/41-escalation-ladder.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null   # miss

# Deny #1 → rank 0 wording (no "STILL", no "DENY #").
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "in context"
echo "$out" | jq -re '.hookSpecificOutput.permissionDecisionReason' \
  | grep -qE 'STILL|DENY #' \
  && { echo "  rank 0 should not contain escalation keywords" >&2; exit 1; }

# Deny #2 (rank 1) → contains "STILL".
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "STILL"

# Denies 3, 4 (rank 1 still).
printf '%s' "$payload" | run_hook >/dev/null
out="$(printf '%s' "$payload" | run_hook)"   # deny #4 → rank 3 (3-5 band)
assert_deny_contains "$out" "DENY #"

# Push to rank 6+.
for _ in 5 6 7; do printf '%s' "$payload" | run_hook >/dev/null; done
out="$(printf '%s' "$payload" | run_hook)"
assert_deny_contains "$out" "READ_ONCE_DISABLE=1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  41-escalation-ladder`.

- [ ] **Step 3: Replace `rc_deny` with the ladder**

```bash
rc_deny() {
  local abs="$1" age="$2" size="$3" denies="${4:-0}"
  local tokens=$(( size / 4 ))
  local n=$((denies + 1))   # deny number this call represents
  local reason
  if   (( denies == 0 )); then
    reason="read-once: ${abs} in context (read ${age}s ago, unchanged, ~${tokens} tokens). Use loaded content. To invalidate: edit file or request different offset/limit."
  elif (( denies <= 2 )); then
    reason="read-once: ${abs} STILL in context (deny #${n}, read ${age}s ago). Stop re-reading. Use content already loaded OR change approach."
  elif (( denies <= 5 )); then
    reason="read-once: ${abs} DENY #${n}. File unchanged since first read. Re-reads will keep failing. Use content from context OR change task plan."
  else
    reason="read-once: ${abs} DENY #${n} — retry loop. Operator escape: set READ_ONCE_DISABLE=1 in env. Otherwise abandon this approach."
  fi
  jq -cn --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}
```

- [ ] **Step 4: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/lib/read-once-cache.sh \
        claude/.claude/tests/read-once/cases/41-escalation-ladder.sh
git commit -m "feat(read-once): escalating deny wording

Wording climbs through four ranks as the deny counter grows:
'in context' → 'STILL in context' → 'DENY #N' → 'retry loop'.
The READ_ONCE_DISABLE operator escape is mentioned only at rank 6+
to avoid training the agent to bypass on the first deny."
```

---

## Task 14: Touch-event sidecar (Spec C.3 part 1)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh` (Bash branch: detect `touch`)
- Create: `claude/.claude/tests/read-once/cases/50-touch-sidecar.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/read-once/cases/50-touch-sidecar.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

payload="$(stdin_for Bash "" 0 -1 "touch $tmpf")"
out="$(printf '%s' "$payload" | run_hook)"
# Cold touch → allow (no cached read on this path yet).
assert_allow "$out"

sidecar="$CASE_TMP/claude/touch-events-$SESSION_ID.jsonl"
[[ -f "$sidecar" ]] || { echo "  touch sidecar missing" >&2; exit 1; }
grep -q "$tmpf" "$sidecar" || { echo "  path not recorded in sidecar" >&2; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `FAIL  50-touch-sidecar`.

- [ ] **Step 3: Add touch detection in the Bash branch**

Immediately after the existing Bash regex match (after `_rest` is set
and before the loop that fills `FILE_ARGS`), add a `touch` branch.
Insert at the top of the Bash branch (right after the early-exit guard
ensures `$COMMAND` matches the read-tool regex). Replace that early-exit
with a two-stage match:

Find:

```bash
  if ! [[ "$COMMAND" =~ ^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*)(sudo[[:space:]]+|env([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+)?(cat|head|tail|bat|view|less|more|sed)[[:space:]] ]]; then
    exit 0
  fi
  READ_TOOL="${BASH_REMATCH[5]}"
```

Replace with:

```bash
  _touch_re='^[[:space:]]*(sudo[[:space:]]+)?touch([[:space:]]|$)'
  if [[ "$COMMAND" =~ $_touch_re ]]; then
    # Parse touch args: skip flags and their values for -t / -d / -r.
    _t_rest="${COMMAND#*touch}"
    read -ra _t_tokens <<< "$_t_rest" || true
    _t_skip=0
    declare -a _touched_paths=()
    for _t in "${_t_tokens[@]}"; do
      if (( _t_skip )); then _t_skip=0; continue; fi
      [[ "$_t" == "--" ]] && continue
      if [[ "$_t" =~ ^-[tdr]$ ]]; then _t_skip=1; continue; fi
      [[ "$_t" =~ ^- ]] && continue
      _t="${_t#[\'\"]}"; _t="${_t%[\'\"]}"
      [[ -n "$_t" ]] && _touched_paths+=("$_t")
    done

    if (( ${#_touched_paths[@]} > 0 )); then
      CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude"
      mkdir -p "$CACHE_DIR" 2>/dev/null || true
      _sidecar="${CACHE_DIR}/touch-events-${SESSION_ID}.jsonl"
      _ts="${EPOCHSECONDS:-$(date +%s)}"
      for _p in "${_touched_paths[@]}"; do
        # Resolve to absolute path (best effort).
        _abs=$(realpath -m "$_p" 2>/dev/null \
              || grealpath -m "$_p" 2>/dev/null || echo "$_p")
        jq -cn --arg path "$_abs" --argjson ts "$_ts" \
          '{path:$path,ts:$ts,event:"touch_invalidate"}' \
          >> "$_sidecar" 2>/dev/null || true
      done
      # Cap sidecar at 100 entries.
      if [[ -f "$_sidecar" ]]; then
        _lines=$(wc -l < "$_sidecar" 2>/dev/null || echo 0)
        if (( _lines > 100 )); then
          tail -n 100 "$_sidecar" > "${_sidecar}.tmp" \
            && mv "${_sidecar}.tmp" "$_sidecar"
        fi
      fi
    fi
    # Bypass-deny check is in Task 15; for now allow the touch.
    exit 0
  fi

  if ! [[ "$COMMAND" =~ ^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*)(sudo[[:space:]]+|env([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+)?(cat|head|tail|bat|view|less|more|sed)[[:space:]] ]]; then
    exit 0
  fi
  READ_TOOL="${BASH_REMATCH[5]}"
```

- [ ] **Step 4: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/tests/read-once/cases/50-touch-sidecar.sh
git commit -m "feat(read-once): record touch events in per-session sidecar

Bash branch now recognises 'touch [-t|-d|-r SUFFIX] <path>...' and
writes an entry per touched path to touch-events-<SID>.jsonl in
the cache dir. Sidecar is capped at 100 lines via tail-rewrite.
A cold touch is allowed; bypass-detection on hot touches lands
in the next change."
```

---

## Task 15: Touch-bypass blocking + escalation on subsequent read (Spec C.3 part 2, C.4)

**Files:**
- Modify: `claude/.claude/hooks/read-once.sh` (touch branch + `_check_path` deny path)
- Modify: `claude/.claude/lib/read-once-cache.sh` (new helper `rc_recent_touch`)
- Create: `claude/.claude/tests/read-once/cases/51-touch-bypass-block.sh`
- Create: `claude/.claude/tests/read-once/cases/52-touch-escalate-read.sh`

- [ ] **Step 1: Write the failing tests**

Create `cases/51-touch-bypass-block.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

# Read first to seed the cache.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Immediate touch on the same path → DENY.
t_payload="$(stdin_for Bash "" 0 -1 "touch $tmpf")"
out="$(printf '%s' "$t_payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "touch on recently-read file"
```

Create `cases/52-touch-escalate-read.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers.sh"
tmpf="$CASE_TMP/f.txt"; echo hi > "$tmpf"

# Seed cache.
payload="$(stdin_for Read "$tmpf")"
printf '%s' "$payload" | run_hook >/dev/null

# Pretend a touch happened (skip block by writing the sidecar directly).
sidecar="$CASE_TMP/claude/touch-events-$SESSION_ID.jsonl"
mkdir -p "$(dirname "$sidecar")"
abs="$tmpf"
jq -cn --arg p "$abs" --argjson ts "$(date +%s)" \
  '{path:$p,ts:$ts,event:"touch_invalidate"}' >> "$sidecar"

# Next read deny must escalate to rank 3 wording.
out="$(printf '%s' "$payload" | run_hook)"
assert_deny "$out"
assert_deny_contains "$out" "Touch invalidation detected"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: two new cases fail.

- [ ] **Step 3: Add `rc_recent_touch` helper**

Append to `claude/.claude/lib/read-once-cache.sh`:

```bash
# rc_recent_touch ABS [WINDOW_SECONDS]
# Returns 0 (and prints the touch ts) if abs was touched within WINDOW seconds
# of NOW; returns 1 otherwise. Default window: 30s.
rc_recent_touch() {
  local abs="$1" window="${2:-30}"
  local sidecar="${CACHE_DIR}/touch-events-${SESSION_ID}.jsonl"
  [[ -f "$sidecar" ]] || return 1
  local ts
  ts=$(jq -r --arg p "$abs" --argjson now "$NOW" --argjson w "$window" '
    [.[]? // empty
     | select(.path == $p and (.ts // 0) >= ($now - $w))
     | .ts] | last // empty
  ' "$sidecar" 2>/dev/null)
  [[ -n "$ts" ]] || return 1
  printf '%s\n' "$ts"
  return 0
}
```

- [ ] **Step 4: Block touch on recently-read paths**

Inside the touch branch (Task 14), replace `# Bypass-deny check is in
Task 15; for now allow the touch.` and the subsequent `exit 0` with:

```bash
    # Bypass detection: if any touched path was read in the last 5s and
    # still cached with unchanged mtime, deny the touch.
    CACHE="${CACHE_DIR}/read-cache-${SESSION_ID}.jsonl"
    if [[ -f "$CACHE" ]]; then
      _now="${EPOCHSECONDS:-$(date +%s)}"
      for _p in "${_touched_paths[@]}"; do
        _abs=$(realpath -m "$_p" 2>/dev/null \
              || grealpath -m "$_p" 2>/dev/null || echo "$_p")
        _row=$(jq -rs --arg p "$_abs" '
          [.[] | select(.path == $p)] | last
          | if . == null then "" else "\(.mtime) \(.ts)" end
        ' "$CACHE" 2>/dev/null) || _row=""
        [[ -n "$_row" ]] || continue
        _cached_mtime="${_row% *}"; _cached_ts="${_row#* }"
        # File mtime as it is right now (touch has not run yet).
        _disk_mtime=$(stat -c %Y "$_p" 2>/dev/null \
                     || stat -f %m "$_p" 2>/dev/null || echo 0)
        if [[ "$_cached_mtime" == "$_disk_mtime" ]] \
           && (( _now - _cached_ts <= 5 )); then
          reason="read-once: ${_abs} DENY — touch on recently-read file looks like a read-once bypass. To force re-read: edit content, or set READ_ONCE_DISABLE=1."
          jq -cn --arg r "$reason" '{
            hookSpecificOutput:{
              hookEventName:"PreToolUse",
              permissionDecision:"deny",
              permissionDecisionReason:$r
            }
          }'
          exit 0
        fi
      done
    fi
    exit 0
```

- [ ] **Step 5: Escalate read deny when a recent touch was logged**

In `_check_path`, just before the `rc_deny` call, source touch info and
override the wording when present. Replace:

```bash
  rc_deny "$abs" "$age" "$size" "$p_denies"
```

with:

```bash
  if _touch_ts=$(rc_recent_touch "$abs"); then
    local _touch_age=$(( NOW - _touch_ts ))
    local reason="read-once: ${abs} DENY — touch invalidation detected (touched ${_touch_age}s ago, no real edit). Use content from context OR make real edits. Touch invalidation detected at ${_touch_ts}."
    jq -cn --arg r "$reason" '{
      hookSpecificOutput:{
        hookEventName:"PreToolUse",
        permissionDecision:"deny",
        permissionDecisionReason:$r
      }
    }'
  else
    rc_deny "$abs" "$age" "$size" "$p_denies"
  fi
```

- [ ] **Step 6: Run tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: `18 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add claude/.claude/hooks/read-once.sh \
        claude/.claude/lib/read-once-cache.sh \
        claude/.claude/tests/read-once/cases/51-touch-bypass-block.sh \
        claude/.claude/tests/read-once/cases/52-touch-escalate-read.sh
git commit -m "feat(read-once): touch-bypass detection

Two-pronged enforcement:
  - 'touch <path>' is denied when the path was read in the last 5s
    and the cached mtime still matches disk; the workaround breaks
    before the file's mtime is bumped.
  - A read deny that follows a recent touch (within 30s) skips the
    normal ladder and emits dedicated 'touch invalidation detected'
    wording so the agent sees the signal."
```

---

## Task 16: Operator guide doc (Spec F.2)

**Files:**
- Create: `claude/.claude/docs/read-once.md`

- [ ] **Step 1: Write the doc**

Create `claude/.claude/docs/read-once.md`:

```markdown
# Read-once hook

Blocks redundant file reads within a single Claude Code session. Implemented as a `PreToolUse` hook on `Read`, `NotebookRead`, `mcp__qmd__get`, `Bash`, and `Grep`.

Source:
- `claude/.claude/hooks/read-once.sh` — the hook
- `claude/.claude/lib/read-once-cache.sh` — shared helpers
- `claude/.claude/hooks/read-once-gc.sh` — `SessionEnd` GC

Cache: `${XDG_RUNTIME_DIR:-$HOME/.cache}/claude/read-cache-<SID>.jsonl`. Snapshots: `${CACHE_DIR}/snapshots-<SID>/`. Touch events: `${CACHE_DIR}/touch-events-<SID>.jsonl`. Bypass log: `~/.claude/logs/read-once-bypass-YYYY-MM-DD.log`.

## Environment variables

| Var | Default | Effect |
|---|---|---|
| `READ_ONCE_TTL` | 1200 | Seconds before a cached entry expires |
| `READ_ONCE_DISABLE` | unset | `1` allows all reads, logs each bypass |
| `READ_ONCE_DIFF` | 1 | Set `0` to disable diff mode on mtime change |
| `READ_ONCE_DIFF_MAX` | 40 | Max diff lines before falling back to full re-read |
| `READ_ONCE_DIFF_MAX_BYTES` | 262144 | Skip snapshot for files larger than this |
| `READ_ONCE_GC_DAYS` | 7 | Retention for cache + snapshot files |
| `READ_ONCE_GC_DISABLE` | unset | `1` disables both GC tiers |

## How to bypass

If a deny is wrong: `READ_ONCE_DISABLE=1` in the environment. Every bypass is logged to `~/.claude/logs/read-once-bypass-YYYY-MM-DD.log` with session id, tool, command, cwd.

If the cache itself looks broken: `rm ~/.cache/claude/read-cache-<SID>.jsonl` for the current session (find the SID in the deny message path).

## Common false positives

- **File regenerated by a tool with the same mtime** — rare; `touch` won't help (blocked by bypass detection). Edit the file or use `READ_ONCE_DISABLE=1`.
- **Reading a slightly different range** — the cache treats non-containing ranges as misses, so this should not happen; if it does, raise an issue.
- **Symlinks across stow** — the hook resolves to canonical paths via `realpath -m`. If `coreutils` is missing on macOS the hook degrades gracefully but the symlinked and canonical paths are then cached separately.

## Why touch is denied

The hook tracks touched paths. If a touched path was read within the last 5 seconds and its on-disk mtime still matches the cache, the touch is treated as an attempted bypass and denied. This is intentional: touching a file just to invalidate the read cache is a workaround that masks the agent's real options (use the content already loaded, or change approach).

## Deny escalation

The deny wording escalates as the count grows in a single session for the same path:

| Denies | Wording |
|---|---|
| 1 | "in context — use loaded content" |
| 2-3 | "STILL in context — stop re-reading" |
| 4-6 | "DENY #N — re-reads will keep failing" |
| 7+ | "DENY #N — retry loop. Operator escape: `READ_ONCE_DISABLE=1`" |

Counter resets on cache miss, mtime change, range extension, or TTL expiry.

## Tests

`bash claude/.claude/tests/read-once/run.sh` runs the full shell test suite. Each case sets up its own temp cache dir and isolated session id.
```

- [ ] **Step 2: Commit**

```bash
git add claude/.claude/docs/read-once.md
git commit -m "docs(read-once): operator guide

Env var reference, bypass instructions, cache layout, false positive
guide, touch-detection rationale, escalation ladder summary, and test
suite entrypoint."
```

---

## Task 17: Final smoke pass

**Files:** (no edits; verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: All cases pass.

- [ ] **Step 2: Sanity-check the hook against a live read**

Run from inside the worktree:

```bash
echo '{"session_id":"99999999-9999-9999-9999-999999999999","tool_name":"Read","tool_input":{"file_path":"claude/.claude/hooks/read-once.sh"}}' \
  | bash claude/.claude/hooks/read-once.sh
echo $?
```

Expected: silent allow on first call (exit 0, no JSON). Repeat the same
command; the second invocation must print the deny JSON and exit 0.

- [ ] **Step 3: Run `claude-sync` to regenerate active settings**

Run: `bash claude/bin/.local/bin/claude-sync || true`

- [ ] **Step 4: Verify the active settings match base**

Run:

```bash
diff <(jq -S '.hooks' ~/.claude/settings.json) \
     <(jq -S '.hooks' claude/.claude/settings.base.json)
```

Expected: no output when the user has no overlay; otherwise diff is
limited to overlay-provided keys.

- [ ] **Step 5: No commit needed** — this task is verification only.

---

## Self-review

**Spec coverage check (against `2026-05-19-read-once-hardening-design.md`):**

- A.1 (drop multi_get) — Task 2.
- A.2 (`sed -i`) — Task 6.
- A.3 (snapshot any range) — Task 10.
- A.4 (bypass log rotation) — Task 3.
- A.5 (Bash prefixes) — Task 5.
- A.6 (realpath) — Task 4.
- A.7 (atomicity doc) — Task 7.
- A.8 (range design doc) — Task 7.
- B.1 (opportunistic prune) — Task 9.
- B.2 (SessionEnd GC) — Task 8.
- C.1 (denies field) — Task 12.
- C.2 (escalation ladder) — Task 13.
- C.3 (touch detection + override) — Tasks 14, 15.
- C.4 (counter reset) — implicit in Task 12 (every `rc_record` writes `denies=0`).
- D.1 (diff default on) — Task 11.
- D.2 (snapshot semantics) — Task 10.
- D.3 (snapshot dir cap) — Task 10.
- D.4 (diff fallback rules) — Task 10.
- D.5 (token estimate) — Task 11.
- D.6 (env table) — Task 16.
- E.1–E.3 (test suite) — Tasks 1, 2–15.
- E.4 (claude-sync `--test` flag) — deferred; not required for the
  spec's goals. The runner is invokable directly. Add `claude-sync
  --test` in a follow-up if desired.
- F.1 (header comment) — Task 7.
- F.2 (operator guide) — Task 16.

All non-deferred spec requirements have at least one task. Task 17 is
the final smoke pass.

**Type / signature consistency:** `rc_record(abs, mtime, ranges,
denies?)`, `rc_lookup(abs, offset, limit) -> status\tmtime\tts\tcovered\textended\tdenies`,
`rc_deny(abs, age, size, denies?)`, `rc_recent_touch(abs, window?) -> ts`,
`rc_path_slug(abs) -> slug`. Consistent across all tasks.

**Placeholder scan:** no TBD, no "implement later", every test has full
test code, every implementation step has full code or a precise edit
target. The single "deferred" item (E.4) is explicitly named and out of
scope.
