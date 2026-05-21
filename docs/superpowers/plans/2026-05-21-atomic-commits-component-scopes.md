# Atomic commits + component scopes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a signal-driven commit-scope validator (no framework-name lists) that nudges agents away from artifact-type / repo-name scopes via the existing `git-safety.sh` PreToolUse hook, plus a rewritten CLAUDE.md rule that teaches the principle without literal scope examples.

**Architecture:** New `claude/.claude/lib/commit-scope.sh` exposes `is_banned_scope` + `suggest_scope` driven by four signals computed against the current repo's filesystem + `git log`. The existing `git-safety.sh` hook sources the lib at commit-time and emits non-blocking warnings via `emit_context`. CLAUDE.md describes the rule in repo-agnostic placeholders.

**Tech Stack:** Bash 4+, jq, awk, sed, git. No external deps beyond what `git-safety.sh` already uses.

**Spec:** `docs/superpowers/specs/2026-05-21-atomic-commits-component-scopes-design.md`

---

## File map

| Path | Role |
|------|------|
| `claude/.claude/lib/commit-scope.sh` | NEW. Public API + signal logic + private helpers. ~150 lines. |
| `claude/.claude/hooks/git-safety.sh` | MODIFIED. Sources lib, adds banned-scope check after `commit -a` guard, extends staged-context emit. |
| `claude/.claude/CLAUDE.md` | MODIFIED. Replaces `### Commit rules` block under "Git Workflow" with the new four-subsection content. |
| `claude/.claude/tests/commit-scope/run.sh` | NEW. Iterates cases. Mirrors `tests/read-once/run.sh`. |
| `claude/.claude/tests/commit-scope/helpers.sh` | NEW. Lib-unit + hook-integration helpers. |
| `claude/.claude/tests/commit-scope/cases/*.sh` | NEW. 27 case files: 13 lib-unit + 10 hook-integration + smokes + sentinel. |

## Commit boundaries

Three atomic commits, dogfooding the rule:

1. `feat(claude): add signal-driven commit-scope lib` — lib + lib-unit tests (Tasks 1-9).
2. `feat(claude): wire commit-scope checks into git-safety hook` — hook ext + hook-integration tests (Tasks 10-18).
3. `docs(claude): document commit-scope rules in CLAUDE.md` — CLAUDE.md replacement (Tasks 19-20).

---

## Phase 1 — Lib + lib-unit tests (commit 1)

### Task 1: Test scaffold + lib skeleton + smoke test

**Files:**
- Create: `claude/.claude/lib/commit-scope.sh`
- Create: `claude/.claude/tests/commit-scope/run.sh`
- Create: `claude/.claude/tests/commit-scope/helpers.sh`
- Create: `claude/.claude/tests/commit-scope/cases/00-smoke-lib-sources.sh`

- [ ] **Step 1: Write lib skeleton**

```bash
cat > claude/.claude/lib/commit-scope.sh <<'EOF'
#!/usr/bin/env bash
# Signal-driven commit-scope validation. Repo-agnostic.
#
# Four signals (computed against the current repo's filesystem + git log):
#   S1 universal filesystem container name (with history escape)
#   S2 repo basename (no history escape)
#   S3 staged-path segment match (with history escape, +s plural inflection)
#   S4 new-scope soft advisory (emitted by the hook, not by this lib)
#
# Pure POSIX-bash. No external state. Safe to source repeatedly.

# S1: filesystem-convention container names. Stable across codebases for decades.
# These are container directory names, NOT framework names. Do not add 'spec',
# 'plan', 'openspec', etc. here -- those get caught by S3 (path-segment match).
CONTAINER_NAMES=(
  docs doc src lib bin scripts script
  tests test assets static public
  vendor build dist target
  packages apps
)
EOF
chmod +x claude/.claude/lib/commit-scope.sh
```

- [ ] **Step 2: Write test runner**

```bash
cat > claude/.claude/tests/commit-scope/run.sh <<'EOF'
#!/usr/bin/env bash
# Commit-scope lib + hook test runner.
# Iterates cases/*.sh; each case sources helpers.sh.
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_HOME="$HERE"
export LIB="$HERE/../../lib/commit-scope.sh"
export HOOK="$HERE/../../hooks/git-safety.sh"

[[ -f "$LIB"  ]] || { echo "missing lib: $LIB"   >&2; exit 2; }
[[ -f "$HOOK" ]] || { echo "missing hook: $HOOK" >&2; exit 2; }

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
EOF
chmod +x claude/.claude/tests/commit-scope/run.sh
```

- [ ] **Step 3: Write helpers**

