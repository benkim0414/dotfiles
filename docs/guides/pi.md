# Personal Pi

Installation owner: `mise` (the `pi` installation and its version are managed
by mise). Observed on 2026-09-16: Pi `0.85.1`; Herdr `0.9.0`. Do not initiate
an update as part of setup.

## File map

- `pi/.pi/agent/settings.defaults.json` contains the tracked portable defaults.
  Pi does not read this filename automatically.
- `pi/.pi/agent/settings.json` is the Git-ignored active configuration, linked by
  Stow to `~/.pi/agent/settings.json`. Pi reads and writes this file. Preserve
  device-local preferences and package declarations when applying defaults.
- This package installs no Pi skills. Downloaded extensions, sessions, and
  authentication remain device-local.

## Package policy

Start with Pi core; do not install community
extensions by default. The design shortlist in
[`docs/superpowers/specs/2026-09-16-pi-factory-herdr-design.md`](../superpowers/specs/2026-09-16-pi-factory-herdr-design.md)
lists optional web, MCP, question, todo, lens, background-task, subagent, and
permission tools. Consult it only when an identified requirement calls for one.
Before installing, review source, maintenance, license, dependencies, and
compatibility, then pin an exact npm version or immutable Git ref. Herdr's
native Pi integration is the only extension added by this plan.

## Connect Pi status to Herdr

Herdr's native Pi integration reports Pi's agent state in the Herdr UI. It is
status integration only: it is not a Factory worker backend and does not send
completion or approval signals.

Before installing, inspect the existing device-local extensions and integration
status. Keep any local customizations. During an authorized per-device setup,
run only the following commands for this integration:

```sh
herdr integration status
herdr integration install pi
herdr integration status
```

Device-specific observation (2026-09-16): before this device's installation,
`herdr integration status` reported Pi as not installed, and `herdr integration
install --help` listed `pi` as an install target. Treat these as recorded setup
facts for this device, not as a universal Herdr state.

The installer owns its generated device-local extension at
`~/.pi/agent/extensions/herdr-agent-state.ts`; do not copy its implementation
into this repository or edit it as a tracked configuration. Do not install
Herdr integrations for other worker harnesses as part of Pi setup.

Authentication remains Pi-local. The portable defaults select
`openai-codex/gpt-6.1-sol` with `high` thinking for new sessions. The OAuth
credential remains only in Pi's device-local authentication store; never put
credentials in portable
defaults. Use `/login` only when provider readiness fails,
and use `/model` when temporarily selecting another model for a session.

For the live verification, restart Pi in a Herdr pane selected by the user.
Check its extension-load output and confirm Herdr recognizes it as Pi. With an
already available provider, send one harmless conversational prompt and observe
the pane transition from working to idle. If an interactive terminal or provider
is unavailable, record this smoke test as unverified rather than changing login
or model configuration.

## Deploy the package

Run Stow from the durable dotfiles checkout, not from a temporary worktree that
may later be deleted. Inspect existing paths for symlinks and conflicts before
deployment. Use these commands only during authorized deployment:

```sh
mkdir -p "$HOME/.pi/agent/extensions"
stow --no-folding --simulate --verbose -t "$HOME" pi
stow --no-folding -t "$HOME" pi
```

A conflict stops deployment. Preserve the existing file and resolve the
conflict explicitly. Do not use `stow --adopt` or remove existing
configuration.

## Apply portable defaults

The portable defaults select `tuiMode: "regular"` so Pi uses terminal scrollback
and tmux copy mode can navigate the transcript. Restart Pi to change its TUI mode;
use `pi --continue` to resume the most recent session in the current directory.

Stow links files; it does not merge JSON. Before the first deployment on a device,
initialize the Git-ignored `pi/.pi/agent/settings.json` from the portable defaults.
If `~/.pi/agent/settings.json` already exists as a regular file, validate that it
is a JSON object and move it to that Git-ignored repository path, preserving its
contents. This migration requires approval for the home-directory write. Stop
if the repository target already exists or the active file is an unexpected
symlink; do not adopt or overwrite a conflict.

Deep-merge portable defaults into the Git-ignored active file: existing settings
first, defaults second. Preserve unknown keys, package declarations, and nested
`compaction` settings. Do not print live settings or read authentication files.
Then run the deployment commands above. Verify that the home-directory settings
path resolves to the Git-ignored repository file and that `tuiMode` is `regular`.
Subsequent Stow runs maintain the link; changes to the active repository file
are immediately available to Pi. Changing the defaults template alone still
requires applying its values to the active file.

## Verification

Validate the tracked defaults without touching active settings:

```sh
jq -e 'type == "object"' pi/.pi/agent/settings.defaults.json
jq -n --slurpfile defaults pi/.pi/agent/settings.defaults.json '
  {defaultProvider:"fixture", defaultModel:"fixture-model",
   defaultThinkingLevel:"low",
   packages:["fixture-package"], compaction:{enabled:false,keepRecentTokens:1234}}
  * $defaults[0]
  | .defaultProvider == "openai-codex"
    and .defaultModel == "gpt-6.1-sol"
    and .defaultThinkingLevel == "high"
    and .packages == ["fixture-package"]
    and .compaction.keepRecentTokens == 1234
    and .compaction.enabled == true
    and .defaultProjectTrust == "ask"
    and .enableSkillCommands == true
    and .tuiMode == "regular"
' -e
```

For a Stow check, use a disposable target from `mktemp -d`, run Stow with
`--no-folding`, and confirm `.pi` and `agent` are real directories
while only intended files are links. Keep synthetic runtime fixtures in that
target; they must not become repository changes. Also confirm the runtime
paths are ignored:

```sh
git check-ignore --no-index pi/.pi/agent/auth.json \
  pi/.pi/agent/settings.json pi/.pi/agent/sessions/example.jsonl
```

The tracked defaults must not be ignored. Finish with `git diff --check`.

## Roll back portable setup

To remove only this Stow package while preserving Pi login, sessions, and local
settings, run:

```sh
stow --no-folding -D -t "$HOME" pi
```

Before removing the package, preserve the active settings in the home directory
if requested; unstowing removes its link but keeps the Git-ignored source file.
If undoing the newly installed native Herdr integration is also requested, run
`herdr integration uninstall pi`. Never
recursively delete `.pi`.
