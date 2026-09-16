# Personal Pi Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is the user's preselected execution workflow.

**Goal:** Configure personal Pi through dotfiles for interactive use in Herdr and explicit access to Factory's existing coordinator workflow.

**Architecture:** Keep the mise-managed Pi executable. Stow portable defaults and one manually activated Factory skill, keeping mutable settings and runtime state device-local. Install Herdr's native Pi integration through Herdr itself; Factory automation is outside this change.

**Tech Stack:** Pi 0.85.1 and Herdr 0.9.0 observed locally, GNU Stow, JSON, Markdown, mise, existing Factory CLI.

**Spec:** `docs/superpowers/specs/2026-09-16-pi-factory-herdr-design.md`, especially its narrowed Implementation scope.

## Global constraints

- This work configures Pi only; no Factory repository changes or worker adapters.
- Keep the existing mise installation and preserve current model/provider choices.
- The baseline adds no community extension packages.
- Keep Pi's mutable `settings.json` device-local rather than symlinking it to a tracked file.
- Use Stow with `--no-folding` to keep writable runtime directories on the device.
- The Factory skill uses `disable-model-invocation: true`.
- Workers continuing autonomously after direct input is future integration context.
- Authentication is performed by the user; never print or commit credentials.
- No live task creation, worker launches, approval, merge, or publication in setup tests.
- Work in the existing linked worktree. Stage explicit paths and make separate logical commits.
- Applying setup under the user's home requires the applicable filesystem approval;
  planning and repository file creation do not authorize bypassing that boundary.

## File map

| Path | Responsibility |
| --- | --- |
| `pi/.pi/agent/settings.defaults.json` | Small portable defaults; input to a documented merge, not Pi's active settings file. |
| `pi/.pi/agent/skills/factory/SKILL.md` | Explicit coordinator workflow using current Factory commands. |
| `.gitignore` | Defense against accidental tracking of Pi runtime files. |
| `docs/guides/pi.md` | Deployment, login/model selection, Herdr integration, verification, rollback, optional packages. |

Do not create a global Pi `AGENTS.md`, a custom extension, a new synchronization
service, or a Factory wrapper executable. Do not modify the existing Herdr
keybindings or install another Pi binary. No change to mise's `pi = "latest"`
is needed for this setup; record the validated version and recheck on upgrade.

## Task 1: Add the personal Pi package and deployment guide

**Files:** Create `pi/.pi/agent/settings.defaults.json` and `docs/guides/pi.md`;
modify `.gitignore`.

**Interface:** Deploys `~/.pi/agent/settings.defaults.json`. The active
`~/.pi/agent/settings.json` remains a real, locally writable file. Applying defaults
overrides exactly three documented leaf settings while preserving all other keys.

- [ ] Confirm the isolated checkout with `git status --short` and
  `git branch --show-current`. Read `CLAUDE.md` for Stow conventions. Check
  `command -v pi`, `pi --version`, and `herdr --version`; compare to the observed
  Pi 0.85.1/Herdr 0.9.0 baseline without initiating an update.
- [ ] Create the defaults file with exactly this content:

```json
{
  "defaultProjectTrust": "ask",
  "enableSkillCommands": true,
  "compaction": {
    "enabled": true
  }
}
```

- [ ] Add these anchored ignore rules. Explicitly track only intentional package
  content; do not import local sessions, downloaded extensions, or authentication.

```gitignore
# Pi runtime state stays device-local; portable defaults and our skill are tracked.
/pi/.pi/agent/*
!/pi/.pi/agent/settings.defaults.json
!/pi/.pi/agent/skills/
/pi/.pi/agent/skills/*
!/pi/.pi/agent/skills/factory/
```

- [ ] Start `docs/guides/pi.md` with the installation owner (mise), observed
  versions, file map, and explicit deployment instructions. Run Stow from the
  durable checkout, not a temporary worktree that may later be deleted. Use
  these commands only during authorized deployment, after inspecting existing
  paths for symlinks and conflicts:

```sh
mkdir -p "$HOME/.pi/agent/skills" "$HOME/.pi/agent/extensions"
stow --no-folding --simulate --verbose -t "$HOME" pi
stow --no-folding -t "$HOME" pi
```

  A conflict stops deployment; preserve the existing file and resolve it explicitly.
  Do not use `stow --adopt` or remove the user's existing configuration.

