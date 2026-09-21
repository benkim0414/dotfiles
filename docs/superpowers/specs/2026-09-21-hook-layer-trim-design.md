# Trim the hook layer to three enforcements

Date: 2026-09-21
Status: approved, not yet implemented
Branch: `worktree-git-guardrail-gaps`

## Goal

Reduce the Claude Code hook layer to exactly the three enforcements that are
worth enforcing mechanically -- worktree isolation, atomic commits, and
conventional commits -- and delete everything else.

Target: 4 hook registrations and ~715 lines, down from 14 registrations and
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
so. A trim that deleted `git-session-start.sh` as "just context" would leave
`worktree-guard.sh` registered, passing all 0 of its tests, and enforcing
nothing -- the failure shape already documented in
`docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`.

**Every hook is a bash 3.2 liability.** Per
`docs/solutions/conventions/hooks-run-under-macos-system-bash-3-2-2026-09-18.md`,
hooks run under `/bin/bash` 3.2.57 and bash 4 syntax fails *silently* -- a
PreToolUse hook that exits 0 without output is indistinguishable from a
permissive one. Three hooks were entirely dead this way before being found.
Fewer hooks is fewer places for that to happen.

## The two markers

The word "marker" names two unrelated files in this layer. They are decided
differently, so they are separated here before the decisions reference them.

| | Worktree marker | Attention marker |
| --- | --- | --- |
| Path | `~/.claude/session-worktrees/pending-<session-id>` | `~/.cache/claude/attention/<TMUX_PANE>` |
| Contents | empty | `pane_id`, `pane_label`, `notification_type`, `project`, `cwd` |
| Written by | `git-session-start.sh:157` | `notify.sh:112` |
| Read by | `worktree-guard.sh:15`, `:29` | `bin/.local/bin/tmux-attention{,-badge,-picker}` |
| Cleared by | `worktree-entered.sh:22` | `resolve-pr-refs.sh:27` |
| Means | "this session still owes a worktree" | "this tmux pane needs the user" |

The worktree marker is **kept** (D2). The attention marker is **deleted**
(D3).

## Decisions

### D1 -- The keep set is defined by the three enforcements

| File | Enforces |
| --- | --- |
| `hooks/commit-guard.sh` | atomic commits, conventional commit scope, no commit on main |
| `hooks/worktree-guard.sh` | worktree isolation (block half) |
| `hooks/arm-worktree-guard.sh` | worktree isolation (arm half) |
| `hooks/worktree-entered.sh` | worktree isolation (clear half) |
| `lib/commit-scope.sh` | the S1-S4 scope signals |
| `lib/session.sh` | session id, marker path, worktree detection, context emit |
| `lib/portability.sh` | `file_mtime`, `to_lower` |

Nothing else survives. Convenience, observability, and ergonomics are not
enforcement and are not worth a hook each.

### D2 -- The worktree marker stays; `git-session-start.sh` is split, not deleted

The guard is three parts and stays three parts: something arms the marker at
session start, `worktree-guard.sh` blocks while it exists, and
`worktree-entered.sh` clears it on `EnterWorktree`.

A markerless guard was considered and rejected. It would decide at edit time
from `git rev-parse --absolute-git-dir` against `--git-common-dir`, needing no
session state -- but it also blocks main-checkout edits permanently, where the
marker design deliberately stops blocking once a worktree has been entered
this session. That escape is worth the state file.

`git-session-start.sh` therefore cannot be deleted whole. It is replaced by
`hooks/arm-worktree-guard.sh`, ~30 lines, doing only what the guard needs:

```
in a git repo?            -> no: exit 0
bare repo?                -> yes: exit 0
linked worktree?          -> yes: exit 0
sweep pending-* older than 24h
touch pending-$SESSION_ID
emit "Main worktree (branch: X). Call EnterWorktree() before any edits."
```

The 24-hour sweep is kept because it is the only thing that stops
`~/.claude/session-worktrees/` accumulating one file per abandoned session.

Dropped from the original 169 lines: merged-branch fetch/checkout/pull, the
linked-worktree listing, the daily cache and audit-log GC, and the `MODE:
no-pr` chain (see D5).