```bash
cat > claude/.claude/tests/commit-scope/helpers.sh <<'EOF'
#!/usr/bin/env bash
# Sourced by every case. Provides assertions + git-fixture setup.
set -uo pipefail

: "${LIB:?LIB must be set by run.sh}"
: "${HOOK:?HOOK must be set by run.sh}"

CASE_TMP="$(mktemp -d -t commit-scope-test.XXXXXX)"
cleanup() { rm -rf "$CASE_TMP"; }
trap cleanup EXIT

# --- Lib-unit assertions ---------------------------------------------------

assert_banned() {
  local scope="$1" staged="${2:-}"
  ( source "$LIB" && is_banned_scope "$scope" "$staged" ) \
    || { echo "  expected '$scope' to be banned (staged='$staged'); was not" >&2; exit 1; }
}

assert_not_banned() {
  local scope="$1" staged="${2:-}"
  if ( source "$LIB" && is_banned_scope "$scope" "$staged" ); then
    echo "  expected '$scope' to be allowed (staged='$staged'); was banned" >&2
    exit 1
  fi
}

assert_suggest_eq() {
  local want="$1" staged="$2"
  local got
  got=$( source "$LIB" && suggest_scope "$staged" )
  [[ "$got" == "$want" ]] \
    || { echo "  suggest_scope want='$want' got='$got' (staged='$staged')" >&2; exit 1; }
}

# --- Hook-integration helpers ----------------------------------------------

# init_git_fixture <dir>
# Creates a git repo at <dir> with an initial empty commit so HEAD is valid.
init_git_fixture() {
  local dir="$1"
  ( cd "$dir" \
    && git init -q -b main \
    && git config user.email "test@example.com" \
    && git config user.name "Test" \
    && git commit -q --allow-empty -m "chore(seed): initial" )
}

# seed_known_scopes <dir> <scope1> [scope2 ...]
# Adds empty commits whose subjects use the given scopes so _known_scopes finds them.
seed_known_scopes() {
  local dir="$1"; shift
  local s
  for s in "$@"; do
    ( cd "$dir" && git commit -q --allow-empty -m "chore(${s}): seed" )
  done
}

# stage_file <dir> <path> [content]
# Touches a file in dir and stages it.
stage_file() {
  local dir="$1" path="$2" content="${3:-x}"
  mkdir -p "$(dirname "$dir/$path")"
  printf '%s\n' "$content" > "$dir/$path"
  ( cd "$dir" && git add "$path" )
}

# pretooluse_json <command>
# Emits a PreToolUse JSON envelope with command.
pretooluse_json() {
  local cmd="$1"
  jq -cn --arg c "$cmd" '{tool_input:{command:$c}}'
}

# run_hook_in <dir> <command>
# Pipes synthesized JSON to the hook, executed inside <dir>. Returns hook stdout.
run_hook_in() {
  local dir="$1" cmd="$2"
  ( cd "$dir" && pretooluse_json "$cmd" | bash "$HOOK" )
}

assert_hook_emits() {
  local out="$1" needle="$2"
  echo "$out" | grep -qF -- "$needle" \
    || { echo "  hook output missing '$needle'; got: $out" >&2; exit 1; }
}

assert_hook_silent_on() {
  local out="$1" needle="$2"
  if echo "$out" | grep -qF -- "$needle"; then
    echo "  hook unexpectedly emitted '$needle'; got: $out" >&2; exit 1
  fi
}
EOF
```

- [ ] **Step 4: Write 00-smoke**

```bash
cat > claude/.claude/tests/commit-scope/cases/00-smoke-lib-sources.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Lib sources without error and exposes CONTAINER_NAMES.
( source "$LIB" && [[ ${#CONTAINER_NAMES[@]} -gt 0 ]] ) \
  || { echo "  lib failed to source or CONTAINER_NAMES empty" >&2; exit 1; }
EOF
```

- [ ] **Step 5: Run smoke**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `1 passed, 0 failed`

---

### Task 2: S1 — Universal container ban with history escape

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (add helpers + `is_banned_scope` S1 path)
- Create: `claude/.claude/tests/commit-scope/cases/10-s1-container-docs.sh`
- Create: `claude/.claude/tests/commit-scope/cases/11-s1-container-src.sh`
- Create: `claude/.claude/tests/commit-scope/cases/12-s1-container-tests.sh`
- Create: `claude/.claude/tests/commit-scope/cases/13-s1-history-escape.sh`

- [ ] **Step 1: Write failing tests (10, 11, 12, 13)**

```bash
cat > claude/.claude/tests/commit-scope/cases/10-s1-container-docs.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE=""   # empty history -> no escape
assert_banned "docs"
EOF

cat > claude/.claude/tests/commit-scope/cases/11-s1-container-src.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE=""
assert_banned "src"
EOF

cat > claude/.claude/tests/commit-scope/cases/12-s1-container-tests.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE=""
assert_banned "tests"
EOF

cat > claude/.claude/tests/commit-scope/cases/13-s1-history-escape.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
# 'docs' is a container BUT also a real scope in this repo's history -> not banned
export COMMIT_SCOPE_KNOWN_OVERRIDE="docs,api,auth"
assert_not_banned "docs"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: cases 10-13 FAIL (`is_banned_scope` not yet defined).

- [ ] **Step 3: Add helpers + S1 logic to lib**

Append to `claude/.claude/lib/commit-scope.sh`:

```bash

# --- Private helpers --------------------------------------------------------

_known_scopes() {
  if [[ -n "${COMMIT_SCOPE_KNOWN_OVERRIDE:-}" ]]; then
    echo "$COMMIT_SCOPE_KNOWN_OVERRIDE" | tr ',' '\n'
    return 0
  fi
  git log --format='%s' -100 2>/dev/null \
    | awk -F'[()]' '/^[a-z]+\(/ {print $2}' \
    | sort -u
}

_is_container() {
  local s="$1" c
  for c in "${CONTAINER_NAMES[@]}"; do
    [[ "$s" == "$c" ]] && return 0
  done
  return 1
}

_in_known_scopes() {
  local scope="$1"
  _known_scopes | grep -qxF "$scope"
}

# --- Public API -------------------------------------------------------------

