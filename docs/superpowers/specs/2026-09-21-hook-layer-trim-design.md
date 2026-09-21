# Trim the hook layer to three enforcements

Date: 2026-09-21
Status: approved, not yet implemented
Branch: `worktree-git-guardrail-gaps`

## Goal

Reduce the Claude Code hook layer to exactly the three enforcements that are
worth enforcing mechanically -- worktree isolation, atomic commits, and
conventional commits -- and delete everything else.

Target: 2 hook registrations and ~570 lines, down from 14 registrations and
2,443 lines of hook and lib code.

## Problem

The hook layer grew to 12 scripts and 5 libs across 14 registrations. Only
three of those registrations enforce anything. The rest inject context,
suppress redundant reads, write an audit log nobody reads, ring a terminal
bell, and add a semantic permission layer on top of a permission system that
already has 136 rules.

Two specific costs justify acting now rather than leaving it:

**Size hides behaviour.** `read-once.sh` alone is 539 lines -- 22% of the
layer -- to save tokens. `git-session-start.sh` is filed under "context
injection" but line 157 is the only writer of the marker that makes
`worktree-guard.sh` work. Nothing in either file's name or documentation says
so. A future trim that deleted `git-session-start.sh` as "just context" would
have left `worktree-guard.sh` registered, passing all 0 of its tests, and
enforcing nothing -- the failure shape already documented in
`docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`.

**Every hook is a bash 3.2 liability.** Per
`docs/solutions/conventions/hooks-run-under-macos-system-bash-3-2-2026-09-18.md`,
hooks run under `/bin/bash` 3.2.57 and bash 4 syntax fails *silently* -- a
PreToolUse hook that exits 0 without output is indistinguishable from a
permissive one. Three hooks were entirely dead this way before being found.
Fewer hooks is fewer places for that to happen.

## Decisions

### D1 -- The keep set is defined by the three enforcements

| File | Enforces |
| --- | --- |
| `hooks/commit-guard.sh` | atomic commits, conventional commit scope, no commit on main |
| `hooks/worktree-guard.sh` | worktree isolation |
| `lib/commit-scope.sh` | the S1-S4 scope signals |
| `lib/git-context.sh` | `emit_context`, `cwd_repo_hint`, `worktree_kind` |
| `lib/portability.sh` | `file_mtime`, `to_lower` |

Nothing else survives. Convenience, observability, and ergonomics are not
enforcement and are not worth a hook each.

### D2 -- The worktree guard becomes markerless

Today the guard is two halves: `git-session-start.sh:157` touches
`$HOME/.claude/session-worktrees/pending-<session-id>`, and
`worktree-guard.sh` blocks while that file exists.
`worktree-entered.sh` deletes it. The split exists only because the guard was
written to need a session id.

It does not. A linked worktree is detectable at edit time from git alone:
`git rev-parse --absolute-git-dir` differs from `git rev-parse
--git-common-dir`. The guard decides for itself:

```bash
[[ "${CLAUDE_WORKTREE_GUARD:-on}" == "off" ]] && exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ "$(worktree_kind)" == "linked" ]] && exit 0
# file_path resolves outside the repo working tree -> exit 0
# otherwise -> block
```

This deletes the state directory, the session-id parsing, the 24-hour stale
marker sweep, the self-healing branch in `check_worktree_pending`, the
SessionStart/first-edit race, and `worktree-entered.sh` entirely.

**Behaviour change, accepted:** today, entering a worktree once clears the
marker and main-checkout edits are allowed for the rest of that session.
Markerless, they are always blocked. The guard matches only
`Write|Edit|NotebookEdit`, so `git merge`, `rm`, and `stow` via Bash are
unaffected; the change bites only when editing a file in the main checkout
after a merge.

**Escape hatch changes shape:** `rm <marker>` is replaced by
`CLAUDE_WORKTREE_GUARD=off`, matching the existing `CLAUDE_PERMISSION_POLICY=off`
convention.

### D3 -- No SessionStart hook at all

With no marker to arm, nothing needs to run at session start.
`git-session-start.sh` is deleted whole rather than reduced to a stub.

The `MODE: no-pr` announcement goes with it, along with merged-branch
auto-checkout, the linked-worktree listing, and the daily cache/audit GC. See
Risks for what that costs.

### D4 -- `no-pr` mode is deleted, not defaulted

