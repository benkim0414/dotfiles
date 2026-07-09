# Runtime State Gitignore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ignore local Codex runtime databases, context-mode session state, and the installer-managed Herdr binary without hiding repo-managed helper scripts.

**Architecture:** Make a narrow `.gitignore`-only change. Keep the existing Codex runtime section as the owner of Codex and context-mode state, and add a separate local installer-managed binaries section for the Herdr executable.

**Tech Stack:** Git ignore patterns, dotfiles repository layout, Herdr installer-managed binary at `~/.local/bin/herdr`, Codex/context-mode runtime state under `codex/.codex/`.

## Global Constraints

- Do not ignore all of `bin/.local/bin/`.
- Do not touch `nvim/.config/nvim/lazy-lock.json`.
- Keep Herdr portable across Linux and macOS by not committing the installed binary.
- Cover SQLite WAL and SHM sidecars with `*.sqlite*`-style patterns.

---

## File Structure

- Modify `.gitignore`: add the narrow ignore patterns.
- No tests are created because the behavior is Git ignore matching, verified with `git check-ignore` and `git status`.

### Task 1: Add Runtime and Installer Ignore Rules

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Consumes: existing `.gitignore` section names and patterns.
- Produces: Git ignore coverage for `bin/.local/bin/herdr`, `codex/.codex/context-mode/sessions/`, `codex/.codex/goals_*.sqlite*`, and `codex/.codex/memories_*.sqlite*`.

- [ ] **Step 1: Inspect the current ignore file**

Run:

```bash
sed -n '1,80p' .gitignore
```

Expected: output includes `tmux/.config/tmux/plugins`, the Herdr runtime state lines, and the existing `# Codex runtime artifacts (keep config.base.toml)` section.

- [ ] **Step 2: Edit `.gitignore`**

Add the local installer-managed binary section after `tmux/.config/tmux/plugins` and add the Codex runtime patterns inside the existing Codex runtime section.

Expected resulting relevant content:

```gitignore
tmux/.config/tmux/plugins
# Local installer-managed binaries
bin/.local/bin/herdr
herdr/.config/herdr/*.log
herdr/.config/herdr/plugins.json
herdr/.config/herdr/session.json
```

Expected Codex runtime additions:

```gitignore
codex/.codex/context-mode/sessions/
codex/.codex/goals_*.sqlite*
codex/.codex/memories_*.sqlite*
```

- [ ] **Step 3: Verify Herdr binary ignore matching**

Run:

```bash
git check-ignore -v bin/.local/bin/herdr
```

Expected: output names `.gitignore` and the pattern `bin/.local/bin/herdr`.

- [ ] **Step 4: Verify Codex runtime ignore matching**

Run:

```bash
git check-ignore -v \
  codex/.codex/context-mode/sessions/71c580dbd3c19b01.db \
  codex/.codex/context-mode/sessions/stats-pid-128483.json \
  codex/.codex/goals_1.sqlite \
  codex/.codex/goals_1.sqlite-shm \
  codex/.codex/goals_1.sqlite-wal \
  codex/.codex/memories_1.sqlite \
  codex/.codex/memories_1.sqlite-shm \
  codex/.codex/memories_1.sqlite-wal
```

Expected: every path is reported as ignored by `.gitignore`.

- [ ] **Step 5: Verify status in the primary checkout**

Run from `/home/benkim0414/workspace/dotfiles` after the `.gitignore` change is applied there:

```bash
git status --short --untracked-files=all
```

Expected: the observed `codex/.codex/context-mode/sessions/*`, `codex/.codex/goals_1.sqlite*`, `codex/.codex/memories_1.sqlite*`, and `bin/.local/bin/herdr` files no longer appear. The unrelated `M nvim/.config/nvim/lazy-lock.json` entry may still appear.

- [ ] **Step 6: Inspect diff**

Run:

```bash
git diff -- .gitignore
```

Expected: the diff contains only the ignore rules from Step 2.

- [ ] **Step 7: Commit the `.gitignore` change**

Run:

```bash
git add .gitignore
git commit -m "chore(codex): ignore runtime state files"
```

Expected: commit succeeds and stages only `.gitignore`.
