# Claude Code Permissions Hardening (Auto Mode)

Status: Design approved, ready for implementation plan.
Date: 2026-05-22
Worktree: `worktree-claude-permissions-hardening`

## Problem

`claude/.claude/settings.base.json` uses `defaultMode: "auto"` with a broad
`allow` list (`Bash`, `Write`, `Edit`, `MultiEdit`, `WebFetch`, `WebSearch`,
`Agent`, `mcp__*`). Auto mode skips prompts for allowed tools and routes
unmatched calls through a background classifier. The current `deny` list
covers credential file reads (`~/.ssh`, `~/.aws/credentials`, `.env`, etc.)
and the `ask` list covers a short list of destructive bash commands.

Audit identified several gaps:

1. **Self-modification.** `Write`/`Edit` to `~/.claude/{settings*.json,
   hooks/**, lib/**, CLAUDE.md}` is not denied. Claude can rewrite its
   own hooks and bypass the entire safety net.
2. **Bash classifier reliance.** `Bash` is fully allowed; many risky
   patterns are not in `ask`: `curl/wget -X POST|PUT|DELETE`, `chmod`,
   `chown`, `dd`, `find -delete`, `find -exec rm`, `git config`,
   `git filter-*`, `git rebase -i`, `git push origin main`, shell
   redirects (`>`) overwriting system files, package publishers
   (`npm publish`, `cargo publish`).
3. **`mcp__*` blanket allow in base alone.** Write-shape MCP tools
   (Slack post, Jira/Linear/Notion mutations) are auto-allowed by base.
   The work-machine overlay (`claude-skills/settings.overlay.json`) adds
   ask patterns; machines using base only inherit blanket allow.
4. **`WebFetch` / `WebSearch` unrestricted.** Exfiltration channel
   (sensitive content packed into URL query params) and
   prompt-injection ingress vector.
5. **Tilde-prefix deny patterns are fragile.** `Bash(*~/.ssh/id_rsa)`
   matches the literal `~` substring. `$HOME/.ssh/id_rsa`,
   `${HOME}/.ssh/id_rsa`, and `/Users/ben/.ssh/id_rsa` all bypass.
6. **Vault export bypass.** `bw export`, `op document get`,
   `op item edit`, `op vault export` are not denied (only `bw get`,
   `bw list`, `op read`, `op item get` are).
7. **Bash deny-list metacharacter bypass.** `Bash(rm -rf *)` does not
   match `\rm -rf /tmp/x`, `command rm -rf /tmp/x`, leading whitespace,
   or quoted command names.

Auto mode amplifies these gaps: unmatched risky calls go to the
background classifier whose verdict cannot be inspected pre-execution.

## Scope

Harden `claude/.claude/settings.base.json` (applies to every machine
stowing this dotfiles) AND add a PreToolUse permission-policy hook that
catches semantic patterns regex matchers cannot express.

Out of scope:

- Auto-mode classifier reliability itself (Anthropic-side).
- Subagent permission inheritance — verified via Claude Code docs:
  subagents inherit parent permission context and tool set; parent
  auto mode forces subagent auto mode; PreToolUse hooks fire for all
  tool calls including subagent calls. Hardening applies to subagents
  automatically.
- Symlink-farm traversal beyond `readlink -f` (canonical path resolution).
- `WebFetch`/`WebSearch` outright restriction — kept in `allow` with
  hook-based flagging. Follow-up if too noisy.

## Design

### 1. `settings.base.json` changes

**Add to `deny`** (block outright; hook is for nuanced cases):

```jsonc
// credential vault exfil
"Bash(bw export*)",
"Bash(bw export --*)",
"Bash(op document get *)",
"Bash(op item edit *)",
"Bash(op vault export*)",

// canonicalized secret paths (complement existing tilde patterns)
"Bash(*$HOME/.ssh/id_rsa*)",
"Bash(*$HOME/.ssh/id_ed25519*)",
"Bash(*$HOME/.ssh/id_ecdsa*)",
"Bash(*$HOME/.aws/credentials*)",
"Bash(*$HOME/.claude/.credentials*)",
"Bash(*/Users/ben/.ssh/id_rsa*)",
"Bash(*/Users/ben/.ssh/id_ed25519*)",
"Bash(*/Users/ben/.aws/credentials*)",
"Bash(*/Users/ben/.claude/.credentials*)"
```

