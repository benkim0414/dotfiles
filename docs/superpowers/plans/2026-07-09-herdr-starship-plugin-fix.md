# Herdr Starship and Plugin Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Herdr panes start zsh so Starship loads, and register the local `vim-herdr-navigation` plugin actions that Herdr keybindings call.

**Architecture:** The repo change is a small Herdr config addition plus documentation for the device-local plugin registry step. Live machine state is fixed through Herdr CLI commands after the config parses cleanly.

**Tech Stack:** Herdr 0.7.x, TOML, zsh, Starship, GNU Stow, `vim-herdr-navigation`.

## Global Constraints

- Work from the linked worktree at `.worktrees/fix-herdr-starship-plugin`.
- Stage explicit paths only; do not use `git add -A`, `git add .`, or `git add -u`.
- Use conventional commit subjects with scope `herdr`.
- Keep Herdr config as a minimal override; do not paste the full `herdr --default-config` output.
- Do not track Herdr runtime state such as sockets, logs, or `session.json`.

---

### Task 1: Configure Herdr Pane Shell

**Files:**
- Modify: `herdr/.config/herdr/config.toml`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Herdr's `[terminal]` config table.
- Produces: New Herdr panes use zsh login shell startup and therefore source the stowed zsh/Starship config.

- [ ] **Step 1: Add the terminal shell block**

Edit `herdr/.config/herdr/config.toml` so it begins:

```toml
onboarding = false

[terminal]
default_shell = "zsh"
shell_mode = "login"

[keys]
```

- [ ] **Step 2: Document the shell behavior**

In `CLAUDE.md`, in the `# herdr` section after the keymap paragraph, add:

```markdown
New panes explicitly launch zsh as a login shell so the stowed zsh config and
Starship prompt load even when the Herdr server was started from a sparse
environment.
```

- [ ] **Step 3: Verify TOML**

Run:

```bash
python3 - <<'PY'
import tomllib
with open('herdr/.config/herdr/config.toml', 'rb') as f:
    data = tomllib.load(f)
assert data['terminal']['default_shell'] == 'zsh'
assert data['terminal']['shell_mode'] == 'login'
print('ok')
PY
```

Expected: `ok`

- [ ] **Step 4: Commit**

Run:

```bash
git diff -- herdr/.config/herdr/config.toml CLAUDE.md
git add herdr/.config/herdr/config.toml CLAUDE.md
git diff --cached
git commit -m "fix(herdr): launch panes with zsh login shell"
```

Expected: commit succeeds.

### Task 2: Register and Verify Herdr Plugin

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: The existing lazy.nvim checkout at `~/.local/share/nvim/lazy/vim-herdr-navigation`.
- Produces: Herdr registry actions `vim-herdr-navigation.left`, `.down`, `.up`, and `.right`.

- [ ] **Step 1: Clarify local plugin registration docs**

In `CLAUDE.md`, update the per-device setup plugin step so it mentions the local-checkout repair path:

```markdown
2. `herdr plugin install paulbkim-dev/vim-herdr-navigation --yes` -- registers the
   `vim-herdr-navigation.*` actions the config's `ctrl+hjkl` binds call. If
   lazy.nvim has already cloned the repo, `herdr plugin link
   ~/.local/share/nvim/lazy/vim-herdr-navigation` is also valid for this machine.
   herdr plugins live in herdr's own store, not Stow-managed (like `tpm` for
   tmux).
```

- [ ] **Step 2: Register the local plugin**

Run:

```bash
herdr plugin link ~/.local/share/nvim/lazy/vim-herdr-navigation
```

Expected: Herdr reports `vim-herdr-navigation` as linked or already linked.

- [ ] **Step 3: Verify plugin actions**

Run:

```bash
herdr plugin action list --plugin vim-herdr-navigation
```

Expected: output lists `vim-herdr-navigation.left`, `vim-herdr-navigation.down`, `vim-herdr-navigation.up`, and `vim-herdr-navigation.right`.

- [ ] **Step 4: Reload Herdr config**

Run:

```bash
herdr server reload-config
```

Expected: JSON result includes `"status":"applied"` and `"diagnostics":[]`.

- [ ] **Step 5: Commit docs**

Run:

```bash
git diff -- CLAUDE.md
git add CLAUDE.md
git diff --cached
git commit -m "docs(herdr): document local plugin registration"
```

Expected: commit succeeds if `CLAUDE.md` changed after Task 1; otherwise skip this commit.

## Self-Review

- Spec coverage: Task 1 covers the zsh/Starship startup cause; Task 2 covers the missing Herdr plugin registry.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: Herdr action names match the existing config values exactly.
