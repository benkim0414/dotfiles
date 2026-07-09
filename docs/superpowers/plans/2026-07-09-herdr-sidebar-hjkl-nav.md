# herdr sidebar hjkl navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind `j`/`k` to the herdr workspace sidebar list in navigate mode, moving pane vertical movement to the freed up/down arrows.

**Architecture:** Four added/changed lines in the existing `[keys]` table of the stowed `herdr/.config/herdr/config.toml`. No code, no tests — verification is TOML validity plus herdr's own `reload-config` diagnostics and a live check.

**Tech Stack:** TOML, herdr 0.7.x, GNU Stow.

## Global Constraints

- New keys MUST sit inside the `[keys]` table, before the first `[[keys.command]]` array-of-tables block (TOML: bare keys after an array-of-tables bind to that table, not `[keys]`).
- Validate TOML with `/opt/homebrew/bin/python3.13` (has `tomllib`; system `python3` does not).
- Commit scope is `herdr`. Stage specific files only (never `git add -A`).
- Stateful steps (stow re-point, `herdr server reload-config`, live keypress check) run from `main` after merge — not from the worktree. The config is already stowed live from the prior herdr task; editing the package file changes the symlink target in place, but reload is deferred.

---

### Task 1: Add navigate-mode workspace keys

**Files:**
- Modify: `herdr/.config/herdr/config.toml` (insert after the `settings` line, line 6)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Edit the config**

Insert four lines into the `[keys]` table, immediately after the `settings = "prefix+comma"` line and before the blank line preceding the `# vim-herdr-navigation` comment. Resulting `[keys]` head:

```toml
[keys]
prefix = "ctrl+s"
split_horizontal = "prefix+s"   # stacked (pane below): tmux muscle memory
settings = "prefix+comma"       # evicted from prefix+s

# navigate mode: j/k walk the workspace sidebar list (default is arrows only);
# up/down arrows absorb pane vertical movement freed from j/k.
navigate_workspace_up = "k"
navigate_workspace_down = "j"
navigate_pane_up = "up"
navigate_pane_down = "down"
```

- [ ] **Step 2: Validate TOML parses**

Run:
```bash
/opt/homebrew/bin/python3.13 -c "import tomllib,sys; d=tomllib.load(open('herdr/.config/herdr/config.toml','rb')); k=d['keys']; print(k['navigate_workspace_up'], k['navigate_workspace_down'], k['navigate_pane_up'], k['navigate_pane_down'])"
```
Expected: `k j up down`

- [ ] **Step 3: Confirm the four keys live in `[keys]`, not a command table**

Run:
```bash
/opt/homebrew/bin/python3.13 -c "import tomllib; d=tomllib.load(open('herdr/.config/herdr/config.toml','rb')); assert set(['navigate_workspace_up','navigate_workspace_down','navigate_pane_up','navigate_pane_down']).issubset(d['keys']); assert len(d['keys']['command'])==4; print('ok: 4 keys in [keys], 4 command blocks intact')"
```
Expected: `ok: 4 keys in [keys], 4 command blocks intact`

- [ ] **Step 4: Commit**

```bash
git add herdr/.config/herdr/config.toml
git commit -m "feat(herdr): bind j/k to workspace sidebar in navigate mode"
```

---

### Task 2: Document the navigate-mode keys

**Files:**
- Modify: `CLAUDE.md` (`# herdr` section)

**Interfaces:**
- Consumes: the shipped config from Task 1.
- Produces: nothing.

- [ ] **Step 1: Extend the `# herdr` section**

In `CLAUDE.md`, in the `# herdr` section, add a sentence to the paragraph describing the keymap (near the `r`/`R`/`b` defaults note) stating:

```
In navigate mode the workspace sidebar list moves with `j`/`k`
(`navigate_workspace_up/down`); the up/down arrows are reassigned to pane
vertical focus (`navigate_pane_up/down`). Pane nav elsewhere is unchanged
(`ctrl+hjkl`, `prefix+hjkl`).
```

Match the surrounding prose style; do not duplicate the full keymap table.

- [ ] **Step 2: Verify the edit reads correctly**

Run:
```bash
grep -n "navigate_workspace" CLAUDE.md
```
Expected: one line referencing `navigate_workspace_up/down`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(herdr): document navigate-mode workspace hjkl keys"
```

---

## Post-merge / live verification (run from `main` after finishing the branch)

Not part of the task commits — these need the live herdr server and a human keypress.

1. `herdr server reload-config` -> expect `"status":"applied"`, `"diagnostics":[]`.
2. Enter navigate mode (expected `prefix+g` / `goto`); press `j`/`k` -> workspace list selection moves down/up.
3. In navigate mode, press up/down arrows -> pane focus moves (not the workspace list).
4. If herdr rejects the `navigate_pane_*` reassignment or arrows misbehave, fall back to the spec's unset alternative (`navigate_pane_up/down = ""`, leave arrows on the workspace list).

## Self-Review

- **Spec coverage:** config change (Task 1), docs update (Task 2), verify-live steps (post-merge section), rejected-alternative fallback (post-merge step 4) — all spec sections mapped.
- **Placeholder scan:** none; full config block and exact commands given.
- **Type consistency:** key names (`navigate_workspace_up/down`, `navigate_pane_up/down`) identical across spec, Task 1, Task 2, and verification.
