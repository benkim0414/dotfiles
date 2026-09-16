# Personal Pi

Installation owner: `mise` (the `pi` installation and its version are managed
by mise). Observed on 2026-09-16: Pi `0.85.1`; Herdr `0.9.0`. Do not initiate
an update as part of setup.

## File map

- `pi/.pi/agent/settings.defaults.json` is the portable, Stow-managed defaults
  file and deploys to `~/.pi/agent/settings.defaults.json`.
- `~/.pi/agent/settings.json` is the active device-local settings file. Keep it
  writable and do not track it.
- `~/.pi/agent/skills/` contains intentional portable skills; downloaded
  extensions, sessions, and authentication remain device-local.

## Use Factory explicitly

Ordinary `pi` remains the personal coding agent. For the Factory coordinator,
open Pi in a Herdr pane, invoke `/skill:factory`, then identify the local
`benkim0414/factory` checkout. The skill coordinates Factory's documented CLI
and manual worker workflow; it does not automatically launch, supervise, steer,
or cancel workers. Steps that require a worker pane or prompt delivery remain
manual, and no automatic worker behavior is promised.

The Factory skill is explicitly activated and is not automatically selected in
normal Pi sessions or workers. Factory's existing status, ticket, attempt,
worktree, and review records remain authoritative.

## Package policy

Start with Pi core and the curated Factory skill; do not install community
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
`openai-codex/gpt-5.6-sol` with `high` thinking for new sessions because Pi is
the Factory coordinator on this device. The OAuth credential remains only in
Pi's device-local authentication store; never put credentials in portable
defaults or the Factory skill. Use `/login` only when provider readiness fails,
and use `/model` when temporarily selecting another model for a session.

For the live verification, restart Pi in a Herdr pane selected by the user.
Check its extension-load output and confirm Herdr recognizes it as Pi. With an
already available provider, send one harmless conversational prompt and observe
the pane transition from working to idle. If an interactive terminal or provider
is unavailable, record this smoke test as unverified rather than changing login
or model configuration.

To verify the optional Factory path, explicitly invoke `/skill:factory` and ask
only for a status check against the user's existing Factory checkout. Confirm it
uses that checkout's documented CLI and neither creates a ticket nor claims
automatic worker control. If no checkout is available, leave this smoke test
unverified; do not clone a checkout or create Factory state as implicit setup.

## Deploy the package

Run Stow from the durable dotfiles checkout, not from a temporary worktree that
may later be deleted. Inspect existing paths for symlinks and conflicts before
deployment. Use these commands only during authorized deployment:

```sh
mkdir -p "$HOME/.pi/agent/skills" "$HOME/.pi/agent/extensions"
stow --no-folding --simulate --verbose -t "$HOME" pi
stow --no-folding -t "$HOME" pi
```

A conflict stops deployment. Preserve the existing file and resolve the
conflict explicitly. Do not use `stow --adopt` or remove existing
configuration.

## Apply portable defaults

Defaults are applied as a JSON deep merge: existing settings first, portable
defaults second. This deliberately restores the six values owned by this
package while retaining unrelated local preferences. The existing settings
file must be a JSON object; invalid input or another JSON type stops the update.
If active settings do not exist, initialize them from the defaults.

Before editing the real file, make a recoverable device-local backup. Use the
native file-edit mechanism to perform the merge after required approval. Do not
log the full settings or read authentication files. The following command is a
fixture-only validation example: run it only with synthetic files, never with
live settings paths, because it prints the merged JSON:

```sh
jq -s '.[0] * .[1]' existing-settings.json settings.defaults.json
```

For the real deployment, after the required approval, use only the native
file-edit mechanism against the active settings file. Existing
packages, resource paths, unknown keys, and additional `compaction` settings
are preserved. Reapplying defaults deliberately selects
`openai-codex/gpt-5.6-sol` at `high` thinking and restores
`defaultProjectTrust`, `enableSkillCommands`, and `compaction.enabled`; no
custom sync script is needed.

Do not dump live settings into the shell or logs. A safe procedure is:

1. Check whether `~/.pi/agent/settings.json` exists and is a JSON object.
2. Copy it to a timestamped backup in the same device-local directory.
3. Apply the defaults to the active file through the native file-edit
   mechanism, without logging settings.
4. If no active file exists, initialize it from the defaults.

If the active file is malformed or not an object, stop and resolve it explicitly
rather than overwriting it.

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
    and .defaultModel == "gpt-5.6-sol"
    and .defaultThinkingLevel == "high"
    and .packages == ["fixture-package"]
    and .compaction.keepRecentTokens == 1234
    and .compaction.enabled == true
    and .defaultProjectTrust == "ask"
    and .enableSkillCommands == true
' -e
```

For a Stow check, use a disposable target from `mktemp -d`, run Stow with
`--no-folding`, and confirm `.pi`, `agent`, and `skills` are real directories
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

Restore a changed active settings file from its device-local deployment backup
only on explicit request. If undoing the newly installed native Herdr
integration is also requested, run `herdr integration uninstall pi`. Never
recursively delete `.pi`.
