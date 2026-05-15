# Codex Atomic Commits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Codex from the user's dotfiles so it consistently makes atomic conventional commits in any project.

**Architecture:** Put durable behavioral guidance in `codex/.codex/AGENTS.md`, add one focused shell hook that blocks broad staging and commit-all commands, and wire that hook through `codex/.codex/config.base.toml`. Keep enforcement generic: no branch, PR, worktree, or repository-specific policy.

**Tech Stack:** Codex CLI `AGENTS.md`, Codex `PreToolUse` command hooks in TOML, Bash, `jq`, Git, GNU Stow package layout.

---

## Source Material

- Design spec: `docs/superpowers/specs/2026-05-15-codex-atomic-commits-design.md`
- Existing generated Codex config pattern: `codex/.codex/config.base.toml`
- Existing sync script: `bin/.local/bin/codex-sync`
- Existing Git conventional commit hook: `git/.config/git/hooks/commit-msg`
- Official Codex config schema: `https://developers.openai.com/codex/config-schema.json`

## File Structure

- Create `codex/.codex/AGENTS.md`: user-level Codex instructions for atomic commits, conventional commit subjects, verification, and `/review`.
- Create `codex/.codex/hooks/atomic-commits.sh`: focused `PreToolUse` shell hook that denies only broad staging and commit-all patterns.
- Create `codex/.codex/tests/test-atomic-commits-hook.sh`: direct hook tests using synthetic Codex hook payloads.
- Modify `codex/.codex/config.base.toml`: enable hooks explicitly and register `atomic-commits.sh` for Bash shell commands.
- No change to `codex/.codex/config.toml`: it is generated and gitignored. Run `codex-sync` during verification to confirm regeneration works, but commit only tracked source files.
- No change to `git/.config/git/hooks/commit-msg`: it already validates conventional commit subjects.

## Task 1: Add User-Level Codex Commit Instructions

**Files:**
- Create: `codex/.codex/AGENTS.md`
- Test: manual content check with `rg`

- [ ] **Step 1: Create the instruction file**

Use `apply_patch` to add this exact file:

```markdown
# Codex User Instructions

## Git Commit Workflow

- Commit each self-contained logical change separately.
- Use conventional commit subjects: `type(scope): description`.
- Prefer these types unless the project documents a different convention:
  `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, and `perf`.
- Stage explicit paths only. Do not use `git add -A`, `git add --all`,
  `git add -u`, `git add .`, `git commit -a`, or `git commit -am`.
- Before committing, inspect `git diff` and `git diff --cached`.
- If the working tree contains unrelated edits, split them into separate
  commits by staging only the files for one logical change at a time.
- Choose commit scopes from recent project history when a clear scope exists.
  A new scope is acceptable when the project genuinely needs one.
- Keep the commit subject concise. Aim for 72 characters or fewer.
- Run relevant verification before committing when feasible. If no verification
  command is obvious, say that explicitly.
- Use Codex `/review` before finalizing non-trivial changes.
- If a commit message hook rejects a subject, read the rejection reason, inspect
  recent subjects with `git log --format=%s -50`, and retry with a valid
  conventional subject.
```

- [ ] **Step 2: Verify the wording avoids forbidden phrasing**

Run:

```bash
rg -n "[gG]lobal" codex/.codex/AGENTS.md
```

Expected: exit code `1` with no output.

- [ ] **Step 3: Verify the important rules are present**

Run:

```bash
rg -n "Commit each self-contained|conventional commit|Stage explicit paths|git add -A|/review" codex/.codex/AGENTS.md
```

Expected: matching lines for all five phrases.

- [ ] **Step 4: Commit Task 1**

Run:

```bash
git add codex/.codex/AGENTS.md
git commit -m "docs(codex): add atomic commit instructions"
```

Expected: commit succeeds.

## Task 2: Add Focused Atomic Commit Hook With Tests

**Files:**
- Create: `codex/.codex/hooks/atomic-commits.sh`
- Create: `codex/.codex/tests/test-atomic-commits-hook.sh`

- [ ] **Step 1: Write the failing test file**

Use `apply_patch` to add this exact file:

```bash
#!/usr/bin/env bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
HOOK="$HOOK_ROOT/atomic-commits.sh"

run_hook() {
  local cmd="$1"
  jq -cn --arg cwd "$PWD" --arg cmd "$cmd" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $cwd, tool_input: {command: $cmd}}' |
    bash "$HOOK"
}

assert_denied() {
  local name="$1"
  local cmd="$2"
  local output
  output=$(run_hook "$cmd")
  if ! jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s\nexpected deny, got: %s\n' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s\n' "$name"
}