`worktree-guard.sh` (50 lines) and `worktree-entered.sh` (24 lines) are
unchanged. `lib/session.sh` keeps `parse_session_id`, `pending_file`,
`check_worktree_pending`, and `STATE_DIR`, and so keeps its name.

### D3 -- The attention marker goes, and takes the tmux-attention feature with it

`notify.sh` (192) writes it, `lib/notify-pane.sh` (55) resolves the pane id
for it, and `resolve-pr-refs.sh` (115) clears it. All three are deleted.

**This is not a graceful degradation.** `tmux-attention` reads two source
directories, `~/.cache/claude/attention` and `~/.cache/codex/attention`, and
the codex one does not exist -- nothing writes it, and
`codex/.codex/config.base.toml` registers no notification hook. Removing
Claude's producer leaves the entire component with no input: the status-bar
badge reads empty forever and the picker always reports "No panes need
attention."

Consequently these become dead code and are deleted in the same change:

- `bin/.local/bin/tmux-attention`
- `bin/.local/bin/tmux-attention-badge`
- `bin/.local/bin/tmux-attention-picker`
- the `status-right` `#()` call and any key binding referencing them in
  `tmux/.config/tmux/tmux.conf`

`tmux-attention` is an established commit scope in this repo, so this is
retiring a named component, not sweeping a leftover. Keeping the three scripts
against a future Codex producer is the alternative; it means shipping a status
bar that is permanently blank.

### D4 -- No other SessionStart, PostCompact, UserPromptSubmit, or Notification hook

Beyond `arm-worktree-guard.sh`, nothing runs on a lifecycle event.
`restore-git-context.sh` (PostCompact), `resolve-pr-refs.sh`
(UserPromptSubmit), `notify.sh` (Notification), `read-once-gc.sh`
(SessionEnd), `audit-log.sh` and `worktree-exited.sh` (PostToolUse), and
`failure-recovery.sh` (PostToolUseFailure) are all deleted.

The worktree marker survives compaction on its own -- it is a file -- so
dropping `restore-git-context.sh` does not desynchronise the guard from what
Claude believes. It costs the re-injected orientation text only.

### D5 -- `no-pr` mode is deleted, not defaulted

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

This removes `workflow_no_pr` from `lib/session.sh` and the `NO_PR` inline
check from the hot path. It also removes the only branch in
`worktree-exited.sh`, which D4 deletes anyway.

### D6 -- Rename one file for accuracy

`hooks/git-safety.sh` becomes `hooks/commit-guard.sh`. It guards commits --
atomicity, scope, no commit on main -- and "safety" names nothing.

`worktree-guard.sh`, `worktree-entered.sh`, `lib/session.sh`,
`lib/commit-scope.sh`, and `lib/portability.sh` keep their names. The new
arming hook is `arm-worktree-guard.sh` so that grepping `worktree-guard`
finds both halves.

`lib/portability.sh` keeps `to_lower` despite having no caller after this
change. `CLAUDE.md` names it as *the* bash-3.2 lowercase escape hatch, and the
next hook that needs one should find it there rather than reinvent `${x,,}`.
`run_timeout` is dropped -- its only caller was `git-session-start.sh`.

### D7 -- The semantic permission hook goes; the glob lists stay

`permission-policy.sh` plus its lib is 220 lines catching shapes a glob cannot
express: shell-expanded secret paths (`$HOME/.ssh/*`), `rm -rf` deny-list
bypass forms (`\rm`, `command rm`, quoted, leading whitespace), curl/wget
piped to a shell, direct edits to live `~/.claude/`, shell-init and
persistence file edits, and suspicious WebFetch targets.

It is deleted. The 52 `permissions.deny` and 84 `permissions.ask` rules in
`settings.base.json` are **not** hooks and are untouched, including every
secret-file rule and `Bash(rm -rf *)`. The loss is bounded to the bypass forms
and shell-expanded paths. See Risks.

### D8 -- Fill the mattpocock gaps as rules, do not adopt the skill

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