**Add to `ask`**:

```jsonc
// network writes / exfil shapes
"Bash(curl * -X POST*)", "Bash(curl * -X PUT*)",
"Bash(curl * -X DELETE*)", "Bash(curl * -X PATCH*)",
"Bash(curl * --request POST*)", "Bash(curl * --request PUT*)",
"Bash(curl * --request DELETE*)",
"Bash(curl * -d *)", "Bash(curl * --data*)",
"Bash(wget --post-*)",

// perm / ownership / disk
"Bash(chmod *)", "Bash(chown *)", "Bash(dd *)", "Bash(mkfs*)",
"Bash(find * -delete*)", "Bash(find * -exec rm*)",

// git history rewrites + remote pushes to protected branches
"Bash(git config *)",
"Bash(git filter-repo*)", "Bash(git filter-branch*)",
"Bash(git rebase -i*)",
"Bash(git push origin main*)", "Bash(git push * main*)",
"Bash(git push * master*)",

// package publishers
"Bash(npm publish*)", "Bash(cargo publish*)",
"Bash(twine upload*)", "Bash(gem push*)",

// GitHub write API
"Bash(gh api * -X POST*)", "Bash(gh api * -X PUT*)",
"Bash(gh api * -X PATCH*)",
"Bash(gh api --method POST*)", "Bash(gh api --method PUT*)",
"Bash(gh api --method PATCH*)",

// MCP wildcard writes (moved from overlay -> base)
"mcp__*__*create*", "mcp__*__*delete*", "mcp__*__*remove*",
"mcp__*__*update*", "mcp__*__*edit*", "mcp__*__*add*",
"mcp__*__*transition*", "mcp__*__*sync*", "mcp__*__*deploy*",
"mcp__*__*apply*", "mcp__*__*invoke*", "mcp__*__*patch*",
"mcp__*__*write*"
```

`WebFetch` / `WebSearch` stay in `allow`; the hook flags suspicious
shapes (large query strings, exfil-shaped payloads, suspect hosts).

### 2. Permission-policy hook + lib

Follows the existing `lib/commit-scope.sh` + `hooks/git-safety.sh`
convention.

**Files**

