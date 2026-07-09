---
title: Bind hjkl to herdr's workspace sidebar list
date: 2026-07-09
category: tooling-decisions
module: herdr
problem_type: tooling_decision
component: tooling
severity: low
applies_when:
  - Wanting vim j/k navigation on herdr's workspace sidebar list instead of the default up/down arrows
  - Resolving a herdr navigate-mode key collision between navigate_workspace_* and navigate_pane_* bindings
  - herdr's own ctrl+j/ctrl+k relocation pattern is unavailable because those keys are already bound to vim-herdr-navigation direct pane-focus binds
tags: [herdr, keybindings, navigation, vim, sidebar, terminal-multiplexer]
---

# Bind hjkl to herdr's workspace sidebar list

## Context

herdr's navigate mode (triggered by `prefix+g` / `goto`) has two independent
movement axes, both configurable via `[keys]` entries. The defaults:

```toml
navigate_workspace_up = "up"     # arrows walk the workspace sidebar list
navigate_workspace_down = "down"
navigate_pane_left = "h"         # h/j/k/l move pane focus inside navigate mode
navigate_pane_down = "j"
navigate_pane_up = "k"
navigate_pane_right = "l"        # left/right arrows are always-on for panes too
```

These binds win only while navigate mode is open and are independent from the
`focus_pane_*` (prefix) and direct `ctrl+hjkl` (vim-herdr-navigation) paths. Out
of the box the workspace list is driven by arrows and pane focus by `h/j/k/l` —
the opposite of vim muscle memory, where `j`/`k` should walk the list you are
looking at. The task was to put vim `j`/`k` on the workspace sidebar list.

The naive fix (`navigate_workspace_up = "k"`, `navigate_workspace_down = "j"`)
collides: `j`/`k` are still claimed by `navigate_pane_down`/`navigate_pane_up`.
herdr's own docs resolve exactly this collision by relocating the pane binds to
`ctrl+j`/`ctrl+k` — a pattern that is wrong for this repo.

## Guidance

Swap the axis instead of chasing the generic docs. Hand plain `j`/`k` to the
workspace list, and let the freed up/down arrows absorb pane vertical movement:

```toml
navigate_workspace_up = "k"      # was "up"
navigate_workspace_down = "j"    # was "down"
navigate_pane_up = "up"          # was "k" — reclaim the freed up-arrow
navigate_pane_down = "down"      # was "j" — reclaim the freed down-arrow
```

Resulting navigate-mode map: `j`/`k` = workspace list down/up (new); `h`/`l` =
pane focus left/right (unchanged); up/down arrows = pane focus up/down (moved off
workspace); left/right arrows = pane focus left/right (always-on, unchanged).

Do NOT follow herdr's generic docs example of relocating
`navigate_pane_down`/`navigate_pane_up` to `ctrl+j`/`ctrl+k`. In this repo
`ctrl+j`/`ctrl+k` are already bound globally to `vim-herdr-navigation.down`/`.up`
via `[[keys.command]]` `plugin_action` binds (the direct-key seamless pane nav
shipped earlier — see the sibling doc,
`herdr-keybindings-match-tmux-muscle-memory.md`). Reusing them for the
navigate-mode pane binds risks a navigate-mode-vs-global collision.

The plain-key `navigate_pane` vertical binds were the redundant ones to sacrifice
precisely because global `ctrl+hjkl` (vim-herdr-navigation) and `prefix+hjkl`
(`focus_pane_*`) already cover pane focus everywhere — including inside navigate
mode. Global pane navigation is untouched by this change.

Placement gotcha: the four keys sit inside the `[keys]` table, before the first
`[[keys.command]]` array-of-tables block. In TOML, bare keys written after an
array-of-tables bind to that table, not back to `[keys]`.

Verify live on first launch:

1. Confirm the navigate-mode trigger (expected `prefix+g` / `goto`).
2. In navigate mode, `j`/`k` walk the workspace list.
3. In navigate mode, up/down arrows move pane focus (not the workspace list).
4. `herdr server reload-config` reports the change applied with zero
   diagnostics.

If herdr rejects the `navigate_pane_*` reassignment or the arrows misbehave, fall
back to the rejected alternative below.

## Why This Matters

The obvious collision fix — the one herdr's own documentation demonstrates —
introduces a silent regression here because it reuses keys already spoken for by
an earlier feature. The correct resolution is deterministic: reassigning the
freed arrows to the freed pane axis creates no new binding, so there is no key to
double-book. When two config layers touch overlapping keyspaces, the fix is to
map the whole picture (global binds + mode-local binds) before applying the
generic recipe — the recipe assumes a clean keyspace this repo does not have.

## When to Apply

- Configuring herdr navigate-mode movement to match vim/tmux muscle memory
  (`j`/`k` on the workspace sidebar list).
- Any time a tool's docs prescribe relocating a binding to a modifier key
  (`ctrl+*`) that another already-shipped layer in your config owns — check the
  target key is free before copying the recipe.

## Examples

Rejected alternatives (from the design):

- **Relocate `navigate_pane_down`/`navigate_pane_up` to `ctrl+j`/`ctrl+k`**
  (herdr's generic docs example): rejected — those keys are already bound
  globally to `vim-herdr-navigation.down`/`.up`, so reuse risks a
  navigate-mode-vs-global collision.
- **Unset `navigate_pane_up = ""` / `navigate_pane_down = ""` and keep arrows on
  the workspace list:** rejected as the default — it depends on herdr hardcoding
  up/down arrows to the workspace list, but only left/right arrows are documented
  as always-on for panes. That hardcoding is unverified, so it risks a silent
  double-bind. The axis swap above is deterministic and needs no undocumented
  behavior.

## Related

- Sibling (foundational keymap this extends):
  `docs/solutions/tooling-decisions/herdr-keybindings-match-tmux-muscle-memory.md`
  — the `ctrl+j`/`ctrl+k` constraint here traces to the vim-herdr-navigation
  direct binds shipped there.
- Design: `docs/superpowers/specs/2026-07-09-herdr-sidebar-hjkl-nav-design.md`
- Plan: `docs/superpowers/plans/2026-07-09-herdr-sidebar-hjkl-nav.md`
- Package convention + per-device setup: `CLAUDE.md` (`# herdr` section)