assert_allowed() {
  local name="$1"
  local cmd="$2"
  local output
  output=$(run_hook "$cmd")
  if [[ -n "$output" ]] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null <<<"$output"; then
    printf 'not ok - %s\nexpected allow, got: %s\n' "$name" "$output" >&2
    return 1
  fi
  printf 'ok - %s\n' "$name"
}

assert_denied "blocks git add dot" "git add ."
assert_denied "blocks git add dash A" "git add -A"
assert_denied "blocks git add all" "git add --all"
assert_denied "blocks git add update" "git add --update"
assert_denied "blocks git add dash u" "git add -u"
assert_denied "blocks git add separator dot" "git add -- ."
assert_denied "blocks git -C add dot" "git -C /tmp/example add ."
assert_denied "blocks commit all" "git commit -a -m 'fix(test): change'"
assert_denied "blocks commit am" "git commit -am 'fix(test): change'"
assert_denied "blocks commit long all" "git commit --all -m 'fix(test): change'"

assert_allowed "allows explicit file staging" "git add src/app.ts tests/app.test.ts"
assert_allowed "allows normal commit" "git commit -m 'fix(test): change'"
assert_allowed "allows git status" "git status --short"
assert_allowed "allows search containing git add text" "rg -n 'git add .' docs"
assert_allowed "allows non-git command" "sed -n '1,20p' README.md"
```

- [ ] **Step 2: Run the test to verify it fails because the hook is missing**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: FAIL with a message from Bash that `codex/.codex/hooks/atomic-commits.sh` does not exist.

- [ ] **Step 3: Add the hook implementation**

Use `apply_patch` to add this exact file:

```bash
#!/usr/bin/env bash
# Codex PreToolUse hook: enforce atomic staging habits for git commits.
set -euo pipefail

input=$(cat)
command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // ""' 2>/dev/null || true)
[[ -n "$command_text" ]] || exit 0

deny() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

git_subcommand_pattern() {
  local subcmd="$1"
  printf '(^|[[:space:];&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+%s([[:space:]]|$)' "$subcmd"
}

has_git_subcommand() {
  local subcmd="$1" pattern
  pattern=$(git_subcommand_pattern "$subcmd")
  [[ "$command_text" =~ $pattern ]]
}

[[ "$command_text" =~ (^|[[:space:];&])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]] ]] || exit 0

if [[ "$command_text" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+add[[:space:]]+(-A|--all|--update|-u|--[[:space:]]+\.(\ |$)|\.(\ |$)) ]]; then
  deny "BLOCKED: Stage explicit paths for one logical change. Use: git add <file1> <file2> ..."
fi

if has_git_subcommand "commit"; then
  cmd_no_msg=$(printf '%s' "$command_text" | sed 's/ -m ["'"'"'$].*//')
  if [[ "$cmd_no_msg" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit[[:space:]]+.*(-a(\ |$)|-am(\ |$)|--all) ]]; then
    deny "BLOCKED: Do not use git commit -a, git commit -am, or git commit --all. Stage explicit paths first, then commit."
  fi
fi
```

- [ ] **Step 4: Make the hook and test executable**

Run:

```bash
chmod +x codex/.codex/hooks/atomic-commits.sh codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: no output.

- [ ] **Step 5: Run the hook test to verify it passes**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected:

```text
ok - blocks git add dot
ok - blocks git add dash A
ok - blocks git add all
ok - blocks git add update
ok - blocks git add dash u
ok - blocks git add separator dot
ok - blocks git -C add dot
ok - blocks commit all
ok - blocks commit am
ok - blocks commit long all
ok - allows explicit file staging
ok - allows normal commit
ok - allows git status
ok - allows search containing git add text
ok - allows non-git command
```

- [ ] **Step 6: Run ShellCheck if available**

Run:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck codex/.codex/hooks/atomic-commits.sh codex/.codex/tests/test-atomic-commits-hook.sh
else
  echo "shellcheck not installed; skipped"
fi
```

Expected: either no output from ShellCheck or `shellcheck not installed; skipped`.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add codex/.codex/hooks/atomic-commits.sh codex/.codex/tests/test-atomic-commits-hook.sh
git commit -m "feat(codex): guard atomic commit staging"
```

Expected: commit succeeds.

## Task 3: Wire the Hook Into Codex Config

**Files:**
- Modify: `codex/.codex/config.base.toml`
- Test: `codex-sync`, `codex features list`, and direct hook tests

- [ ] **Step 1: Add the hooks feature flag and hook registration**

Use `apply_patch` to modify `codex/.codex/config.base.toml`.

Add this block after `web_search = "live"`:

```toml
[features]
# Keep command hooks explicit in the checked-in base config.
hooks = true
```

Add this block after the `[history]` section:

```toml
[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = 'bash "$HOME/.codex/hooks/atomic-commits.sh"'
timeout = 10
statusMessage = "Checking atomic commit workflow"
```

