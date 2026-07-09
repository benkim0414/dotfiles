# herdr sidebar hjkl navigation — design

## Problem

In herdr's navigate mode, the workspace list in the sidebar moves only with the
up/down arrow keys. As a vim/tmux user I want `j`/`k` to walk that list, matching
the muscle memory already applied to the rest of the herdr keymap
(`2026-07-09-herdr-tmux-keybindings-design.md`).

## Background

herdr's navigate-mode movement is configurable via four `[keys]` entries
(defaults shown):

```toml
navigate_workspace_up = "up"
navigate_workspace_down = "down"
navigate_pane_left = "h"      # left arrow always focuses the pane to the left
navigate_pane_down = "j"
navigate_pane_up = "k"
navigate_pane_right = "l"     # right arrow always focuses the pane to the right
```

These "win while navigate mode is open" and are independent from the
`focus_pane_*` (prefix) and direct `ctrl+hjkl` (vim-herdr-navigation) paths. The
workspace list is bound to the arrows; pane focus within the mode is bound to
`h/j/k/l` plus the always-on left/right arrows.

herdr's own docs demonstrate the rebind pattern: giving `j` to
`navigate_workspace_down` requires relocating `navigate_pane_down` off `j`.

## Decision

Hand plain `j`/`k` to the workspace list and let the freed up/down arrows absorb
pane vertical movement inside navigate mode:

```toml
navigate_workspace_up = "k"      # was "up"
navigate_workspace_down = "j"    # was "down"
navigate_pane_up = "up"          # was "k" — reclaim the freed up-arrow
navigate_pane_down = "down"      # was "j" — reclaim the freed down-arrow
```

Resulting navigate-mode map:

| Key | Action |
|---|---|
| `j` / `k` | workspace list down / up (new) |
| `h` / `l` | pane focus left / right (unchanged) |
| up / down arrows | pane focus up / down (moved off workspace) |
| left / right arrows | pane focus left / right (always, unchanged) |

Global pane navigation is untouched: direct `ctrl+h/j/k/l`
(vim-herdr-navigation) and `prefix+h/j/k/l` (`focus_pane_*`) still move pane
focus everywhere, including inside navigate mode.

### Why not the alternatives

- **Relocate `navigate_pane_down/up` to `ctrl+j`/`ctrl+k`** (herdr's generic docs
  example): rejected — `ctrl+j`/`ctrl+k` are already bound globally to
  `vim-herdr-navigation.down`/`.up`. Reusing them risks a navigate-mode-vs-global
  collision.
- **Unset `navigate_pane_up/down = ""` and keep arrows on the workspace list:**
  rejected as the default — depends on herdr hardcoding up/down arrows to the
  workspace list (only left/right arrows are documented as always-on for panes).
  Unverified, so it risks a silent double-bind. The reassign above is
  deterministic.

## Scope

One config file, four `[keys]` lines. The new keys sit inside the existing
`[keys]` table, before the first `[[keys.command]]` array-of-tables block (TOML
ordering: bare keys after an array-of-tables would bind to that table, not
`[keys]`).

Docs: update the `# herdr` section of `CLAUDE.md` to note the navigate-mode
workspace keys, and add a `ce-compound` solution doc.

## Consequence

Up/down arrows stop moving the workspace list; `j`/`k` do. Workspace selection
also remains available via `prefix+w` (picker) and `prefix+g` (goto).

## Verify live (first launch)

1. Confirm the navigate-mode trigger (expected `prefix+g` / `goto`).
2. In navigate mode, `j`/`k` walk the workspace list.
3. In navigate mode, up/down arrows move pane focus (not the workspace list).
4. `herdr server reload-config` reports the change applied with zero diagnostics.

If herdr rejects `navigate_pane_*` reassignment or the arrows behave
unexpectedly, fall back to the unset alternative documented above.

## Related

- `docs/superpowers/specs/2026-07-09-herdr-tmux-keybindings-design.md`
- `docs/solutions/tooling-decisions/herdr-keybindings-match-tmux-muscle-memory.md`
- `CLAUDE.md` (`# herdr` section)