`CLAUDE_GIT_WORKFLOW=no-pr` gates exactly two branches in `git-safety.sh`:
merge/rebase/cherry-pick on main (line 117) and push to main (line 137).
Commit-on-main (line 109) is unconditional and does not consult it.

The variable is live at `no-pr` in the working environment, so both gates
already evaluate to "allow" on every invocation. Deleting the mode removes
dead configurability: merge-to-main and push-to-main become unconditionally
allowed in the hook, and commit-on-main stays blocked.

Push-to-main is not left unguarded -- `Bash(git push origin main*)`,
`Bash(git push * main*)`, and `Bash(git push * master*)` remain in
`permissions.ask` and still prompt.

This also removes `workflow_no_pr` from the lib and the `NO_PR` inline check
from the hot path.

### D5 -- Rename two files for accuracy

| Now | Becomes | Why |
| --- | --- | --- |
| `hooks/git-safety.sh` | `hooks/commit-guard.sh` | it guards commits; "safety" names nothing |
| `lib/session.sh` | `lib/git-context.sh` | after D2 and D4 it holds no session state |

`worktree-guard.sh`, `lib/commit-scope.sh`, and `lib/portability.sh` keep their
names -- each already says what it is.

`lib/portability.sh` keeps `to_lower` despite having no caller after this
change. `CLAUDE.md` names it as *the* bash-3.2 lowercase escape hatch, and the
next hook that needs one should find it there rather than reinvent `${x,,}`.
`run_timeout` is dropped -- its only caller was `git-session-start.sh`.

### D6 -- The semantic permission hook goes; the glob lists stay

`permission-policy.sh` plus its lib is 220 lines catching shapes a glob cannot
express: shell-expanded secret paths (`$HOME/.ssh/*`), `rm -rf` deny-list
bypass forms (`\rm`, `command rm`, quoted, leading whitespace), curl/wget
piped to a shell, direct edits to live `~/.claude/`, shell-init and
persistence file edits, and suspicious WebFetch targets.

It is deleted. The 52 `permissions.deny` and 84 `permissions.ask` rules in
`settings.base.json` are **not** hooks and are untouched, including every
secret-file rule and `Bash(rm -rf *)`. The loss is bounded to the bypass forms
and shell-expanded paths. See Risks.

### D7 -- Fill the mattpocock gaps as rules, do not adopt the skill

`mattpocock/skills` `git-guardrails-claude-code` is one 24-line PreToolUse
Bash hook with nine `grep -qE` patterns and a hard `exit 2`.

Seven of its nine patterns were already covered by `permissions.ask`. Two were
not, and both discard every uncommitted change in the working tree with
nothing in the reflog: `git checkout .` and `git restore .`.

Those two, plus the bare no-argument forms of `git reset --hard` and
`git clean -f` (the committed rules end in a trailing glob that may require a
following character), were added to `permissions.ask` in commit `0cd3b98`.

The skill itself is not adopted: it blocks `git push` outright with no
allowlist and no bypass, which breaks the normal path in every repo, and it
covers none of worktree isolation, main-branch protection, the `git add -A`
ban, or commit scope.

### D8 -- The codex hook layer is untouched

`codex/.codex/config.base.toml` registers `atomic-commits.sh` and
`worktree-guard.sh` from `~/.codex/hooks/`, which are physically separate files
(9.9 KB and 53 KB) with no shared code. Nothing in this change reaches them.
The known stub in the codex guard's shell branch
(`docs/solutions/tooling-decisions/codex-worktree-guard-shell-branch-is-a-stub-2026-09-18.md`)
stays open.

## Changes

### 1. `hooks/worktree-guard.sh` -- rewrite markerless

50 -> ~30 lines. Per D2. Drops `parse_session_id`, `STATE_DIR`, the
`compgen -G` fast exit, and the `check_worktree_pending` delegation. Adds the
`CLAUDE_WORKTREE_GUARD` env check and an inline block message naming that
escape hatch.

### 2. `hooks/git-safety.sh` -> `hooks/commit-guard.sh` -- rename and trim

296 -> ~270 lines. Per D4 and D5: remove the `NO_PR` variable, its inline
`CLAUDE_GIT_WORKFLOW` read, and the `"$NO_PR" != "true" &&` condition from
both the merge/rebase/cherry-pick guard and the push guard. Update the
`source` path for the renamed lib. No change to the `git add`, `git commit -a`,
commit-on-main, or scope logic.

### 3. `lib/session.sh` -> `lib/git-context.sh` -- rename and trim

