# Personal Pi

Installation owner: `mise` (the `pi` installation and its version are managed
by mise). Observed on 2026-09-16: Pi `0.85.1`; Herdr `0.9.0`. Do not initiate
an update as part of setup.

## File map

- `pi/.pi/agent/settings.json` is the single Git-tracked configuration, linked
  by Stow to `~/.pi/agent/settings.json`. Pi reads and writes this file.
  Model choices, preferences, and package declarations are shared across machines.
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

Authentication remains Pi-local. The shared settings select
`openai-codex/gpt-6.1-sol` with `high` thinking for new sessions. The OAuth
credential remains only in Pi's device-local authentication store; never put
credentials in the tracked settings. Use `/login` only when provider readiness fails,
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

## Shared settings across machines

The shared configuration adds `codemode` with `defaultTools: ["+codemode"]`,
preserving Pi's default tools. Run `/reload` or start a new Pi session after
changing it. Explicit CLI tool selections can override this setting. See Pi's
bundled `docs/cli.md` (Enable codemode) and `docs/settings.md` (Tools).

`tuiMode: "regular"` enables terminal scrollback and tmux copy mode navigation.
Restart Pi to change its TUI mode; use `pi --continue` to resume the most recent
session in the current directory.

On each machine, sync the repository and deploy the Pi Stow package from the
durable checkout. There is no defaults file to merge. If a regular
`~/.pi/agent/settings.json` already exists, review its preferences and preserve
it before replacing it with the Stow link; stop on conflicts. Home-directory
changes require approval under the working agreements.

Pi also writes preferences, package declarations, and changelog state to this
file. Review and commit intended changes before syncing to another machine,
and resolve any Git conflicts before starting Pi. Package declarations are
shared; installed package files, authentication, and sessions remain local.
A temporary model choice can use `/model` or a CLI override.

## Settings maintenance

Keep shared settings portable: avoid machine-specific shell paths, proxies,
and absolute resource paths. Use a project's `.pi/settings.json` for
repository-specific settings. Authentication and saved trust decisions stay
device-local.

Keep `defaultProjectTrust: "ask"`. Trust controls loading project resources;
it does not sandbox tools or restrict their access to files and processes.
Keep automatic compaction enabled and use the default token thresholds,
transport, and retry settings unless a specific problem requires tuning.
In particular, leave provider-level retries at their default of zero.

Pin package declarations to exact versions and review source before upgrades.
The shared configuration includes `pi-web-access@0.29.0` with packaged skills
disabled; `pi-goal-x` is no longer configured. Removing its declaration stops
it loading from this configuration; existing installed files may remain local.

The `$schema` reference enables editor validation and completion. The hosted
schema follows upstream, so check suggested options against the documentation
bundled with the installed Pi version before adding them. Review Git diffs
after `/settings` changes or package commands, and commit intended changes
before syncing machines.

References: Pi's official [settings](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md),
[packages](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md),
and [security](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/security.md)
documentation.

## Verification

Validate the shared configuration:

```sh
jq -e 'type == "object" and .defaultTools == ["+codemode"]
  and .tuiMode == "regular"' pi/.pi/agent/settings.json
```

For a Stow check, use a disposable target within the task worktree, run Stow
with `--no-folding`, and confirm `.pi` and `agent` are real directories while
`settings.json` is a link. Keep synthetic runtime fixtures in that target;
they must not become repository changes. Confirm runtime paths are ignored:

```sh
git check-ignore --no-index pi/.pi/agent/auth.json \
  pi/.pi/agent/sessions/example.jsonl pi/.pi/agent/extensions/example.ts
```

`pi/.pi/agent/settings.json` must not be ignored. Finish with
`git diff --check`.

## Roll back portable setup

To remove only this Stow package while preserving Pi login, sessions, and shared
settings, run:

```sh
stow --no-folding -D -t "$HOME" pi
```

Before removing the package, preserve the active settings in the home directory
if requested; unstowing removes its link but keeps the tracked source file.
If undoing the newly installed native Herdr integration is also requested, run
`herdr integration uninstall pi`. Never
recursively delete `.pi`.
