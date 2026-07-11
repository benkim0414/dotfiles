# Niri Removal and Test Relocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove obsolete Niri desktop config and move package-specific shell tests next to the packages they validate.

**Architecture:** Delete the retired Niri and xdg-desktop-portal Stow package files and remove only the Niri auto-start stanza from zsh login setup. Move each top-level test harness into the owning package directory, updating each script's repository-root calculation and active documentation paths.

**Tech Stack:** GNU Stow package layout, Bash test harnesses, zsh configuration, git.

## Global Constraints

- Keep `bin/.local/bin/wiki-stage` and `bin/.local/bin/wiki-stage-install`.
- Keep `CLAUDE.md` wiki-stage documentation.
- Keep historical wiki-stage specs, plans, and solution notes.
- Do not touch unrelated `nvim/.config/nvim/lazy-lock.json` changes in the main worktree.
- Stage explicit paths only; do not use `git add -A`, `git add --all`, `git add -u`, `git add .`, `git commit -a`, or `git commit -am`.

---

## File Structure

- Delete `niri/.config/niri/config.kdl`: retired Niri compositor package.
- Delete `xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf`: retired Niri portal preference package.
- Modify `zsh/.zprofile`: keep keychain login setup and remove the Niri tty1 auto-start block.
- Move `tests/wiki-stage/run.sh` to `bin/tests/wiki-stage/run.sh`: package-local tests for `bin/.local/bin/wiki-stage*`.
- Move `tests/zsh-eval-cache/run.sh` to `zsh/tests/eval-cache/run.sh`: package-local tests for zsh eval-cache behavior.
- Modify `CLAUDE.md`: update test command references if it mentions the old top-level paths.
- Historical docs under `docs/superpowers/` and `docs/solutions/` may keep old paths as project history.

### Task 1: Remove Retired Niri Desktop Config

**Files:**
- Delete: `niri/.config/niri/config.kdl`
- Delete: `xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf`
- Modify: `zsh/.zprofile`

**Interfaces:**
- Consumes: Existing Stow package layout and zsh login profile.
- Produces: No active Niri package files and no `niri-session` auto-exec path.

- [ ] **Step 1: Inspect the current zprofile block**

Run: `sed -n '1,80p' zsh/.zprofile`

Expected: output includes the keychain block followed by this Niri block:

```sh
# Start Niri on the first TTY as a systemd-managed Wayland session.
# The display checks keep this from firing inside nested terminals, SSH
# sessions, or an already-running graphical session.
if command -v niri-session &>/dev/null \
    && [[ -z ${DISPLAY-} && -z ${WAYLAND_DISPLAY-} && "$(tty)" == /dev/tty1 ]]; then
    exec niri-session
fi
```

- [ ] **Step 2: Remove only the Niri auto-start block**

Edit `zsh/.zprofile` so its full content is:

```sh
# Start the SSH agent and load keys once per login; writes socket to ~/.keychain/.
# Only prompt from an interactive terminal so non-interactive shells do not
# fail through ssh-askpass when no TTY is available.
if command -v keychain &>/dev/null && [[ -o interactive && -t 0 ]]; then
    eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
fi
```

- [ ] **Step 3: Delete retired package files**

Run:

```sh
rm niri/.config/niri/config.kdl
rm xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf
```

Expected: both commands exit 0. The empty package directories may remain on disk but will have no tracked files.

- [ ] **Step 4: Verify no active Niri references remain**

Run: `rg -n "niri|xdg-desktop-portal" zsh niri xdg-desktop-portal`

Expected: no output and exit 1, because these active paths no longer contain matching tracked content.

- [ ] **Step 5: Inspect the diff**

Run: `git diff -- zsh/.zprofile niri/.config/niri/config.kdl xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf`

Expected: the diff removes only the Niri auto-start stanza from `zsh/.zprofile` and deletes the two desktop package files.

- [ ] **Step 6: Commit desktop cleanup**

Run:

```sh
git add zsh/.zprofile niri/.config/niri/config.kdl xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf
git diff --cached -- zsh/.zprofile niri/.config/niri/config.kdl xdg-desktop-portal/.config/xdg-desktop-portal/niri-portals.conf
git commit -m "chore: remove niri desktop config"
```

Expected: commit succeeds with a conventional subject. If the commit hook requires a known scope, retry with `chore(zsh): remove niri desktop config` because `zsh` is an existing scope and one changed file is zsh-owned.

### Task 2: Move Tests Under Owning Packages

**Files:**
- Move: `tests/wiki-stage/run.sh` to `bin/tests/wiki-stage/run.sh`
- Move: `tests/zsh-eval-cache/run.sh` to `zsh/tests/eval-cache/run.sh`
- Modify: `bin/tests/wiki-stage/run.sh`
- Modify: `zsh/tests/eval-cache/run.sh`
- Modify: `CLAUDE.md` if old test paths appear in active instructions