143 -> ~50 lines. Keep `emit_context`, `cwd_repo_hint`, `worktree_kind`.
Delete `emit_context_with_msg`, `parse_session_id`, `pending_file`,
`check_worktree_pending`, `workflow_no_pr`, and `STATE_DIR`.

### 4. `lib/portability.sh` -- trim

41 -> ~25 lines. Keep `file_mtime` and `to_lower`; delete `run_timeout`.

### 5. `claude/.claude/settings.base.json` -- 14 registrations to 2

Remove every `hooks` entry except the two PreToolUse registrations, and point
the Bash matcher at the renamed script:

```
PreToolUse  Bash                       bash $HOME/.claude/hooks/commit-guard.sh
PreToolUse  Write|Edit|NotebookEdit    bash $HOME/.claude/hooks/worktree-guard.sh
```

Removed events entirely: `SessionStart`, `UserPromptSubmit`, `PostToolUse`,
`PostToolUseFailure`, `PostCompact`, `Notification`, `SessionEnd`.

`permissions`, `env`, `enabledPlugins`, `extraKnownMarketplaces`, and
`outputStyle` are untouched.

### 6. Delete 11 hooks and 3 libs -- 1,718 lines

| File | Lines |
| --- | --- |
| `hooks/read-once.sh` | 539 |
| `hooks/notify.sh` | 192 |
| `hooks/git-session-start.sh` | 169 |
| `lib/permission-policy.sh` | 162 |
| `hooks/resolve-pr-refs.sh` | 115 |
| `lib/read-once-cache.sh` | 114 |
| `hooks/failure-recovery.sh` | 85 |
| `hooks/audit-log.sh` | 80 |
| `hooks/permission-policy.sh` | 58 |
| `hooks/restore-git-context.sh` | 57 |
| `lib/notify-pane.sh` | 55 |
| `hooks/read-once-gc.sh` | 49 |
| `hooks/worktree-entered.sh` | 24 |
| `hooks/worktree-exited.sh` | 19 |

### 7. Tests

Delete `tests/read-once/` (19 cases), `tests/permission-policy/` (13 cases),
`tests/notify-pane/` (6 cases).

Rename `tests/session-lib/` -> `tests/git-context/` and drop the cases for
deleted functions, including `30-workflow-no-pr-set.sh` and
`31-workflow-no-pr-unset.sh`.

Keep `tests/commit-scope/` (32 cases) and `tests/bash-portability/`, updating
any path references to the renamed files.

**Add a `tests/worktree-guard/` suite.** The rewritten guard currently has no
test of its own, and its failure mode is silent permissiveness. The suite must
assert the *block* branch, not only the allow branches -- see V1.

The three non-hook suites (`output-style/`, `theme-contrast/`,
`mcp-permission-overlay/`) are untouched.

### 8. `claude/.claude/hooks/README.md` -- rewrite

116 lines documenting 12 hooks and 5 libs. Rewrite for 2 hooks and 3 libs.

### 9. `CLAUDE.md` (dotfiles project file) -- update stale passages

