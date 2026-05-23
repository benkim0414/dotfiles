# Zsh Aliases Design

## Goal

Keep zsh aliases in a dedicated alias file sourced by `.zshrc`, while pruning shortcuts that duplicate newer defaults and adding a minimal Kubernetes shortcut.

## Current State

Aliases currently live directly in `zsh/.zshrc` beside environment loading, plugin setup, and helper functions. The existing aliases cover editor shortcuts, `eza` listing commands, `lazygit`, and Claude Code shortcuts. Small helper functions such as `sz()` and `bwu()` also live in `.zshrc`.

Two Claude aliases are now stale:

- `cca` duplicates the user's default Claude auto mode.
- `ccw` duplicates the enforced Claude Code worktree workflow.

## Recommended Approach

Create `zsh/.zsh_aliases` as an alias-only file and source it from `zsh/.zshrc`. This follows a common shell convention, mirrors the familiar `.bash_aliases` pattern, and fits the repository's current home-directory dotfile layout.

Keep helper functions in `.zshrc`. The new alias file should only contain `alias` declarations grouped by purpose.

## Alias Set

Move these existing aliases into `zsh/.zsh_aliases`:

- Editor: `vi`, `vim`
- Listing: `ld`, `lf`, `lh`, `ls`, `lt`
- Git: `lg`
- Claude Code: `cc`, `ccc`, `ccr`, `ccp`

Remove these aliases:

- `cca`
- `ccw`

Add this Kubernetes alias:

- `k="kubectl"`

## Kubectl Completion

The official Kubernetes quick reference documents the `k` alias and shell completion setup. Implement kubectl completion with guards so shell startup does not fail when `kubectl` is unavailable.

If zsh completion registration for the alias can be done cleanly with the existing completion setup, wire `k` to kubectl completion. Avoid importing generated kubectl alias packs for now; large alias sets such as `ahmetb/kubectl-aliases` are useful for people who want a full shorthand language, but they are unnecessary for the requested minimal shortcut.

## Validation

Run noninteractive checks after editing:

- `zsh -n zsh/.zshrc zsh/.zsh_aliases`
- Source `.zshrc` in zsh and confirm `k`, kept aliases, and removed aliases resolve as expected.

Manual validation after reloading zsh:

- `alias k` prints `kubectl`.
- `alias cca` and `alias ccw` report no alias.
- Existing aliases such as `vim`, `ls`, `lg`, and `cc` still exist.
- If `kubectl` is installed, completion for `k` behaves like completion for `kubectl`.

## Out Of Scope

- Moving shell helper functions out of `.zshrc`.
- Adding generated kubectl alias packs.
- Changing zsh plugin management.
- Removing `eza`, `lazygit`, or Claude aliases beyond `cca` and `ccw`.