### D9 -- The codex hook layer is untouched

`codex/.codex/config.base.toml` registers `atomic-commits.sh` and
`worktree-guard.sh` from `~/.codex/hooks/`, which are physically separate files
(9.9 KB and 53 KB) with no shared code. Nothing in this change reaches them.
The known stub in the codex guard's shell branch
(`docs/solutions/tooling-decisions/codex-worktree-guard-shell-branch-is-a-stub-2026-09-18.md`)
stays open.

## Changes

### 1. `hooks/git-session-start.sh` -> `hooks/arm-worktree-guard.sh`

169 -> ~30 lines. Per D2. Keeps the `worktree_kind` short-circuit, the 24-hour
`pending-*` sweep, the `touch`, and one `emit_context_with_msg` call. Drops
everything else.

### 2. `hooks/git-safety.sh` -> `hooks/commit-guard.sh` -- rename and trim

296 -> ~270 lines. Per D5 and D6: remove the `NO_PR` variable, its inline
`CLAUDE_GIT_WORKFLOW` read, and the `"$NO_PR" != "true" &&` condition from
both the merge/rebase/cherry-pick guard and the push guard. No change to the
`git add`, `git commit -a`, commit-on-main, or scope logic.

### 3. `hooks/worktree-guard.sh`, `hooks/worktree-entered.sh` -- unchanged

50 and 24 lines. Per D2. Only their `source` paths are checked, and
`lib/session.sh` keeps its name, so nothing moves.

### 4. `lib/session.sh` -- trim

143 -> ~120 lines. Keep `emit_context`, `emit_context_with_msg`,
`parse_session_id`, `pending_file`, `check_worktree_pending`, `cwd_repo_hint`,
`worktree_kind`, `STATE_DIR`. Delete `workflow_no_pr` (D5).

### 5. `lib/portability.sh` -- trim

41 -> ~25 lines. Keep `file_mtime` and `to_lower`; delete `run_timeout`.

### 6. `claude/.claude/settings.base.json` -- 14 registrations to 4

```
SessionStart                          bash $HOME/.claude/hooks/arm-worktree-guard.sh
PreToolUse   Bash                     bash $HOME/.claude/hooks/commit-guard.sh
PreToolUse   Write|Edit|NotebookEdit  bash $HOME/.claude/hooks/worktree-guard.sh
PostToolUse  EnterWorktree            bash $HOME/.claude/hooks/worktree-entered.sh
```

Removed events entirely: `UserPromptSubmit`, `PostToolUseFailure`,
`PostCompact`, `Notification`, `SessionEnd`. `permissions`, `env`,
`enabledPlugins`, `extraKnownMarketplaces`, and `outputStyle` are untouched.

### 7. Delete 9 hooks and 3 libs -- 1,525 lines

| File | Lines |
| --- | --- |
| `hooks/read-once.sh` | 539 |
| `hooks/notify.sh` | 192 |
| `lib/permission-policy.sh` | 162 |
| `hooks/resolve-pr-refs.sh` | 115 |
| `lib/read-once-cache.sh` | 114 |
| `hooks/failure-recovery.sh` | 85 |
| `hooks/audit-log.sh` | 80 |
| `hooks/permission-policy.sh` | 58 |
| `hooks/restore-git-context.sh` | 57 |
| `lib/notify-pane.sh` | 55 |
| `hooks/read-once-gc.sh` | 49 |
| `hooks/worktree-exited.sh` | 19 |

Plus `git-session-start.sh` (169), replaced rather than removed -- change 1.

### 8. Delete the tmux-attention component

Per D3: `bin/.local/bin/tmux-attention`, `tmux-attention-badge`, and
`tmux-attention-picker`, plus all four references in
`tmux/.config/tmux/tmux.conf`:

```
53: bind-key a run-shell "tmux-attention"
54: bind-key A display-popup -E -w 80% -h 80% "tmux-attention-picker"
78: set -g status-right "#[fg=#f38ba8]#(tmux-attention-badge)#[default] "
85: set-hook -g pane-focus-in "run-shell -b 'tmux-attention --clear-focused'"
```