# is_banned_scope <scope> [<staged-files>]
# Exit 0 = banned, 1 = ok.
is_banned_scope() {
  local scope="$1" staged="${2:-}"

  # S1: universal container, with history escape
  if _is_container "$scope" && ! _in_known_scopes "$scope"; then
    return 0
  fi

  return 1
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `5 passed, 0 failed` (00 smoke + 10-13).

---

### Task 3: S2 — Repo basename ban

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (add `_repo_basename` + S2 path)
- Create: `claude/.claude/tests/commit-scope/cases/14-s2-repo-basename.sh`

- [ ] **Step 1: Write failing test**

```bash
cat > claude/.claude/tests/commit-scope/cases/14-s2-repo-basename.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="myapp"
export COMMIT_SCOPE_KNOWN_OVERRIDE="myapp,api"  # even if in history, S2 has no escape
assert_banned "myapp"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: case 14 FAILS.

- [ ] **Step 3: Add `_repo_basename` helper**

In `claude/.claude/lib/commit-scope.sh`, insert the helper before `_known_scopes`:

```bash
_repo_basename() {
  if [[ -n "${COMMIT_SCOPE_REPO_NAME:-}" ]]; then
    echo "$COMMIT_SCOPE_REPO_NAME"
    return 0
  fi
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  basename "$top"
}
```

- [ ] **Step 4: Extend `is_banned_scope` with S2**

Replace the body of `is_banned_scope` in `claude/.claude/lib/commit-scope.sh` with:

```bash
is_banned_scope() {
  local scope="$1" staged="${2:-}"

  # S1: universal container, with history escape
  if _is_container "$scope" && ! _in_known_scopes "$scope"; then
    return 0
  fi

  # S2: repo basename, no history escape
  local repo
  if repo=$(_repo_basename); then
    [[ "$scope" == "$repo" ]] && return 0
  fi

  return 1
}
```

- [ ] **Step 5: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `6 passed, 0 failed`.

---

### Task 4: S3 — Path-segment ban with history escape + plural inflection

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (add `_seg_matches_scope`, `_path_segments`, S3 path)
- Create: `claude/.claude/tests/commit-scope/cases/15-s3-path-segment-spec.sh`
- Create: `claude/.claude/tests/commit-scope/cases/16-s3-path-segment-plan.sh`
- Create: `claude/.claude/tests/commit-scope/cases/17-s3-path-segment-openspec.sh`
- Create: `claude/.claude/tests/commit-scope/cases/18-s3-history-escape.sh`
- Create: `claude/.claude/tests/commit-scope/cases/19-good-component-passes.sh`

- [ ] **Step 1: Write failing tests**

```bash
cat > claude/.claude/tests/commit-scope/cases/15-s3-path-segment-spec.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# 'spec' is singular of 'specs' path segment AND not in history
assert_banned "spec" "docs/superpowers/specs/2026-05-21-foo-design.md"
EOF

cat > claude/.claude/tests/commit-scope/cases/16-s3-path-segment-plan.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_banned "plan" "docs/superpowers/plans/2026-05-21-foo.md"
EOF

cat > claude/.claude/tests/commit-scope/cases/17-s3-path-segment-openspec.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_banned "openspec" "openspec/changes/foo/proposal.md"
EOF

cat > claude/.claude/tests/commit-scope/cases/18-s3-history-escape.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
# 'auth' is a path segment of src/auth/login.ts AND already in history -> allowed
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
assert_not_banned "auth" $'src/auth/login.ts'
EOF

cat > claude/.claude/tests/commit-scope/cases/19-good-component-passes.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_REPO_NAME="anyrepo"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# 'auth' is in history, not a container, not repo name, not a stale path segment
assert_not_banned "auth" $'src/auth/login.ts\ntests/auth/login_test.ts'
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: cases 15-17 FAIL (S3 not implemented); 18, 19 may pass coincidentally — that's fine.

- [ ] **Step 3: Add S3 helpers**

In `claude/.claude/lib/commit-scope.sh`, insert before `_in_known_scopes`:

```bash
_seg_matches_scope() {
  local scope="$1" seg="$2"
  [[ "$scope" == "$seg" ]] && return 0
  [[ "${scope}s" == "$seg" ]] && return 0
  [[ "$scope" == "${seg}s" ]] && return 0
  return 1
}

_path_segments() {
  local staged="$1"
  echo "$staged" | tr '/' '\n' | sed '/^$/d' | sed 's|\.md$||' | sort -u
}
```

- [ ] **Step 4: Extend `is_banned_scope` with S3**

Replace `is_banned_scope` in `claude/.claude/lib/commit-scope.sh` with:

```bash
is_banned_scope() {
  local scope="$1" staged="${2:-}"

  # S1: universal container, with history escape
  if _is_container "$scope" && ! _in_known_scopes "$scope"; then
    return 0
  fi

  # S2: repo basename, no history escape
  local repo
  if repo=$(_repo_basename); then
    [[ "$scope" == "$repo" ]] && return 0
  fi

  # S3: staged path segment with history escape + plural inflection
  if [[ -n "$staged" ]] && ! _in_known_scopes "$scope"; then
    local seg
    while IFS= read -r seg; do
      [[ -z "$seg" ]] && continue
      if _seg_matches_scope "$scope" "$seg"; then
        return 0
      fi
    done < <(_path_segments "$staged")
  fi

  return 1
}
```

- [ ] **Step 5: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `11 passed, 0 failed`.

---

### Task 5: `suggest_scope` — date-prefix slug step (step 1)

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (append `suggest_scope` with step 1 only)
- Create: `claude/.claude/tests/commit-scope/cases/20-suggest-from-date-slug.sh`

- [ ] **Step 1: Write failing test**

```bash
cat > claude/.claude/tests/commit-scope/cases/20-suggest-from-date-slug.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="read-once,auth,api"
# Date-slug 'read-once-hardening' matches known scope 'read-once' (longest suffix match)
assert_suggest_eq "read-once" "docs/superpowers/specs/2026-05-21-read-once-hardening-design.md"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: case 20 FAILS (suggest_scope not defined).

- [ ] **Step 3: Append `suggest_scope` step 1 + step 4-5 (history match)**

Append to `claude/.claude/lib/commit-scope.sh`:

```bash

# suggest_scope <staged-files>
# Echo candidate scope (empty if none).
suggest_scope() {
  local staged="$1"
  local count
  count=$(echo "$staged" | grep -c '.' || true)
  local candidate=""

  # Step 1: single file with date-prefixed slug
  if (( count == 1 )); then
    local base
    base=$(basename "$staged")
    if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)\.md$ ]]; then
      candidate="${BASH_REMATCH[1]}"
      candidate="${candidate%-design}"
      candidate="${candidate%-plan}"
    fi
  fi

  [[ -z "$candidate" ]] && return 0

  # Step 4-5: match against known scopes (longest match)
  local k best="" best_len=0
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$candidate" == "$k" ]] \
        || [[ "$candidate" == "${k}-"* ]] \
        || [[ "$candidate" == *"-${k}-"* ]] \
        || [[ "$candidate" == *"-${k}" ]]; then
      if (( ${#k} > best_len )); then
        best="$k"
        best_len=${#k}
      fi
    fi
  done < <(_known_scopes)

  if [[ -n "$best" ]]; then
    echo "$best"
  else
    # Step 6: echo bare candidate
    echo "$candidate"
  fi
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `12 passed, 0 failed`.

---

### Task 6: `suggest_scope` — nested-md-path step (step 2)

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (insert step 2 between step 1 and history match)
- Create: `claude/.claude/tests/commit-scope/cases/21-suggest-from-nested-md-path.sh`

- [ ] **Step 1: Write failing test**

```bash
cat > claude/.claude/tests/commit-scope/cases/21-suggest-from-nested-md-path.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="codex,api"
# OpenSpec-style: openspec/changes/codex-cli-fix/proposal.md
# Deepest non-container dir before file = 'codex-cli-fix' -> match 'codex' (longest suffix)
assert_suggest_eq "codex" "openspec/changes/codex-cli-fix/proposal.md"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: case 21 FAILS (suggest_scope returns empty — step 2 missing).

- [ ] **Step 3: Insert step 2 into `suggest_scope`**

In `claude/.claude/lib/commit-scope.sh`, find the `[[ -z "$candidate" ]] && return 0` line that follows step 1 and replace it with:

```bash
  # Step 2: single .md file under nested path; walk deepest-first
  if [[ -z "$candidate" ]] && (( count == 1 )) && [[ "$staged" == *.md ]]; then
    local dir seg
    dir=$(dirname "$staged")
    while [[ "$dir" != "." && "$dir" != "/" && "$dir" != "" ]]; do
      seg=$(basename "$dir")
      if ! _is_container "$seg"; then
        candidate="$seg"
        break
      fi
      dir=$(dirname "$dir")
    done
  fi

  [[ -z "$candidate" ]] && return 0
```

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `13 passed, 0 failed`.

---

### Task 7: `suggest_scope` — top-level dir + edge cases (steps 3, 6)

**Files:**
- Modify: `claude/.claude/lib/commit-scope.sh` (insert step 3 before final empty check)
- Create: `claude/.claude/tests/commit-scope/cases/22-suggest-from-toplevel-dir.sh`
- Create: `claude/.claude/tests/commit-scope/cases/23-suggest-skips-container-toplevel.sh`
- Create: `claude/.claude/tests/commit-scope/cases/24-suggest-multi-toplevel-empty.sh`
- Create: `claude/.claude/tests/commit-scope/cases/25-suggest-no-known-match-echoes-slug.sh`

- [ ] **Step 1: Write failing tests**

```bash
cat > claude/.claude/tests/commit-scope/cases/22-suggest-from-toplevel-dir.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Single top-level non-container 'auth/' -> candidate 'auth' -> known scope match
assert_suggest_eq "auth" $'auth/login.ts\nauth/logout.ts'
EOF

cat > claude/.claude/tests/commit-scope/cases/23-suggest-skips-container-toplevel.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Top-level 'src/' is a container AND file is NOT .md, so step 2 doesn't engage either
# Expected: empty (no useful suggestion derivable without more context)
assert_suggest_eq "" $'src/foo.ts\nsrc/bar.ts'
EOF

cat > claude/.claude/tests/commit-scope/cases/24-suggest-multi-toplevel-empty.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Multiple top-level dirs -> ambiguous -> empty
assert_suggest_eq "" $'auth/login.ts\napi/handlers.ts'
EOF

cat > claude/.claude/tests/commit-scope/cases/25-suggest-no-known-match-echoes-slug.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"
export COMMIT_SCOPE_KNOWN_OVERRIDE="auth,api"
# Date slug 'unknown-thing' has no known-scope match -> echo bare candidate
assert_suggest_eq "unknown-thing" "docs/superpowers/specs/2026-05-21-unknown-thing-design.md"
EOF
```

- [ ] **Step 2: Run to verify failures**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: case 22 FAILS (step 3 missing); 23, 24, 25 may pass coincidentally with current logic — that's fine.

- [ ] **Step 3: Insert step 3 into `suggest_scope`**

In `claude/.claude/lib/commit-scope.sh`, find the second `[[ -z "$candidate" ]] && return 0` (after step 2) and replace it with:

```bash
  # Step 3: single top-level non-container dir
  if [[ -z "$candidate" ]]; then
    local top
    top=$(echo "$staged" | cut -d/ -f1 | sort -u)
    if [[ "$(echo "$top" | wc -l)" -eq 1 ]] && ! _is_container "$top"; then
      candidate="$top"
    fi
  fi

  [[ -z "$candidate" ]] && return 0
```

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `17 passed, 0 failed`.

---

### Task 8: Sentinel test — repo-agnostic guarantee

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/50-sentinel-container-list.sh`

- [ ] **Step 1: Write sentinel test**

```bash
cat > claude/.claude/tests/commit-scope/cases/50-sentinel-container-list.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

# Anchor: CONTAINER_NAMES must contain the universal entries.
( source "$LIB"
  for required in docs src lib tests packages apps; do
    found=0
    for c in "${CONTAINER_NAMES[@]}"; do
      [[ "$c" == "$required" ]] && { found=1; break; }
    done
    [[ $found -eq 1 ]] || { echo "  CONTAINER_NAMES missing required entry: $required" >&2; exit 1; }
  done
)

# Guarantee: lib file must not contain framework-name literals as values.
# Match only `<name>` as a standalone token within an array literal or quoted string.
banned_literals=(spec plan openspec dotfiles proposal rfc prd)
for lit in "${banned_literals[@]}"; do
  if grep -E "^[[:space:]]*${lit}[[:space:]]|\"${lit}\"|'${lit}'" "$LIB" >/dev/null; then
    echo "  lib contains framework-name literal '$lit' (repo-agnostic violation)" >&2
    exit 1
  fi
done
EOF
```

- [ ] **Step 2: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `18 passed, 0 failed`.

---

### Task 9: Commit 1 — lib + lib-unit tests

- [ ] **Step 1: Verify clean working tree (besides our changes)**

Run: `git status`
Expected: only `claude/.claude/lib/commit-scope.sh` (new), `claude/.claude/tests/commit-scope/` (new) listed.

- [ ] **Step 2: Stage the new files**

```bash
git add claude/.claude/lib/commit-scope.sh
git add claude/.claude/tests/commit-scope/run.sh
git add claude/.claude/tests/commit-scope/helpers.sh
git add claude/.claude/tests/commit-scope/cases/
```

- [ ] **Step 3: Run full suite one more time**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `18 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(claude): add signal-driven commit-scope lib

New claude/.claude/lib/commit-scope.sh validates commit scopes against
four signals computed from filesystem + git log of the current repo:

  S1 universal filesystem container (with history escape)
  S2 repo basename (no history escape)
  S3 staged-path segment match (with history escape, +s plural inflection)
  S4 unknown-scope advisory (emitted by hook, not by this lib)

No framework-name list to maintain. Adding a new AI-skill framework
that publishes to its own artifact directory is caught by S3
automatically. Sentinel test forbids re-introducing framework
literals.

claude/.claude/tests/commit-scope/ covers all signals + suggest_scope
edge cases. 18 cases pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Hook extension + hook-integration tests (commit 2)

### Task 10: Hook-integration smoke

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/60-hook-smoke.sh`

- [ ] **Step 1: Write smoke that the hook sources cleanly and emits nothing fatal for an unrelated command**

```bash
cat > claude/.claude/tests/commit-scope/cases/60-hook-smoke.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/repo"
mkdir -p "$dir"
init_git_fixture "$dir"
# Non-git command -> hook should exit cleanly with no JSON
out=$(run_hook_in "$dir" "ls -la")
assert_hook_silent_on "$out" "Scope check"
assert_hook_silent_on "$out" "Staged files"
EOF
```

- [ ] **Step 2: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `19 passed, 0 failed`. (Hook smoke runs against unmodified `git-safety.sh` — no change yet.)

---

### Task 11: Hook banned-scope warning — S1

**Files:**
- Modify: `claude/.claude/hooks/git-safety.sh` (add lib source + banned-scope check block)
- Create: `claude/.claude/tests/commit-scope/cases/61-hook-emits-banned-s1-docs.sh`

- [ ] **Step 1: Write failing test**

```bash
cat > claude/.claude/tests/commit-scope/cases/61-hook-emits-banned-s1-docs.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/repo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "src/auth/login.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "docs: tweak"')
assert_hook_emits "$out" "scope='docs' is BANNED"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: case 61 FAILS — hook has no banned-scope check yet.

- [ ] **Step 3: Add banned-scope check block to `git-safety.sh`**

In `claude/.claude/hooks/git-safety.sh`, find the closing `fi` of the `commit -a` block (around line 89) and insert immediately after:

```bash

# --- Commit scope validation (signal-driven, non-blocking) ---
if [[ "$COMMAND" =~ git[[:space:]]+commit ]]; then
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/commit-scope.sh"
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"

  scope_msg=""
  if [[ "$COMMAND" =~ -m[[:space:]]+\"([^\"]*)\" ]]; then
    scope_msg="${BASH_REMATCH[1]}"
  elif [[ "$COMMAND" =~ -m[[:space:]]+\'([^\']*)\' ]]; then
    scope_msg="${BASH_REMATCH[1]}"
  fi

  declared_scope=""
  if [[ "$scope_msg" =~ ^[a-z]+\(([^)]+)\): ]]; then
    declared_scope="${BASH_REMATCH[1]}"
  elif [[ "$scope_msg" =~ ^([a-z]+): ]]; then
    declared_scope="${BASH_REMATCH[1]}"
  fi

  staged_for_scope=$(git diff --cached --name-only 2>/dev/null || true)

  if [[ -n "$declared_scope" ]] && is_banned_scope "$declared_scope" "$staged_for_scope"; then
    emit_context "PreToolUse" "Scope check: scope='${declared_scope}' is BANNED (filesystem container, repo basename, or path-segment match). Scope names a component, not a location. See CLAUDE.md > Commit rules > Scope."
  fi
fi
```

Note: extracts `<scope>` from both `type(scope): ...` AND unscoped `type: ...` forms. The latter case sets `declared_scope` to the bare type (e.g. `docs`) which is itself a container → S1 fires. This catches `docs: tweak` (used as test fixture above) the same way `docs(docs): tweak` would.

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `20 passed, 0 failed`.

---

### Task 12: Hook banned-scope warning — S2

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/62-hook-emits-banned-s2-repo-name.sh`

- [ ] **Step 1: Write test**

```bash
cat > claude/.claude/tests/commit-scope/cases/62-hook-emits-banned-s2-repo-name.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/myrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# Repo basename = 'myrepo' (last segment of $dir). Scope 'myrepo' fires S2.
out=$(run_hook_in "$dir" 'git commit -m "feat(myrepo): tweak"')
assert_hook_emits "$out" "scope='myrepo' is BANNED"
EOF
```

- [ ] **Step 2: Run to verify pass (S2 already wired by Task 11's lib call)**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `21 passed, 0 failed`.

---

### Task 13: Hook banned-scope warning — S3

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/63-hook-emits-banned-s3-path-segment.sh`

- [ ] **Step 1: Write test**

```bash
cat > claude/.claude/tests/commit-scope/cases/63-hook-emits-banned-s3-path-segment.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "openspec/changes/codex-cli-fix/proposal.md" "x"

# 'openspec' is a path segment, NOT in known scopes -> S3 fires
out=$(run_hook_in "$dir" 'git commit -m "docs(openspec): add proposal"')
assert_hook_emits "$out" "scope='openspec' is BANNED"
EOF
```

- [ ] **Step 2: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `22 passed, 0 failed`.

---

### Task 14: Hook suggest_scope emit + new-scope advisory

**Files:**
- Modify: `claude/.claude/hooks/git-safety.sh` (extend existing staged-context block with suggest + new-scope advisory)
- Create: `claude/.claude/tests/commit-scope/cases/64-hook-emits-suggest-from-date-slug.sh`
- Create: `claude/.claude/tests/commit-scope/cases/67-hook-emits-new-scope-advisory.sh`

- [ ] **Step 1: Write failing tests**

```bash
cat > claude/.claude/tests/commit-scope/cases/64-hook-emits-suggest-from-date-slug.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" read-once auth
stage_file "$dir" "docs/superpowers/specs/2026-05-21-read-once-foo-design.md" "x"

out=$(run_hook_in "$dir" 'git commit -m "docs(read-once): add spec"')
assert_hook_emits "$out" "Suggested scope (derived): read-once"
EOF

cat > claude/.claude/tests/commit-scope/cases/67-hook-emits-new-scope-advisory.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "billing/charges.ts" "x"

# 'billing' is NOT in known scopes, NOT a container, NOT repo basename
# -> not banned, but S4 advisory fires (new scope)
out=$(run_hook_in "$dir" 'git commit -m "feat(billing): add charges"')
assert_hook_silent_on "$out" "is BANNED"
assert_hook_emits "$out" "NEW SCOPE"
EOF
```

- [ ] **Step 2: Run to verify failure**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: cases 64 + 67 FAIL (suggest emit + advisory not yet wired).

- [ ] **Step 3: Extend staged-context block in `git-safety.sh`**

In `claude/.claude/hooks/git-safety.sh`, replace the existing context-building block (between `dirs=$(echo "$staged" | grep '/' ...)` and `emit_context "PreToolUse" "$ctx"`) with the new version. Locate the existing block at lines 209-244 of the current file. The new block:

```bash
file_count=$(echo "$staged" | wc -l)
dirs=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | tr '\n' ', ' | sed 's/,$//')

# Collect known scopes from recent history — cached with 60-second TTL.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")/../lib/session.sh"
# commit-scope.sh already sourced above for banned-scope check

repo_path=$(git rev-parse --show-toplevel 2>/dev/null || true)
repo_key=${repo_path//[^a-zA-Z0-9_]/_}
cache_dir="${XDG_RUNTIME_DIR:-$HOME/.cache/claude}"
mkdir -p "$cache_dir" 2>/dev/null || true
scope_cache="${cache_dir}/commit-scopes-${repo_key}"
scope_age=999
if [[ -f "$scope_cache" ]]; then
  scope_age=$(( EPOCHSECONDS - $(file_mtime "$scope_cache") ))
fi
if (( scope_age > 60 )); then
  known_scopes=$(git log --format='%s' -50 2>/dev/null \
    | awk -F'[()]' '/^[a-z]+\(/ && !seen[$2]++ { s = s (s?",":"") $2 } END { print s }' || true)
  printf '%s' "$known_scopes" > "$scope_cache" 2>/dev/null || true
else
  known_scopes=$(cat "$scope_cache" 2>/dev/null || true)
fi

suggested=$(suggest_scope "$staged")
top_level_count=$(echo "$staged" | grep '/' | cut -d/ -f1 | sort -u | wc -l)

ctx="Staged files (${file_count}): ${staged}"
[[ -n "$dirs" ]] && ctx+=". Top-level directories: ${dirs}"
[[ -n "$known_scopes" ]] && ctx+=". Known scopes: ${known_scopes}"
[[ -n "$suggested" ]] && ctx+=". Suggested scope (derived): ${suggested}"
if (( top_level_count > 1 )); then
  ctx+=". ATOMICITY: staged files span ${top_level_count} top-level dirs. Verify ONE logical change; split if not."
fi

# S4: new-scope soft advisory (when declared scope is valid but unfamiliar)
if [[ -n "${declared_scope:-}" ]] \
   && ! is_banned_scope "$declared_scope" "$staged" \
   && ! echo "$known_scopes" | tr ',' '\n' | grep -qxF "$declared_scope" \
   && [[ "$declared_scope" != "$suggested" ]]; then
  ctx+=". NEW SCOPE: '${declared_scope}' not in git log history; suggested from paths is '${suggested:-<none>}'. Verify scope names a component."
fi

ctx+=". Pick scope by component, not artifact path. See CLAUDE.md > Commit rules > Scope."

emit_context "PreToolUse" "$ctx"
```

- [ ] **Step 4: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `24 passed, 0 failed`.

---

### Task 15: Hook atomicity warning

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/65-hook-emits-atomicity-multi-toplevel.sh`
- Create: `claude/.claude/tests/commit-scope/cases/66-hook-no-atomicity-single-toplevel.sh`

- [ ] **Step 1: Write tests**

```bash
cat > claude/.claude/tests/commit-scope/cases/65-hook-emits-atomicity-multi-toplevel.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api billing
stage_file "$dir" "auth/login.ts" "x"
stage_file "$dir" "billing/charges.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(auth): tweak"')
assert_hook_emits "$out" "ATOMICITY"
EOF

cat > claude/.claude/tests/commit-scope/cases/66-hook-no-atomicity-single-toplevel.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth api
stage_file "$dir" "auth/login.ts" "x"
stage_file "$dir" "auth/logout.ts" "x"

out=$(run_hook_in "$dir" 'git commit -m "feat(auth): tweak"')
assert_hook_silent_on "$out" "ATOMICITY"
EOF
```

- [ ] **Step 2: Run to verify pass (already wired in Task 14)**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `26 passed, 0 failed`.

---

### Task 16: Hook edge cases — heredoc, single-quoted, no-m

**Files:**
- Create: `claude/.claude/tests/commit-scope/cases/68-hook-heredoc-skips-banned-check.sh`
- Create: `claude/.claude/tests/commit-scope/cases/69-hook-single-quoted-msg-parsed.sh`
- Create: `claude/.claude/tests/commit-scope/cases/70-hook-no-m-flag-skips.sh`

- [ ] **Step 1: Write tests**

```bash
cat > claude/.claude/tests/commit-scope/cases/68-hook-heredoc-skips-banned-check.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# Heredoc-style commit: -m argument is a $(cat <<EOF ... EOF) expansion.
# Our regex only matches simple -m "..." or -m '...'; heredoc skipped silently.
out=$(run_hook_in "$dir" 'git commit -m "$(cat <<HEREDOC
docs(spec): something
HEREDOC
)"')
assert_hook_silent_on "$out" "is BANNED"
# But staged context still emitted
assert_hook_emits "$out" "Staged files"
EOF

cat > claude/.claude/tests/commit-scope/cases/69-hook-single-quoted-msg-parsed.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
seed_known_scopes "$dir" auth
stage_file "$dir" "src/foo.ts" "x"

# Single-quoted -m argument: regex captures the inner string.
out=$(run_hook_in "$dir" "git commit -m 'docs(src): tweak'")
assert_hook_emits "$out" "scope='src' is BANNED"
EOF

cat > claude/.claude/tests/commit-scope/cases/70-hook-no-m-flag-skips.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$TEST_HOME/helpers.sh"

dir="$CASE_TMP/anyrepo"
mkdir -p "$dir"
init_git_fixture "$dir"
stage_file "$dir" "src/foo.ts" "x"

# No -m at all (editor-based commit). declared_scope stays empty -> banned-check skipped.
out=$(run_hook_in "$dir" 'git commit')
assert_hook_silent_on "$out" "is BANNED"
# Staged context still emitted
assert_hook_emits "$out" "Staged files"
EOF
```

- [ ] **Step 2: Run to verify pass**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `29 passed, 0 failed`.

---

### Task 17: Stow + claude-sync refresh validation

- [ ] **Step 1: Verify symlinks already exist (lib + tests are in stowed dirs)**

Run: `readlink ~/.claude/lib/commit-scope.sh 2>/dev/null || echo "not yet stowed"`
Expected: either an absolute path to the worktree's `commit-scope.sh`, or `not yet stowed`. Either is acceptable — the file is new and will become live after the user runs `stow -t ~ -R claude` post-merge.

Run: `bash claude/.claude/hooks/git-safety.sh </dev/null; echo "exit=$?"`
Expected: should not crash on empty input — but in practice `cat` will block. Skip this step's invocation; rely on tests for confidence.

- [ ] **Step 2: Confirm hook still works for non-commit git commands**

Run: `printf '{"tool_input":{"command":"git status"}}' | bash claude/.claude/hooks/git-safety.sh; echo "exit=$?"`
Expected: `exit=0`, no output (fast exit on non-commit).

---

### Task 18: Commit 2 — hook + hook-integration tests

- [ ] **Step 1: Verify only expected files changed**

Run: `git status`
Expected: `claude/.claude/hooks/git-safety.sh` modified, `claude/.claude/tests/commit-scope/cases/{60-70}*.sh` new.

- [ ] **Step 2: Stage**

```bash
git add claude/.claude/hooks/git-safety.sh
git add claude/.claude/tests/commit-scope/cases/60-hook-smoke.sh
git add claude/.claude/tests/commit-scope/cases/61-hook-emits-banned-s1-docs.sh
git add claude/.claude/tests/commit-scope/cases/62-hook-emits-banned-s2-repo-name.sh
git add claude/.claude/tests/commit-scope/cases/63-hook-emits-banned-s3-path-segment.sh
git add claude/.claude/tests/commit-scope/cases/64-hook-emits-suggest-from-date-slug.sh
git add claude/.claude/tests/commit-scope/cases/65-hook-emits-atomicity-multi-toplevel.sh
git add claude/.claude/tests/commit-scope/cases/66-hook-no-atomicity-single-toplevel.sh
git add claude/.claude/tests/commit-scope/cases/67-hook-emits-new-scope-advisory.sh
git add claude/.claude/tests/commit-scope/cases/68-hook-heredoc-skips-banned-check.sh
git add claude/.claude/tests/commit-scope/cases/69-hook-single-quoted-msg-parsed.sh
git add claude/.claude/tests/commit-scope/cases/70-hook-no-m-flag-skips.sh
```

- [ ] **Step 3: Run full suite**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `29 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(claude): wire commit-scope checks into git-safety hook

git-safety.sh now sources claude/.claude/lib/commit-scope.sh and
emits non-blocking warnings at commit time:

  - Banned-scope warning when is_banned_scope fires (S1/S2/S3)
  - Suggested-scope hint derived from staged paths
  - Atomicity warning when staged files span multiple top-level dirs
  - New-scope advisory when declared scope is unfamiliar (S4)

Parses -m "..." and -m '...' message forms; heredoc and no-m commits
skip the scope check silently (editor-based commits land in the
editor anyway).

Hook-integration tests cover all four signals plus edge cases
(heredoc, single-quoted, no-m, multi-toplevel atomicity).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — CLAUDE.md documentation (commit 3)

### Task 19: Replace `### Commit rules` block in CLAUDE.md

**Files:**
- Modify: `claude/.claude/CLAUDE.md` (replace the `### Commit rules` block under `## Git Workflow`)

- [ ] **Step 1: Locate current block**

Open `claude/.claude/CLAUDE.md`. The current block (around lines 81-86 of the worktree file) reads:

```markdown
### Commit rules

- Commit each self-contained logical change atomically.
- Conventional commits: `type(scope): description` -- types: feat, fix,
  docs, chore, refactor, test, ci, perf.
- Stage specific files; never `git add -A` or `git add .` (hook-enforced).
```

- [ ] **Step 2: Replace with new block**

Use Edit on `claude/.claude/CLAUDE.md`. `old_string`:

```
### Commit rules

- Commit each self-contained logical change atomically.
- Conventional commits: `type(scope): description` -- types: feat, fix,
  docs, chore, refactor, test, ci, perf.
- Stage specific files; never `git add -A` or `git add .` (hook-enforced).
```

`new_string`:

```
### Commit rules

#### Atomicity

One commit = one self-contained logical change. Reviewable, bisectable,
revertable on its own. Heuristics for splitting:

- Subject contains "and" / "also" / "plus" -> split.
- Staged files span more than one top-level package or affect both code
  and unrelated docs -> split.
- Fixing a bug AND refactoring the surrounding code -> split (bug fix
  first, refactor second).
- Addressing multiple PR review comments -> one commit per comment.

#### Staging

- Stage specific files: `git add <path1> <path2>`.
- Never `git add -A`, `git add .`, `git add --all`, `git add --update`,
  `git commit -a`, `git commit -am`. Hook-enforced.

#### Conventional commits

- Form: `type(scope): description`.
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`.

#### Scope = affected component, not artifact directory

Scope identifies WHAT the commit changes, not WHERE the artifact lives.
Read the file contents before choosing scope. The
`claude/.claude/hooks/git-safety.sh` hook emits a non-blocking warning
when the declared scope fails any of these signals (see
`claude/.claude/lib/commit-scope.sh` for the canonical implementation):

- **S1 - Universal container**: scope is a filesystem-convention
  container name (`docs`, `src`, `lib`, `bin`, `tests`, `scripts`,
  `packages`, `apps`, etc.) AND scope is not already in the repo's
  `git log` history.
- **S2 - Repo basename**: scope equals the current repository's
  directory name (e.g. scope `myapp` in repo `myapp/`). No history
  escape - repo names never identify a component.
- **S3 - Path-segment match**: scope (or its `+s` plural form) equals
  a directory segment of the staged file paths, AND scope is not in
  `git log` history. Catches `docs(spec)` when staging under
  `docs/superpowers/specs/`, `docs(openspec)` when staging under
  `openspec/changes/`, and any future framework that publishes to a
  documentation directory.
- **S4 - New-scope advisory** (soft): scope is allowed by S1-S3 but is
  not in `git log` history. Verify the scope names a component, not an
  artifact directory.

Real scopes are whatever component names appear in the current repo's
`git log`. Examples below use `<component>` placeholders; substitute
your repo's actual components.

#### Examples

```text
# Good
feat(<component>): <description>                 # scope names the affected component
docs(<component>): update <component> docs       # same
docs: <repo-wide policy change>                  # unscoped when no concrete component dominates

# Bad
feat(spec): <description>                        # 'spec' = artifact type (S3: matches 'specs/' segment)
feat(plan): <description>                        # 'plan' = artifact type (S3: matches 'plans/' segment)
docs(<repo-name>): <description>                 # repo name = location (S2)
docs(openspec): <description>                    # framework name (S3: matches 'openspec/' segment)
docs(docs): <description>                        # universal container (S1)
feat(<component>): change X and Y                # "and" = two changes -> split
```
```

- [ ] **Step 3: Verify the file parses cleanly**

Run: `bash -n claude/.claude/CLAUDE.md 2>&1 || true; head -1 claude/.claude/CLAUDE.md`
Expected: file is markdown (no syntax check applies); first line is `# Global Claude Code Preferences`.

- [ ] **Step 4: Run lib/hook suite still green (no regression)**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `29 passed, 0 failed`.

---

### Task 20: Commit 3 — CLAUDE.md replacement

- [ ] **Step 1: Verify only CLAUDE.md changed**

Run: `git status`
Expected: only `claude/.claude/CLAUDE.md` modified.

- [ ] **Step 2: Stage**

```bash
git add claude/.claude/CLAUDE.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(claude): document commit-scope rules in CLAUDE.md

Replaces the three-bullet Commit rules block under Git Workflow with
four subsections:

  - Atomicity: definition + four splitting heuristics
  - Staging: selective-staging requirement + banned commands
  - Conventional commits: form + type enum
  - Scope = affected component, not artifact directory: four-signal
    explanation referencing the lib + good/bad examples using
    <component> placeholders (repo-agnostic)

Canonical implementation pointer to claude/.claude/lib/commit-scope.sh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

- [ ] **Step 1: Three new commits visible**

Run: `git log --format='%h %s' main..HEAD`
Expected: three commits in order — `feat(claude): add signal-driven commit-scope lib`, `feat(claude): wire commit-scope checks into git-safety hook`, `docs(claude): document commit-scope rules in CLAUDE.md`.

- [ ] **Step 2: Test suite green at HEAD**

Run: `bash claude/.claude/tests/commit-scope/run.sh`
Expected: `29 passed, 0 failed`.

- [ ] **Step 3: No regression in existing read-once tests**

Run: `bash claude/.claude/tests/read-once/run.sh`
Expected: existing read-once suite still green.

- [ ] **Step 4: Hook dogfood check**

Stage a single file with a banned-scope subject and confirm warning would appear if this were a fresh session. Cannot directly verify inside the running session (PreToolUse fires in a child process; warnings land in the next agent turn). Document this limitation; the suite is authoritative.

- [ ] **Step 5: Branch ready for review**

Branch `worktree-atomic-commits-component-scopes` now contains spec + plan + three implementation commits. Hand off to `superpowers:requesting-code-review`, then `compound-engineering:ce-compound`, then `superpowers:finishing-a-development-branch` option 1.