- `claude/.claude/lib/permission-policy.sh` — pattern matchers and
  helper functions. Each pattern returns the trigger reason on match,
  empty string on no match. Library is sourced (not exec'd) so it can
  be unit-tested with shell test harness.
- `claude/.claude/hooks/permission-policy.sh` — thin PreToolUse entry
  point. Reads JSON from stdin, sources the lib, dispatches by
  `tool_name`, emits `permissionDecision: ask` JSON when any matcher
  fires, exits 0 silently otherwise.
- `claude/.claude/tests/permission-policy-test.sh` — bash test harness
  exercising positive cases (must `ask`), negative cases (must stay
  silent), and bypass attempts (must `ask`).

**Settings registration** (new entry in `hooks.PreToolUse`):

```jsonc
{
  "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch",
  "hooks": [
    {
      "type": "command",
      "command": "bash $HOME/.claude/hooks/permission-policy.sh"
    }
  ]
}
```

**Hook output protocol** (Claude Code PreToolUse JSON):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "<short reason for user>"
  }
}
```

Exit 0 silent = allow (no decision override). Hook never emits `deny`;
always `ask` per the chosen policy.

**Dispatch table**

| Tool | Pattern | Trigger reason |
|------|---------|----------------|
| `Bash` | Shell-expanded secret path (`$HOME/.ssh/...`, `${HOME}/.ssh/...`, `/Users/ben/.ssh/...`, `/Users/ben/.aws/credentials`, etc.) that the regex `deny` patterns miss | Bash command references secret path via non-tilde form |
| `Bash` | Bypass attempts: `\rm`, `command rm`, `'rm'`, `"rm"`, leading whitespace before `rm -rf` | Possible deny-list bypass for `rm -rf` |
| `Bash` | Shell metachar chains hiding writes: `;\s*rm`, `&&\s*rm -rf`, `\| sh`, `\| bash`, `curl.*\| sh`, `wget -O-.*\| bash` | Piped or chained execution of fetched content |
| `Bash` | Exfil pipeline: `base64.*\|.*curl`, `base64.*\|.*wget`, `tar.*\|.*curl`, `gpg.*\|.*curl` | Possible data exfiltration pipeline |
| `Write` / `Edit` / `MultiEdit` / `NotebookEdit` | canonical path under `/Users/ben/.claude/` AND NOT under any worktree of `/Users/ben/workspace/dotfiles/` | Edit to live `~/.claude/` outside dotfiles repo — edit base settings or stowed source instead |
| `Write` / `Edit` / `MultiEdit` / `NotebookEdit` | canonical path matches `*/hooks/*.sh`, `*/lib/*.sh`, `settings*.json`, `CLAUDE.md`, `statusline.sh` AND outside current worktree | Edit to safety-critical claude config outside current worktree |
| `Write` / `Edit` / `MultiEdit` | path matches `~/.zshrc`, `~/.bashrc`, `~/.gitconfig`, `~/Library/LaunchAgents/*`, `~/.config/launchd/*`, system `crontab` | Shell init / persistence file edit |
| `WebFetch` | URL host in suspect list: `requestbin.com`, `webhook.site`, `pipedream.net`, `*.ngrok.io`, `*.trycloudflare.com`, paste/gist with `raw=` query | Fetch to dynamic-DNS / paste / webhook host |
| `WebFetch` | URL query string > 500 chars OR contains base64-shaped payload `[A-Za-z0-9+/]{120,}={0,2}` | Fetch URL carries large query payload (possible exfil) |
| `WebFetch` | URL contains `$HOME`, `/Users/ben/`, or known secret-path substrings | Fetch URL references local filesystem path |

**Path canonicalization**

`readlink -f "$path"` on Linux. macOS without coreutils falls back to
`python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))"`. Then
compare with `/Users/ben/.claude/` prefix and
`/Users/ben/workspace/dotfiles/` prefix.

**Worktree awareness**

Hook reads `$CLAUDE_WORKTREE_ROOT` (set by `worktree-entered.sh`) to
identify the in-scope workspace path. Files whose canonical path lives
under `$CLAUDE_WORKTREE_ROOT` skip the safety-critical-outside-worktree
check. If `$CLAUDE_WORKTREE_ROOT` is unset, the hook treats the main
worktree (`/Users/ben/workspace/dotfiles`) as in scope by default.

**Audit logging**

Every `ask` decision is captured by the existing `audit-log.sh`
PostToolUse hook. No new logging code in the policy hook itself.

### 3. claude-sync overlay interaction

`claude-sync` deep-merges: arrays concatenate then deduplicate; objects
overlay-wins. Moving the MCP write wildcards (`mcp__*__*create*` etc.)
from `claude-skills/settings.overlay.json` -> base is safe — dedupe
removes the duplicate. Follow-up commit in claude-skills should delete
the now-duplicate block from the overlay to prevent drift, but that is
not in scope for the current dotfiles change.

### 4. Rollback / disable

- Env var `CLAUDE_PERMISSION_POLICY=off` short-circuits the hook
  (returns exit 0 immediately). Lets the user test the rest of the
  system without the new hook in the path.
- Per-repo override: `.claude/settings.local.json` can add allow rules,
  but PreToolUse hooks always run regardless of allow-list match. To
  bypass the hook, use the env var.
- Worst-case rollback: `git revert` the merge commit, run `claude-sync`,
  restart session.

### 5. Verification

- `bash claude/.claude/tests/permission-policy-test.sh` — runs locally
  and exercises:
  - positive cases (each pattern in dispatch table must trigger `ask`)
  - negative cases (regular bash, regular edits inside worktree,
    regular WebFetch to `github.com` docs must stay silent)
  - bypass attempts (`\rm -rf /tmp/x`, `command rm -rf /tmp/x`,
    `cat $HOME/.ssh/id_rsa`)
- Manual: feed synthetic PreToolUse JSON into the hook via stdin,
  assert stdout JSON shape and content.
- Live smoke test in fresh session post-merge: try one positive case
  per category (e.g., `cat /Users/ben/.ssh/id_rsa`, `gh api -X POST
  repos/x/y/issues`, fetch to webhook.site URL). Expect ask prompt with
  the matching reason.

## File layout

```
claude/.claude/
├── CLAUDE.md                       # unchanged
├── settings.base.json              # edited (deny+ask additions)
├── hooks/
│   ├── permission-policy.sh        # NEW
│   └── ... (existing hooks)
├── lib/
│   ├── commit-scope.sh             # unchanged
│   └── permission-policy.sh        # NEW
└── tests/
    └── permission-policy-test.sh   # NEW
```

## Risks and trade-offs

- **Prompt fatigue.** New `ask` entries plus the hook will add prompts
  in day-to-day flow. The `ask` patterns target genuinely risky shapes
  (network writes, perm changes, history rewrites, package publishes).
  Mitigated by env-var disable and per-repo local allow lists. If a
  specific pattern becomes too noisy in practice, demote it to `allow`
  or move it into the hook's allowlist of known-safe shapes.
- **macOS `readlink -f` portability.** Older macOS lacks GNU coreutils.
  Python fallback covers that; tests run both paths.
- **Hook execution cost.** PreToolUse runs per tool call. Bash hook
  with regex matchers is sub-millisecond — negligible vs. tool latency.
- **Pattern coverage gaps.** Regex cannot cover every bash shape.
  Combined with the existing allow/deny lists and the auto-mode
  classifier, the hook is defense-in-depth, not a complete sandbox.
- **MCP wildcard moves break overlay-only machines.** Once base
  contains `mcp__*__*create*` etc., a machine with overlay still
  carrying the same entries is fine (dedupe), but a machine with a
  custom overlay that *allows* one of those wildcards is silently
  shadowed by the base `ask`. Acceptable — affirmative allow in the
  overlay still wins via array merge if the same pattern appears in
  both `allow` and `ask` (Claude Code applies `deny` -> `ask` -> `allow`
  precedence; need to verify exact precedence in implementation phase).

## Open questions for implementation phase

- Exact Claude Code precedence between `allow`, `ask`, `deny` when the
  same glob appears in two lists — confirm before assuming the MCP move
  is safely shadowed.
- Whether the PreToolUse hook's `permissionDecision: ask` output
  actually surfaces an interactive prompt under `defaultMode: auto`
  (versus being treated as advisory). Need to verify with a live test
  during plan execution.

## Verified semantics (2026-05-22)

Source: docs.claude.com pages fetched 2026-05-22 via
`mcp__plugin_context-mode_context-mode__ctx_fetch_and_index`:

- `https://docs.claude.com/en/docs/claude-code/hooks` (titled "Hooks
  reference"; the `/hooks-reference` slug returns 404)
- `https://docs.claude.com/en/docs/claude-code/settings`
- `https://docs.claude.com/en/docs/claude-code/permissions`
- `https://docs.claude.com/en/docs/claude-code/permission-modes`
- `https://docs.claude.com/en/docs/claude-code/auto-mode-config`

### Hook permissionDecision precedence

- `permissionDecision: "ask"` from PreToolUse: surfaces an interactive
  confirm prompt. The docs do **not** explicitly state what happens
  when the same call also matches a settings `allow` rule; the only
  directional statement is the inverse, that settings deny/ask still
  bind regardless of hook return. See "Gate decision" below.
- Overrides `defaultMode: "auto"`: not explicitly stated. By
  implication (hooks describe "the permission prompt displayed to the
  user" with `[User]`/`[Project]`/`[Plugin]`/`[Local]` labels and no
  carve-out for auto mode), an `ask` hook decision should surface a
  prompt. Needs live smoke test in implementation phase.
- Multiple PreToolUse hooks for same call: most-restrictive wins, fixed
  precedence `deny > defer > ask > allow`. So `git-safety.sh` returning
  empty alongside `permission-policy.sh` returning `ask` resolves to
  `ask`.
- `permissionDecision: "deny"`: highest precedence among hook returns;
  "prevents the tool call".

Exact wording from the hooks page:

> `permissionDecision` — `"allow"` skips the permission prompt.
> `"deny"` prevents the tool call. `"ask"` prompts the user to
> confirm. `"defer"` exits gracefully so the tool can be resumed
> later. Deny and ask rules are still evaluated regardless of what the
> hook returns.

> When multiple PreToolUse hooks return different decisions, precedence
> is `deny > defer > ask > allow`. When a hook returns `"ask"`, the
> permission prompt displayed to the user includes a label identifying
> where the hook came from: for example, `[User]`, `[Project]`,
> `[Plugin]`, or `[Local]`.

### Settings precedence

Order (highest to lowest): **`deny` -> `ask` -> `allow`**. First
matching rule wins. From the permissions page:

> Rules are evaluated in order: **deny -> ask -> allow**. The first
> matching rule wins, so deny rules always take precedence.

Implication for the design: if the same glob appears in both `allow`
and `ask`, the `ask` rule wins. Moving the MCP write wildcards
(`mcp__*__*create*` etc.) into base `ask` correctly shadows any
remaining `mcp__*` entry in an overlay's `allow`.

### Auto-mode classifier vs hooks

The auto-mode classifier runs **after** the settings allow/deny check.
From the permission-modes page, "How the classifier evaluates
actions":

> Each action goes through a fixed decision order. The first matching
> step wins:
> 1. Actions matching your allow or deny rules resolve immediately
> 2. Read-only actions and file edits in your working directory are
>    auto-approved, except writes to protected paths
> 3. Everything else goes to the classifier

The docs do not explicitly slot PreToolUse hooks into this list. The
hooks page treats hook output as a parallel decision channel
(`permissionDecision` produces "the permission prompt displayed to the
user"). PreToolUse runs **before a tool call executes** and "can block
it" — language consistent with hooks executing before the settings
allow/deny resolution, not after. But the docs do not state this
ordering in one sentence.

Also from the permission-modes page, relevant to broad `Bash` allow:

> On entering auto mode, broad allow rules that grant arbitrary code
> execution are dropped: Blanket `Bash(*)` or `PowerShell(*)`;
> Wildcarded interpreters like `Bash(python*)`; Package-manager run
> commands; Agent allow rules. Narrow rules like `Bash(npm test)`
> carry over.

So `Bash` as a bare allow entry is dropped under auto mode. The
classifier guards the unmatched space. This reduces but does not
eliminate the value of the hook: narrow allow rules still bypass the
classifier, and the hook catches semantic patterns the classifier may
miss (canonicalised secret paths, exfil pipelines, claude-self-edit
shapes outside the worktree).

### Gate decision

The docs are **clear** on three of the four sub-questions and
**ambiguous** on the fourth (hook `ask` versus settings `allow` for
the same call). Reading the available statements together — hooks are
described as producing prompts with source labels, no carve-out for
auto mode, deny/ask settings still bind regardless of hook return —
the most defensible interpretation is:

- Settings `allow` does **not** shadow a hook's `ask` return; the hook
  is a parallel decision channel and the most-restrictive outcome
  wins.

This interpretation matches the documented design intent (hooks give
"richer control" than settings rules) but is not stated verbatim.

**Decision: PROCEED to plan, with a hard gate in the implementation
plan.** First implementation step after the hook is wired up must be
a live smoke test: a Bash command matching both an `allow` entry
(e.g., `Bash`) and the hook's `ask` pattern (e.g., `cat
$HOME/.ssh/id_rsa`) must produce an interactive prompt. If it does
not — i.e. the allow shadows the hook — the design has to be revised
to move risky shapes into settings `ask`/`deny` exclusively and the
hook becomes advisory only.

## Next step

Hand off to `superpowers:writing-plans` to produce the step-by-step
implementation plan covering: settings.base.json edits, lib + hook
scaffold, test harness, claude-sync regeneration, live smoke test, and
the docs/solutions/ entry for the eventual `ce-compound` capture.