Line 78 must be **replaced with `set -g status-right ""`**, not deleted. It is
the base assignment; lines 79-80 are `set -ag` appends for the catppuccin
session and host segments. Deleting line 78 makes the first append land on
tmux's built-in default `status-right` (pane title and clock), which would
appear in the status bar as a visible regression rather than a removal.

### 9. Tests

Delete `tests/read-once/` (19 cases), `tests/permission-policy/` (13 cases),
`tests/notify-pane/` (6 cases).

Trim `tests/session-lib/` (7 cases): drop `30-workflow-no-pr-set.sh` and
`31-workflow-no-pr-unset.sh`. Keep the name -- the lib keeps its name.

Keep `tests/commit-scope/` (32 cases) and `tests/bash-portability/`, updating
path references to `commit-guard.sh`.

**Add a `tests/worktree-guard/` suite.** The guard has no test of its own
today, and its failure mode is silent permissiveness. It must assert the
*block* branch, not only the allow branches -- see V1.

The three non-hook suites (`output-style/`, `theme-contrast/`,
`mcp-permission-overlay/`) are untouched.

### 10. `claude/.claude/hooks/README.md` -- rewrite

116 lines documenting 12 hooks and 5 libs. Rewrite for 4 hooks and 3 libs.

### 11. `CLAUDE.md` (dotfiles project file) -- update stale passages

