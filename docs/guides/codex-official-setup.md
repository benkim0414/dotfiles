# Activate the reviewed Codex setup

This branch is prepared, not activated. Activation requires separate user authorization, including applying the reviewed changes to the primary checkout. `~/.codex` points into that checkout: changing its AGENTS.md or base immediately affects future sessions, and running its sync changes the live config. Do not point that symlink at the feature worktree.

## Back up before activation

Close other Codex sessions first; restart the controlling session after activation. Record the reviewed branch commit and the primary checkout commit and inspect `git status --short` in both checkouts. Stop if applying the change would overwrite unrelated work. Record `readlink "$HOME/.codex"` and any config/hook link targets without printing config contents.

Create a private backup directory; back up only the following migration files, preserving symlinks and permissions and recording which files were absent:

- `codex/.codex/config.toml` (contains the current model choices, trust entries, and plugin enablement), `config.base.toml`, and `AGENTS.md`.
- `bin/.local/bin/codex-sync` and `codex/.codex/sync_config.py`, if present.
- The old tracked `codex/.codex/hooks.json`, `hooks/atomic-commits.sh`, and `hooks/worktree-guard.sh`, if present.
- Separate managed links under `~/.codex` if the recorded topology differs from the current directory symlink.

For the current topology, this command makes the backup without copying credentials, caches, or shared skills:

```bash
primary="$HOME/workspace/dotfiles"
backup="$primary/codex/.codex/config.toml.bak.official-setup-$(date +%Y%m%d-%H%M%S)"
umask 077
mkdir "$backup"
python3 - "$primary" "$backup" <<'PY'
import json, pathlib, shutil, sys
root, backup = map(pathlib.Path, sys.argv[1:])
paths = ['codex/.codex/config.toml', 'codex/.codex/config.base.toml',
         'codex/.codex/AGENTS.md', 'bin/.local/bin/codex-sync',
         'codex/.codex/sync_config.py', 'codex/.codex/hooks.json',
         'codex/.codex/hooks/atomic-commits.sh',
         'codex/.codex/hooks/worktree-guard.sh']
present = []
for name in paths:
    source = root / name
    if source.exists() or source.is_symlink():
        target = backup / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target, follow_symlinks=False)
        present.append(name)
(backup / 'manifest.json').write_text(json.dumps({'paths': paths, 'present': present}))
PY
```

This backup directory is inside the workspace and covered by the existing `config.toml.bak*` ignore rule. Keep it private; config can contain private integration settings. Do not archive the whole `.codex` directory.

## Apply and activate

After reviewing the final branch commit, explicitly authorize integration into the primary checkout. Confirm that its current branch is the intended main branch and that `chore/codex-official-setup` still points to the reviewed commit. Stop on branch mismatch, a refused fast-forward, or a conflict; do not stash or discard unrelated changes (including current herdr/zsh edits). Integration includes the retired tracked hook files; sync refuses arbitrary regular hook files rather than deleting them. Preserve the existing ignored config.toml until sync merges it. These commands are instructions only; no integration has been performed.

With authorization and the backup available, integrate and activate in this order; stop if any command fails:

```bash
primary="$HOME/workspace/dotfiles"
git -C "$primary" merge --ff-only chore/codex-official-setup
DOTFILES="$primary" CODEX_HOME="$HOME/.codex" "$primary/bin/.local/bin/codex-sync"
python3 "$primary/codex/.codex/tests/test-codex-sync.py"
```

The regular config.toml behind the directory symlink stays a regular file. Sync preserves unrelated settings and existing official plugin enablement, replaces permission/reviewer choices, disables the enumerated shared skills and ELI5, removes context-mode registration and third-party marketplaces, and disables the three retired plugins. It removes only recognized managed hook links. If it refuses an unmanaged hook source or unrelated config destination, stop and resolve that specific source with the user before retrying.

## Check a fresh session

Start a fresh Codex session; an existing session can retain injected instructions and tools. Confirm short global instructions, user approval review, on-request, workspace-write, hooks disabled, and no custom hooks. Inspect skill discovery to confirm all 29 current shared skills and legacy ELI5 are disabled, five bundled system skills remain available, and official artifact plugins retain their previous enabled states. For the currently enabled five artifact plugins, expect six artifact skill entries. Confirm the live model and reasoning effort stayed `gpt-6.1-sol` and `low` (or the user's selections at activation time). Do not request a model response merely to inspect configuration.

The isolated strict app-server probe is documented in the Task 2 report. It does not establish that host-provided Pages, pets, or connector tools refresh correctly; inspect those in the fresh interactive session. New shared skills need additional disable entries and another discovery check.

## Roll back

Close Codex sessions. With explicit approval to restore primary/live files, use the manifest to restore only migration files from the private backup, preserving symlinks and modes. For paths recorded absent, remove only the migration-created file at that exact path after confirming no subsequent user edits. Restore recorded managed link topology if activation changed it. Restore config.toml directly; do not run the new sync against the old base. This restores model, trust, plugin enablement, instructions, and old hook configuration without touching credentials or shared assets.

Keep unrelated changes and commits. Do not reset the repository, delete branches/worktrees, or reverse subsequent user edits. Start a fresh session and inspect the restored configuration before resuming work.
