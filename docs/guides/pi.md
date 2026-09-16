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
defaults second. This deliberately restores the three values owned by this
package while retaining local preferences. The existing settings file must be
a JSON object; invalid input or another JSON type stops the update. If active
settings do not exist, initialize them from the defaults.

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
`defaultProvider`, `defaultModel`, packages, resource paths, unknown keys, and
additional `compaction` settings are preserved. Reapplying defaults
deliberately restores `defaultProjectTrust`, `enableSkillCommands`, and
`compaction.enabled`; no custom sync script is needed for three values.

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