- [ ] Document applying defaults as a JSON deep merge: existing settings first,
  portable defaults second. Existing settings must be a JSON object; invalid
  input stops the update. Preserve `defaultProvider`, `defaultModel`, packages,
  resource paths, unknown keys, and additional compaction settings. Make a
  recoverable device-local backup before editing the real file. Do not log the
  full settings or read authentication files. Use the native file-edit mechanism
  when applying the actual merge, after required approval.

  The exact merge can be checked without writing the result to disk:

```sh
jq -s '.[0] * .[1]' existing-settings.json settings.defaults.json
```

  These two names in the example are fixture files, not permission to dump live
  settings. If active settings do not exist, initialize them from defaults.
  Reapplying defaults deliberately restores the three owned values; all other
  preferences remain local. No custom sync script is needed for three values.

- [ ] Validate JSON with `jq -e 'type == "object"'` against the tracked defaults.
  Check merge behavior using synthetic data, without reading personal settings:

```sh
jq -n --slurpfile defaults pi/.pi/agent/settings.defaults.json '
  {defaultProvider:"fixture", defaultModel:"fixture-model",
   packages:["fixture-package"], compaction:{enabled:false,keepRecentTokens:1234}}
  * $defaults[0]
  | .defaultProvider == "fixture"
    and .defaultModel == "fixture-model"
    and .packages == ["fixture-package"]
    and .compaction.keepRecentTokens == 1234
    and .compaction.enabled == true
    and .defaultProjectTrust == "ask"
    and .enableSkillCommands == true
' -e
```

  Expected: `true`, exit 0. Also check missing settings initialize from defaults
  and malformed/non-object settings are rejected by the documented procedure.
- [ ] Use a disposable directory from `mktemp -d` as the Stow target for a
  deployment check. Stow with `--no-folding`, confirm `.pi`, `agent`, and `skills`
  are real directories, and only intended files are links. Write any synthetic
  runtime fixtures with the file-edit tool. Confirm runtime files stay in the
  disposable target and do not appear as repository changes.
- [ ] Run `git check-ignore --no-index pi/.pi/agent/auth.json
  pi/.pi/agent/settings.json pi/.pi/agent/sessions/example.jsonl`; all should be
  ignored. Confirm the tracked defaults are not ignored. Run `git diff --check`.
- [ ] Inspect unstaged/staged diffs, then commit the three explicit paths with
  `chore: add portable personal Pi defaults`.

## Task 2: Add the explicitly activated Factory skill

**Files:** Create `pi/.pi/agent/skills/factory/SKILL.md`; extend `docs/guides/pi.md`.

**Interface:** `/skill:factory` activates the coordinator instructions for that
conversation. Normal Pi sessions and workers do not automatically select this
skill. Existing global skill discovery is not disabled or wholesale duplicated.

