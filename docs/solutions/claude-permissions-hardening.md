---
module: claude
tags: [permissions, auto-mode, hooks, security]
problem_type: hardening
---

# Hardening Claude Code auto mode

## Problem

`defaultMode: "auto"` with a broad `allow` list lets risky shapes
through the background classifier. Regex `deny`/`ask` lists do not
cover shell-expanded paths, deny-list bypass forms, exfil pipelines,
or URL-based data leakage. Subagents inherit the parent's auto mode
and tool set, so permissive defaults amplify through delegation.

## Approach

Two layers:

1. **Tighten `settings.base.json`** -- deny vault export commands and
   the canonical absolute / `$HOME`-prefixed forms of credential
   paths; ask on a broad set of risky bash patterns, package
   publishers, GitHub write API, and MCP write wildcards.
2. **Add a semantic-policy hook** --
   `claude/.claude/hooks/permission-policy.sh` plus
   `claude/.claude/lib/permission-policy.sh`. Hook reads PreToolUse
   stdin, dispatches by tool name, calls the lib's pattern checks,
   and emits `permissionDecision: "ask"` JSON when any pattern
   fires.

## Key design choices

- **Ask, never deny, from the hook.** Deny stays in settings so the
  user has clear, version-controlled control over hard blocks.
  Semantic checks surface as prompts.
- **Library pattern matches existing `lib/commit-scope.sh`.** Pure
  bash, sourced not exec'd, individually testable via the
  `tests/<component>/{run,helpers,cases}` harness.
- **Input-path check for file edits, not canonical resolution.** The
  original plan canonicalized the file path before matching, which
  resolved live `~/.claude/CLAUDE.md` (symlink) into the dotfiles
  source and allowed it. That defeats the self-modification guard.
  Checking the input path directly catches edits through the live
  symlink while naturally allowing direct dotfiles source edits.
- **Disable via env var.** `CLAUDE_PERMISSION_POLICY=off`
  short-circuits the hook before stdin read and lib source, so a
  broken or moved lib never traps the user.
- **Fast-exit before lib source.** The hook's first `case` filters
  out tools we do not inspect (Read, Glob, Grep, Task, TodoWrite,
  etc.) -- ~70%+ of typical calls -- before paying the lib-source
  cost.

## Pitfalls

- Tilde-prefix glob patterns (`Bash(*~/.ssh/id_rsa)`) match the
  literal `~` substring only. Always pair with `$HOME` and absolute
  forms.
- `permissionDecision: "ask"` interaction with `allow` matches is not
  documented verbatim. Live smoke test in a fresh session is required
  after merge to confirm the hook surfaces an interactive prompt when
  the call also matches an `allow` entry.
- `readlink -f` is not universal on macOS; use a Python
  `os.path.realpath` fallback.
- Hook output protocol: `hookSpecificOutput.hookEventName` must be
  `"PreToolUse"` exactly. Using the wrong event name silently drops
  the decision.
- `claude-sync` is bound to `$DOTFILES_DIR` (defaults to the main
  checkout). Worktree-side edits to `settings.base.json` do not flow
  to `~/.claude/settings.json` until the worktree merges to main and
  `claude-sync` is run there.

## Files

- `claude/.claude/settings.base.json` -- deny + ask additions, hook
  registration.
- `claude/.claude/lib/permission-policy.sh` -- `check_bash`,
  `check_file_edit`, `check_web_fetch`, `canonical_path`.
- `claude/.claude/hooks/permission-policy.sh` -- PreToolUse
  dispatcher with env-var disable and fast-exit.
- `claude/.claude/tests/permission-policy/` -- runner + 13 cases.

## Known limitations

- **Bash secret-path check is substring, not semantic.** `cat /Users/ben/.ssh/...`,
  `ls /Users/ben/.ssh/`, and `rsync local /Users/ben/.ssh/safe/` all flag the
  same way -- the lib does not parse argument intent. The hook only asks
  (never denies), so the cost is prompt fatigue, not blocked work. Narrowing
  to credential filenames (`id_rsa`, `id_ed25519`, `credentials`, etc.) is a
  follow-up option if the prompts become noisy.
- **`rm -rf` bypass coverage is incomplete.** Uppercase R variants (`rm -RF`)
  and double-space (`rm  -rf`) are not caught by the current regex. The base
  `Bash(rm -rf *)` ask still catches the canonical form.
- **Pipe-to-shell check covers only shells.** `curl ... | python` and
  `wget ... | node` slip through. The more common shell-piping shape is
  caught.
- **Literal `$HOME` deny patterns don't shell-expand.** Entries like
  `Bash(*$HOME/.ssh/id_rsa*)` in `settings.base.json` only match when the
  command literally contains the substring `$HOME`. The lib's `check_bash`
  handles the expanded form. The redundancy is intentional belt-and-suspenders
  coverage across both layers.
- **`mcp__*__*invoke*` was deliberately dropped from the ask list.** It
  caught `mcp-compressor` dispatchers (atlassian, slack, qmd,
  sequential-thinking) on every call regardless of read/write intent,
  defeating the `mcp__*` allow. Per-server-tool ask entries in
  `.claude/settings.local.json` can gate specific dispatchers when stricter
  control is needed.
- **Settings-precedence interaction with hook `ask` is not verbatim-documented.**
  The Claude Code docs imply (but do not state explicitly) that hook
  `permissionDecision: ask` overrides a settings `allow` match. Live smoke
  test in a fresh session post-merge is the source of truth -- see the spec's
  "Smoke test" section for the procedure.

## Related

- `claude/.claude/lib/commit-scope.sh` and `hooks/git-safety.sh` --
  same lib + thin-hook pattern.
- `claude/.claude/hooks/worktree-guard.sh` -- complementary write
  enforcement; permission-policy adds semantic checks on top.