At minimum: the "Hook shell constraint (bash 3.2)" section (it cites "16 of
them across `settings.base.json` and `codex/.codex/config.base.toml`"); the
entire "Semantic policy hook" section; the `git-safety.sh` reference in
"Commit scope"; and "Hook-enforced." in the staging rule. Grep for
`git-safety`, `permission-policy`, `read-once`, `session.sh`, and
`git-session-start` before declaring this done.

## Verification

### V1 -- The worktree guard blocks, and is seen to block (blocking)

The whole point of D2 is that a guard which cannot enforce must not look like
one that can. Assert all four branches with the hook invoked the way its
config invokes it (`bash <path>`, not the shebang):

1. Main checkout, `file_path` inside the repo -> **exit 2**, message names
   `CLAUDE_WORKTREE_GUARD=off`.
2. Linked worktree, same path -> exit 0.
3. Main checkout, `file_path` outside the repo working tree -> exit 0.
4. `CLAUDE_WORKTREE_GUARD=off` in the main checkout -> exit 0.

Case 1 is the one that matters. A suite containing only 2-4 passes against a
guard that has been deleted.

### V2 -- The commit guard still enforces all three

Pipe representative payloads to `commit-guard.sh` and assert exit 2 for:
`git add -A`, `git add .`, `git add --all`, `git add --update`,
`git commit -a`, `git commit -am "x"`, and `git commit` while HEAD is main.
Assert exit 0 for `git merge <branch>` on main and `git push origin main`
(D4 removed those gates).

### V3 -- Suites pass

Run each as its own plain command (the worktree-isolation guard refuses loops
and heredocs):

```sh
cd claude/.claude/tests/commit-scope && bash run.sh
cd claude/.claude/tests/worktree-guard && bash run.sh
cd claude/.claude/tests/git-context && bash run.sh
cd claude/.claude/tests/bash-portability && bash run.sh
cd claude/.claude/tests/mcp-permission-overlay && bash run.sh
cd claude/.claude/tests/output-style && bash run.sh
cd claude/.claude/tests/theme-contrast && bash run.sh
```

### V4 -- No dangling references to deleted files

```sh
grep -rn 'git-safety\|permission-policy\|read-once\|notify-pane\|git-session-start\|resolve-pr-refs\|failure-recovery\|restore-git-context\|audit-log\|worktree-entered\|worktree-exited\|lib/session\.sh\|workflow_no_pr\|session-worktrees' \
  --include='*.sh' --include='*.json' --include='*.md' claude/ bin/ CLAUDE.md
```

Frozen plan and spec documents under `docs/superpowers/` are expected hits and
are left alone. Anything under `claude/`, `bin/`, or `CLAUDE.md` is a real
dangling pointer and must be fixed -- this is the bug the previous branch
shipped and had to correct.

### V5 -- No dangling symlinks after restow

Deleting and renaming stowed files leaves dead links in `~/.claude/hooks/` and
`~/.claude/lib/`, exactly as `CLAUDE.company.md` did. **After merge, from the
main checkout only** (never from a worktree -- `CLAUDE.md` > Stow gotchas):

```sh
cd ~/workspace/dotfiles && stow -t ~ -R claude
find ~/.claude/hooks ~/.claude/lib -type l ! -exec test -e {} \; -print
```

The `find` must print nothing. Then run `claude-sync` to regenerate
`~/.claude/settings.json` with the two remaining registrations, and confirm
with `jq '.hooks' ~/.claude/settings.json`.

### V6 -- bash 3.2

Both surviving hooks and all three libs run under `/bin/bash` explicitly:

```sh
/bin/bash -n claude/.claude/hooks/commit-guard.sh
/bin/bash -n claude/.claude/hooks/worktree-guard.sh
```

A green run under Homebrew bash 5 proves nothing. `tests/bash-portability/`
covers the syntax scan.

## Risks

**Loss of the semantic permission layer while live secrets are unrotated.**
D6 removes the check for shell-expanded secret paths (`$HOME/.ssh/*`,
`/Users/ben/.ssh/*`) and the `rm -rf` bypass forms (`\rm`, `command rm`). The
literal-path `deny` globs stay, so the common forms are still blocked. This
lands while `zsh/.zshenv` holds four unrotated live credentials
(`GITHUB_ACCESS_TOKEN`, `SENTRY_AUTH_TOKEN`, `ARGOCD_API_TOKEN`,
`MDB_MCP_CONNECTION_STRING`). Rotating those is the mitigation and is tracked
separately; it is not a reason to keep 220 lines of hook.

**No workflow reminder at session start or after compaction.** D3 removes
both. The superpowers chain must be carried in a project `CLAUDE.md` or
remembered. Long sessions lose worktree orientation after a compaction.

**No merged-branch auto-checkout.** After merging a branch on the remote, the
main checkout stays on the stale branch until checked out by hand.

**`~/.cache/claude` is no longer swept.** `commit-guard.sh` writes
`commit-scopes-*` cache files with a 60-second TTL. These are rewritten rather
than appended and amount to one small file per repo, so the growth is bounded.
`~/.claude/logs/` stops being pruned, but nothing writes to it once
`audit-log.sh` is gone; the existing 8.8 MB archive is left in place.

**No attention notification.** Ghostty OSC 777 and the tmux bell stop firing
on `AskUserQuestion` and `ExitPlanMode`.

**Higher token use.** `read-once.sh` suppressed re-reads of files already in
context. Removing it trades 702 lines of hook for some context churn.

## Out of scope

- The codex hook layer, including the known stub in its worktree guard's
  shell branch.
- Rotating the `zsh/.zshenv` credentials and the PAT in the `ops` origin URL.
- Deleting the 8.8 MB of existing audit logs in `~/.claude/logs/`.
- `docs/solutions/architecture-patterns/company-vs-personal-claude-config-layering-2026-06-19.md`,
  already queued in the `/ce-compound-refresh claude-code-config` sweep.