- [ ] **Step 2: Verify TOML shape by regenerating the ignored config**

Run:

```bash
DOTFILES="$PWD" bash bin/.local/bin/codex-sync
```

Expected: no output and `codex/.codex/config.toml` is regenerated from `config.base.toml`.

- [ ] **Step 3: Confirm the generated config contains the hook**

Run:

```bash
rg -n "hooks = true|atomic-commits.sh|Checking atomic commit workflow" codex/.codex/config.toml
```

Expected: lines matching all three patterns.

- [ ] **Step 4: Confirm the generated config remains ignored**

Run:

```bash
git status --short --ignored codex/.codex/config.toml
```

Expected:

```text
!! codex/.codex/config.toml
```

- [ ] **Step 5: Confirm hooks are available in this Codex CLI**

Run:

```bash
codex features list | rg '^hooks[[:space:]]+stable[[:space:]]+true'
```

Expected: one line showing `hooks` as `stable` and `true`.

- [ ] **Step 6: Re-run the direct hook test**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
```

Expected: all `ok - ...` lines from Task 2.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add codex/.codex/config.base.toml
git commit -m "chore(codex): enable atomic commit hook"
```

Expected: commit succeeds.

## Task 4: Document the Dotfiles Sync Behavior

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update package conventions**

Use `apply_patch` to add this paragraph to `CLAUDE.md` in the `Package conventions` section, immediately after the paragraph about the `codex/` package:

```markdown
- Codex user instructions live in `codex/.codex/AGENTS.md`. Codex command hooks
  live in `codex/.codex/hooks/` and are registered from
  `codex/.codex/config.base.toml`; run `codex-sync` after editing the base
  config to regenerate the gitignored `config.toml`.
```

- [ ] **Step 2: Verify the documentation wording avoids forbidden phrasing**

Run:

```bash
rg -n "[gG]lobal" CLAUDE.md codex/.codex/AGENTS.md docs/superpowers/specs/2026-05-15-codex-atomic-commits-design.md docs/superpowers/plans/2026-05-15-codex-atomic-commits.md
```

Expected: no output for the new Codex workflow wording. Existing unrelated text in `CLAUDE.md` may appear if it predates this task; do not rewrite unrelated Claude wording.

- [ ] **Step 3: Commit Task 4**

Run:

```bash
git add CLAUDE.md
git commit -m "docs(codex): document commit workflow config"
```

Expected: commit succeeds.

## Task 5: Final Verification

**Files:**
- Verify: `codex/.codex/AGENTS.md`
- Verify: `codex/.codex/hooks/atomic-commits.sh`
- Verify: `codex/.codex/tests/test-atomic-commits-hook.sh`
- Verify: `codex/.codex/config.base.toml`
- Verify: `CLAUDE.md`

- [ ] **Step 1: Run all focused tests**

Run:

```bash
bash codex/.codex/tests/test-atomic-commits-hook.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck codex/.codex/hooks/atomic-commits.sh codex/.codex/tests/test-atomic-commits-hook.sh
else
  echo "shellcheck not installed; skipped"
fi
DOTFILES="$PWD" bash bin/.local/bin/codex-sync
codex features list | rg '^hooks[[:space:]]+stable[[:space:]]+true'
```

Expected: hook tests print all `ok - ...` lines, ShellCheck passes or is skipped, `codex-sync` has no output, and `codex features list` confirms hooks are enabled.

- [ ] **Step 2: Exercise the existing commit message hook with sample messages**

Run:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
printf 'fix(codex): validate hook sample\n' > "$tmpdir/valid"
printf 'update stuff\n' > "$tmpdir/invalid"
bash git/.config/git/hooks/commit-msg "$tmpdir/valid"
if bash git/.config/git/hooks/commit-msg "$tmpdir/invalid"; then
  echo "expected invalid commit subject to fail" >&2
  exit 1
else
  echo "invalid commit subject rejected as expected"
fi
```

Expected:

```text
COMMIT REJECTED: subject does not follow conventional commits.
...
invalid commit subject rejected as expected
```

The rejection text is printed to stderr before the final confirmation line.

- [ ] **Step 3: Confirm only intended tracked files changed**

Run:

```bash
git status --short
```

Expected: clean after the previous task commits. If the plan file itself is uncommitted, stage and commit it with:

```bash
git add docs/superpowers/plans/2026-05-15-codex-atomic-commits.md
git commit -m "docs(codex): plan atomic commit workflow"
```

- [ ] **Step 4: Summarize the implementation branch**

Run:

```bash
git log --oneline main..HEAD
```

Expected: atomic commits for instructions, hook/tests, config wiring, documentation, and this plan if it was committed on the implementation branch.