- [ ] Read the applicable skill-authoring instructions before implementation.
  Verify Pi supports `disable-model-invocation` and `/skill:name` on the installed
  version. The [official skill reference](https://pi.dev/docs/latest/skills)
  documents both.
- [ ] Create the skill with this complete initial content:

```markdown
---
name: factory
description: Coordinate work through benkim0414/factory's existing CLI and manual worker workflow when explicitly requested.
disable-model-invocation: true
---

# Factory coordinator

Use this workflow only when the user explicitly invokes it. Factory means
benkim0414/factory, not Factory.ai or Droid.

Resolve the local Factory checkout from the current directory or a path supplied
by the user. If neither identifies it, ask for its location. Read its README,
package.json, and repository instructions before running commands. Use its
documented runtime and working directory; do not invent an HTTP or MCP API.

Start by inspecting Factory status. Existing tickets, attempts, worktree paths,
and review packets are authoritative. Reconcile them before proposing another
attempt. Commands below are subcommands of the repository's documented Factory
CLI entry point; consult its current help for exact arguments:

- `status`: inspect current work.
- `ticket create`: record a requested task and acceptance criteria.
- `workflow start` with runtime `manual`: prepare an attempt/worktree and render
  its worker prompt.
- `pane register` and `attempt attach-pane`: record a manually selected worker.
- `attempt prompt`: obtain the current worker prompt.
- `attempt manual-result-template` and `attempt ingest-manual`: collect and
  validate real worker evidence.
- `workflow review`: obtain the current approval packet.

These manual commands do not launch or control Herdr terminals. Tell the user
when a step requires opening a worker pane or delivering a prompt manually.
Do not claim automatic dispatch, background supervision, or worker cancellation
unless the current checkout supplies and verifies that capability.

The user primarily talks to this coordinator but can directly instruct workers
in their own Herdr terminals. Workers continue autonomously after those messages.
Record material scope changes in Factory before reviewing results. Do not infer
that you observed direct messages or that the worker reported them automatically.

Present the current task, blocker, next action, and evidence concisely. A pane's
idle state is not evidence of task completion. Never invent checks, exit codes,
digests, or a worker result. Approval applies to the current evidence snapshot
and requires the user's explicit authority. Follow repository permissions for
merging, publishing, credentials, and destructive operations.

Keep implementation changes in the prepared worker worktree. Do not configure
another orchestrator or add a Pi subagent package as part of this workflow.
```

- [ ] Document the normal entry flow: open Pi in a Herdr pane, invoke
  `/skill:factory`, then identify the local Factory checkout. No automatic
  worker behavior is promised. Ordinary `pi` remains the personal coding agent.
- [ ] Add the package research decision to the guide: start without community
  extensions; consult the spec's cited shortlist for optional web/MCP/code tools.
  Install only for an identified requirement, review source, and pin exact
  versions. Herdr's native integration is the only extension added by this plan.
- [ ] Verify Stow exposes the skill at the expected path in the disposable target.
  In an isolated Pi config directory under `/tmp`, inspect startup discovery with
  startup network disabled. Do not request model inference just to validate file
  discovery. Confirm no missing-description/name warnings. In the eventual
  interactive smoke test, confirm `/skill:factory` exists and explicit invocation
  loads its text; a plain session does not announce itself as Factory coordinator.
- [ ] Review the prose against Factory's current README. Verify every named
  subcommand remains documented; never execute mutating commands as a prose test.
  Run `git diff --check`; commit these two explicit paths with
  `feat: add explicit Factory workflow to personal Pi`.

## Task 3: Document and verify native Herdr integration

**Files:** Extend `docs/guides/pi.md`. Deployment may create device-local
`~/.pi/agent/extensions/herdr-agent-state.ts` through Herdr's installer.

**Interface:** Herdr reports Pi's native agent state in its UI. This is status
integration, not a Factory worker backend or a completion/approval signal.

- [ ] Record the installed command behavior: `herdr integration status` currently
  reports Pi as not installed. `herdr integration install --help` lists `pi`.
  Check existing integration files before making changes; retain local customizations.
- [ ] Put the following per-device setup and verification commands in the guide:

```sh
herdr integration status
herdr integration install pi
herdr integration status
```

  Run the install only when applying the configuration with approval to write
  outside workspace roots. Keep the generated extension device-local and owned
  by Herdr; do not copy its implementation into this repository. Do not install
  integrations for other worker harnesses as part of Pi setup.
- [ ] Document authentication and model selection through Pi's interactive
  `/login`, `/model`, and `/settings` flows. Preserve the user's existing defaults.
  If already configured, do not log in again or choose a replacement provider.
  No secrets go in defaults or the Factory skill. Provider readiness requiring
  user interaction is reported separately from completion of repository artifacts.
- [ ] Restart Pi in a user-selected Herdr pane. Check extension load errors and
  confirm Herdr recognizes it as Pi. With the user's available provider, send one
  harmless conversational prompt and observe working-to-idle state. If the agent
  cannot access the interactive terminal, report this smoke test as unverified.
- [ ] Invoke `/skill:factory` and request only a status check against the user's
  Factory checkout. Confirm Pi follows the existing CLI and does not create a
  ticket or claim automatic worker control. If no checkout is available, leave
  this integration smoke test explicitly unverified; do not clone elsewhere or
  create Factory state as an implicit setup action.
- [ ] Add rollback instructions: unstow only the `pi` package with
  `stow --no-folding -D -t "$HOME" pi`; preserve login/session/local settings.
  Restore changed settings from the deployment backup only on explicit request.
  Use `herdr integration uninstall pi` only if undoing the newly installed native
  integration is requested. Never recursively delete `.pi`.
- [ ] Review links and commands, run `git diff --check`, and commit the guide with
  `docs(herdr): document personal Pi setup and verification`.

## Completion and review

- [ ] Review the resulting diff using Codex `/review` if available; if this
  environment cannot invoke it, state that limitation and perform the normal
  independent implementation review required by subagent-driven-development.
- [ ] Report the created configuration/skill/guide paths and meaningful checks.
  Separate repository verification from any unavailable live login/Herdr smoke test.
- [ ] Confirm no Factory source, worker automation, runtime credentials, global
  instruction files, or existing Herdr keybindings entered the diff.
- [ ] Do not push, open a PR, or merge as part of this plan without the requested
  shipping workflow. The current user request ends at a concrete configuration plan.

No new automated test suite is required for three settings and a Markdown skill.
The merge-preservation and temporary Stow checks validate the meaningful failure
modes; live integration requires the explicit smoke tests above.