At minimum: the "Hook shell constraint (bash 3.2)" section (it cites "16 of
them across `settings.base.json` and `codex/.codex/config.base.toml`"); the
entire "Semantic policy hook" section; the `git-safety.sh` reference in
"Commit scope"; and "Hook-enforced." in the staging rule. Grep for
`git-safety`, `permission-policy`, `read-once`, `git-session-start`, and
`tmux-attention` before declaring this done.

## Verification

### V1 -- The worktree guard blocks, and is seen to block (blocking)

A guard that cannot enforce must not look like one that can. Assert every
branch with the hook invoked the way its config invokes it (`bash <path>`,
not the shebang):

1. Marker present, `file_path` inside the repo, main checkout -> **exit 2**.
2. Marker present, linked worktree -> exit 0, and the stale marker is removed
   (the self-healing branch in `check_worktree_pending`).
3. Marker present, `file_path` outside the repo working tree -> exit 0.
4. No marker -> exit 0.

Case 1 is the one that matters. A suite containing only 2-4 passes against a
guard that has been deleted.

### V2 -- The arm hook actually arms

Pipe a SessionStart payload with a known session id and assert
`~/.claude/session-worktrees/pending-<id>` exists afterwards in a main
checkout, and does **not** exist when run from a linked worktree. This is the
coupling that D2 preserves; it is currently asserted by nothing.

### V3 -- The commit guard still enforces all three

Pipe representative payloads to `commit-guard.sh` and assert exit 2 for:
`git add -A`, `git add .`, `git add --all`, `git add --update`,
`git commit -a`, `git commit -am "x"`, and `git commit` while HEAD is main.
Assert exit 0 for `git merge <branch>` on main and `git push origin main`
(D5 removed those gates).

### V4 -- Suites pass

Run each as its own plain command (the worktree-isolation guard refuses loops
and heredocs):

```sh
cd claude/.claude/tests/commit-scope && bash run.sh
cd claude/.claude/tests/worktree-guard && bash run.sh
cd claude/.claude/tests/session-lib && bash run.sh
cd claude/.claude/tests/bash-portability && bash run.sh
cd claude/.claude/tests/mcp-permission-overlay && bash run.sh
cd claude/.claude/tests/output-style && bash run.sh
cd claude/.claude/tests/theme-contrast && bash run.sh
```

`bin/tests/stow-hygiene/run.sh` must also pass after change 8 touches `bin/`.

### V5 -- No dangling references to deleted files

```sh
grep -rn 'git-safety\|permission-policy\|read-once\|notify-pane\|notify\.sh\|git-session-start\|resolve-pr-refs\|failure-recovery\|restore-git-context\|audit-log\|worktree-exited\|workflow_no_pr\|tmux-attention\|claude/attention' \
  --include='*.sh' --include='*.json' --include='*.conf' --include='*.md' \
  claude/ bin/ tmux/ CLAUDE.md
```

Frozen plan and spec documents under `docs/superpowers/` are expected hits and
are left alone. Anything under `claude/`, `bin/`, `tmux/`, or `CLAUDE.md` is a
real dangling pointer and must be fixed -- this is the bug the previous branch
shipped and had to correct.

### V6 -- No dangling symlinks after restow

Deleting and renaming stowed files leaves dead links in `~/.claude/hooks/`,
`~/.claude/lib/`, and `~/.local/bin/`, exactly as `CLAUDE.company.md` did.
**After merge, from the main checkout only** (never from a worktree --
`CLAUDE.md` > Stow gotchas):

```sh
cd ~/workspace/dotfiles && stow -t ~ -R claude && stow -t ~ -R bin && stow -t ~ -R tmux
find ~/.claude/hooks ~/.claude/lib ~/.local/bin -type l ! -exec test -e {} \; -print
```

The `find` must print nothing. Then run `claude-sync` to regenerate
`~/.claude/settings.json` and confirm with `jq '.hooks' ~/.claude/settings.json`
that four registrations remain.

### V7 -- bash 3.2

Every surviving hook and lib parses under `/bin/bash` explicitly:

```sh
/bin/bash -n claude/.claude/hooks/commit-guard.sh
/bin/bash -n claude/.claude/hooks/worktree-guard.sh
/bin/bash -n claude/.claude/hooks/arm-worktree-guard.sh
/bin/bash -n claude/.claude/hooks/worktree-entered.sh
```

A green run under Homebrew bash 5 proves nothing. `tests/bash-portability/`
covers the syntax scan.

## Risks

**Loss of the semantic permission layer while live secrets are unrotated.**
D7 removes the check for shell-expanded secret paths (`$HOME/.ssh/*`,
`/Users/ben/.ssh/*`) and the `rm -rf` bypass forms (`\rm`, `command rm`). The
literal-path `deny` globs stay, so the common forms are still blocked. This
lands while `zsh/.zshenv` holds four unrotated live credentials
(`GITHUB_ACCESS_TOKEN`, `SENTRY_AUTH_TOKEN`, `ARGOCD_API_TOKEN`,
`MDB_MCP_CONNECTION_STRING`). Rotating those is the mitigation and is tracked
separately; it is not a reason to keep 220 lines of hook.

**Retiring tmux-attention is a one-way door in practice.** D3 deletes a
working, named component. Restoring it means rewriting a notification hook,
not reverting a config line. The three scripts remain in git history.

**No workflow reminder beyond the arming line.** `arm-worktree-guard.sh`
emits "Call EnterWorktree() before any edits" and nothing else. The
superpowers chain and `MODE: no-pr` must be carried in a project `CLAUDE.md`
or remembered, and long sessions lose orientation after a compaction.

**No merged-branch auto-checkout.** After merging a branch on the remote, the
main checkout stays on the stale branch until checked out by hand.

**`~/.cache/claude` is no longer swept.** `commit-guard.sh` writes
`commit-scopes-*` files with a 60-second TTL. These are rewritten rather than
appended and amount to one small file per repo, so growth is bounded.
`~/.claude/logs/` stops being pruned, but nothing writes to it once
`audit-log.sh` is gone; the existing 8.8 MB archive is left in place.

**Higher token use.** `read-once.sh` suppressed re-reads of files already in
context. Removing it trades 702 lines of hook for some context churn.

## Out of scope

- The codex hook layer, including the known stub in its worktree guard's
  shell branch.
- Rotating the `zsh/.zshenv` credentials and the PAT in the `ops` origin URL.
- Deleting the 8.8 MB of existing audit logs in `~/.claude/logs/`.
- `docs/solutions/architecture-patterns/company-vs-personal-claude-config-layering-2026-06-19.md`,
  already queued in the `/ce-compound-refresh claude-code-config` sweep.