**Interfaces:**
- Consumes: Existing Bash test harnesses.
- Produces: Passing package-local test commands:
  - `bash bin/tests/wiki-stage/run.sh`
  - `bash zsh/tests/eval-cache/run.sh`

- [ ] **Step 1: Move the wiki-stage test harness**

Run:

```sh
mkdir -p bin/tests/wiki-stage
mv tests/wiki-stage/run.sh bin/tests/wiki-stage/run.sh
rmdir tests/wiki-stage
```

Expected: `bin/tests/wiki-stage/run.sh` exists and `tests/wiki-stage` no longer exists.

- [ ] **Step 2: Move the zsh eval-cache test harness**

Run:

```sh
mkdir -p zsh/tests/eval-cache
mv tests/zsh-eval-cache/run.sh zsh/tests/eval-cache/run.sh
rmdir tests/zsh-eval-cache
rmdir tests
```

Expected: `zsh/tests/eval-cache/run.sh` exists and top-level `tests/` is gone. If `rmdir tests` fails because another file was added there, inspect it and do not remove unrelated files.

- [ ] **Step 3: Update wiki-stage DOTFILES root calculation**

In `bin/tests/wiki-stage/run.sh`, replace:

```sh
DOTFILES=$(cd "$(dirname "$0")/../.." && pwd)
```

with:

```sh
DOTFILES=$(cd "$(dirname "$0")/../../.." && pwd)
```

This walks from `bin/tests/wiki-stage` back to the repository root.

- [ ] **Step 4: Update zsh eval-cache DOTFILES root calculation**

In `zsh/tests/eval-cache/run.sh`, replace:

```sh
DOTFILES=$(cd "$(dirname "$0")/../.." && pwd)
```

with:

```sh
DOTFILES=$(cd "$(dirname "$0")/../../.." && pwd)
```

This walks from `zsh/tests/eval-cache` back to the repository root.

- [ ] **Step 5: Find active references to old test paths**

Run: `rg -n '(^|[^[:alnum:]_/.-])tests/(wiki-stage|zsh-eval-cache)' CLAUDE.md bin zsh`

Expected: no output and exit 1. If output appears, update active instructions to the new paths:

```text
tests/wiki-stage/run.sh -> bin/tests/wiki-stage/run.sh
tests/zsh-eval-cache/run.sh -> zsh/tests/eval-cache/run.sh
```

- [ ] **Step 6: Run moved tests**

Run:

```sh
bash bin/tests/wiki-stage/run.sh
bash zsh/tests/eval-cache/run.sh
```

Expected:

```text
15 passed, 0 failed
6 passed, 0 failed
```

- [ ] **Step 7: Inspect path-only move and root edits**

Run:

```sh
git diff --stat
git diff -- bin/tests/wiki-stage/run.sh zsh/tests/eval-cache/run.sh CLAUDE.md
```

Expected: two renamed test files, each with only the `DOTFILES` path calculation changed. `CLAUDE.md` is unchanged unless Step 5 found active old-path references.

- [ ] **Step 8: Commit test relocation**

Run:

```sh
git add bin/tests/wiki-stage/run.sh zsh/tests/eval-cache/run.sh tests/wiki-stage/run.sh tests/zsh-eval-cache/run.sh CLAUDE.md
git diff --cached --stat
git commit -m "test: move shell harnesses under owning packages"
```

Expected: commit succeeds. If `CLAUDE.md` was unchanged, `git add CLAUDE.md` is a harmless no-op.

### Task 3: Final Verification

**Files:**
- Verify: working tree and active references.

**Interfaces:**
- Consumes: Commits from Tasks 1 and 2.
- Produces: Clean branch ready for final review.

- [ ] **Step 1: Run complete relevant verification**

Run:

```sh
bash bin/tests/wiki-stage/run.sh
bash zsh/tests/eval-cache/run.sh
rg -n '(^|[^[:alnum:]_/.-])tests/(wiki-stage|zsh-eval-cache)' CLAUDE.md bin zsh
rg -n "niri|xdg-desktop-portal" zsh niri xdg-desktop-portal
```

Expected: both test commands pass. Both `rg` commands produce no active matches and exit 1.

- [ ] **Step 2: Confirm wiki-stage tooling still exists**

Run:

```sh
test -x bin/.local/bin/wiki-stage
test -x bin/.local/bin/wiki-stage-install
```

Expected: both commands exit 0.

- [ ] **Step 3: Inspect final status and recent commits**

Run:

```sh
git status --short --branch
git log --oneline -4
```

Expected: clean working tree on `remove-niri-relocate-tests`, with recent commits for the design, desktop cleanup, and test relocation.
