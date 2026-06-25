# insane-search Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `insane-search` Claude Code plugin and make all plugin marketplaces auto-register on fresh devices via `extraKnownMarketplaces` in synced settings.

**Architecture:** Declarative settings only. Add an `extraKnownMarketplaces` block (5 marketplaces, each `autoUpdate: true`) and one `enabledPlugins` line to `claude/.claude/settings.base.json`; document the convention in the root `CLAUDE.md`. `claude-sync` already deep-merges these object keys -- no script change. Marketplaces ride synced settings, so a fresh device auto-installs them after a one-time trust prompt.

**Tech Stack:** JSON settings, `jq` (merge engine in `claude-sync`), GNU Stow, markdown docs.

---

## File Structure

- `claude/.claude/settings.base.json` -- add top-level `extraKnownMarketplaces`; add one line to `enabledPlugins`. The only behavioral change.
- `CLAUDE.md` (repo root) -- fold the marketplace/plugin reproducibility convention into the existing "Claude Code settings (layered merge)" section.

No new files. No `claude-sync`, Brewfile, or test-harness changes (rationale in the spec).

---

## Verification context (read before Task 3)

`claude-sync` resolves `DOTFILES="${DOTFILES_DIR:-$HOME/workspace/dotfiles}"` and **also re-stows** the claude package (`stow -d "$DOTFILES" -t ~ -R claude`). Running it with `DOTFILES_DIR` pointed at this worktree would repoint live `~/.claude` symlinks at the worktree -- do **not** do that as a verification step.

In-worktree verification therefore validates the edited base file directly and dry-runs the merge to a temp file with no side effects. The real `claude-sync` regen + `claude /doctor` happen after this branch merges to `main` (the no-pr finish pushes `main`; then `claude-sync` runs normally against `main`). Task 3 covers both the in-worktree checks and the documented post-merge step.

---

## Task 1: Add extraKnownMarketplaces + enable insane-search

**Files:**
- Modify: `claude/.claude/settings.base.json:348-354` (`enabledPlugins` block) and append a new top-level `extraKnownMarketplaces` key.

- [ ] **Step 1: Add the `insane-search` line to `enabledPlugins`**

The `enabledPlugins` block currently reads:

```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "context-mode@context-mode": true,
    "superpowers@superpowers-marketplace": true
  }
```

Insert `insane-search@gptaku-plugins` in alphabetical-by-id order (between `context-mode` and `superpowers`) so the block becomes:

```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "context-mode@context-mode": true,
    "insane-search@gptaku-plugins": true,
    "superpowers@superpowers-marketplace": true
  }
```

- [ ] **Step 2: Add the `extraKnownMarketplaces` top-level block**

`enabledPlugins` is currently the last top-level key (file ends with `}` on its own line after the `enabledPlugins` closing `}`). Add `extraKnownMarketplaces` as a sibling key. To keep a valid object, the `enabledPlugins` closing brace gets a trailing comma and the new block follows. Result (tail of file):

```json
  "enabledPlugins": {
    "caveman@caveman": true,
    "claude-md-management@claude-plugins-official": true,
    "compound-engineering@compound-engineering-plugin": true,
    "context-mode@context-mode": true,
    "insane-search@gptaku-plugins": true,
    "superpowers@superpowers-marketplace": true
  },
  "extraKnownMarketplaces": {
    "caveman": {
      "source": { "source": "github", "repo": "JuliusBrussee/caveman" },
      "autoUpdate": true
    },
    "compound-engineering-plugin": {
      "source": { "source": "github", "repo": "EveryInc/compound-engineering-plugin" },
      "autoUpdate": true
    },
    "context-mode": {
      "source": { "source": "github", "repo": "mksglu/context-mode" },
      "autoUpdate": true
    },
    "gptaku-plugins": {
      "source": { "source": "github", "repo": "fivetaku/gptaku_plugins" },
      "autoUpdate": true
    },
    "superpowers-marketplace": {
      "source": { "source": "github", "repo": "obra/superpowers-marketplace" },
      "autoUpdate": true
    }
  }
}
```

Note: `claude-plugins-official` is intentionally omitted -- it is the official Anthropic marketplace and is auto-known to Claude Code.

- [ ] **Step 3: Verify the file is valid JSON and has the expected contents**

Run:
```bash
cd /Users/ben/workspace/dotfiles/.claude/worktrees/insane-search-plugin
jq -e '
  (.enabledPlugins["insane-search@gptaku-plugins"] == true)
  and ((.extraKnownMarketplaces | keys) == ["caveman","compound-engineering-plugin","context-mode","gptaku-plugins","superpowers-marketplace"])
  and (all(.extraKnownMarketplaces[]; .autoUpdate == true and (.source.source == "github") and (.source.repo | length > 0)))
' claude/.claude/settings.base.json
```
Expected: prints `true` and exits 0. (A parse error or `false` means a typo -- fix it.)

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "feat(claude): declare plugin marketplaces and enable insane-search"
```

---

## Task 2: Document the marketplace/plugin reproducibility convention

**Files:**
- Modify: `CLAUDE.md` (repo root) -- the "Claude Code settings (layered merge)" section.

- [ ] **Step 1: Add a documentation paragraph to the layered-merge section**

In the "# Claude Code settings (layered merge)" section of the root `CLAUDE.md`, after the paragraph that ends `...With no overlay present it copies the base as-is.` (immediately before the "Instructions layer separately..." paragraph), insert this subsection verbatim:

```markdown
## Plugins and marketplaces (cross-device)

Two `settings.base.json` keys make the plugin set reproducible on any
device through synced settings alone -- no manual `/plugin marketplace
add`:

- `enabledPlugins` toggles each plugin on (`"plugin@marketplace": true`).
- `extraKnownMarketplaces` declares the marketplace each plugin comes
  from (`github` source + `repo`). On a fresh device Claude Code
  auto-installs every declared marketplace after a one-time trust
  prompt. Every entry sets `"autoUpdate": true`, so Claude Code refreshes
  the marketplace and updates its installed plugins at startup.

A plugin needs an `enabledPlugins` entry AND -- unless it lives on the
official Anthropic marketplace -- an `extraKnownMarketplaces` entry for
its marketplace. `claude-md-management@claude-plugins-official` rides the
auto-known official marketplace, so it has no `extraKnownMarketplaces`
entry by design. Both keys are objects, so `claude-sync` deep-merges
them (overlay wins); they live in the base, not an overlay, because they
are personal cross-device config.
```

- [ ] **Step 2: Verify the insertion landed in the right section**

Run:
```bash
cd /Users/ben/workspace/dotfiles/.claude/worktrees/insane-search-plugin
grep -n "Plugins and marketplaces (cross-device)" CLAUDE.md
awk '/# Claude Code settings \(layered merge\)/{s=1} /Plugins and marketplaces \(cross-device\)/{if(s)print "OK: subsection inside settings section"}' CLAUDE.md
```
Expected: the grep prints one line; the awk prints `OK: subsection inside settings section`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document cross-device plugin marketplace convention"
```

---

## Task 3: Verify the merge and document the post-merge regen

**Files:** none modified (verification only).

- [ ] **Step 1: Dry-run the `claude-sync` merge with no side effects**

This replicates `claude-sync`'s jq merge against the worktree base + the company overlay, writing to a temp file (never `~/.claude/settings.json`, never stowing):

```bash
cd /Users/ben/workspace/dotfiles/.claude/worktrees/insane-search-plugin
BASE=claude/.claude/settings.base.json
OVERLAY=claude/.claude/settings.overlay.json
OUT=/private/tmp/claude-501/-Users-ben-workspace-dotfiles/2bf48d9b-3486-4424-a6e0-be6f2d9d15f4/scratchpad/settings.merged.json
jq -n --slurpfile base <(jq -s '.' "$BASE") --slurpfile overlays <(jq -s '.' "$OVERLAY") '
  def merge(b):
    reduce (b | to_entries[]) as $e (.;
      if (.[$e.key] | type) == "object" and ($e.value | type) == "object"
        then if has($e.key) then .[$e.key] |= merge($e.value) else .[$e.key] = $e.value end
      else .[$e.key] = $e.value end);
  reduce $overlays[0][] as $o ($base[0]; merge($o))
' > "$OUT" && jq -e '
  (.enabledPlugins["insane-search@gptaku-plugins"] == true)
  and ((.extraKnownMarketplaces | length) == 5)
' "$OUT"
```
Expected: prints `true`, exits 0. Confirms the merged result Claude Code will load is valid and carries both blocks. (The company overlay defines neither key, so the base values pass through unchanged -- this is the expected outcome.)

- [ ] **Step 2: Confirm no placeholder/foreign keys leaked**

Run:
```bash
jq -e '.extraKnownMarketplaces | has("claude-plugins-official") | not' \
  /private/tmp/claude-501/-Users-ben-workspace-dotfiles/2bf48d9b-3486-4424-a6e0-be6f2d9d15f4/scratchpad/settings.merged.json
```
Expected: prints `true` (official marketplace correctly absent).

- [ ] **Step 3: Record the post-merge verification step (no commit)**

The live regen cannot run safely from the worktree (it would re-stow `~/.claude` from the worktree). After this branch merges to `main`, the operator runs the real verification:

```bash
claude-sync                      # regenerates ~/.claude/settings.json from main
jq -e '.extraKnownMarketplaces | length == 5' ~/.claude/settings.json
claude /doctor                   # expect no settings schema errors
```

First launch on this device may show no change (marketplaces already known/trusted). First launch on a *fresh* device shows a one-time trust prompt per marketplace, after which `insane-search` is active. This is the documented manual verification; no further action in the worktree.

---

## Self-Review

**Spec coverage:**
- extraKnownMarketplaces block, 5 entries, autoUpdate true -> Task 1 Step 2. (covered)
- enabledPlugins insane-search line -> Task 1 Step 1. (covered)
- claude-plugins-official omitted -> Task 1 Step 2 note + Task 3 Step 2. (covered)
- CLAUDE.md doc, folded into existing settings section -> Task 2. (covered)
- No claude-sync / Brewfile change -> reflected in File Structure (no tasks touch them). (covered)
- Verification: JSON validity + presence + /doctor + fresh-device note -> Task 3. (covered)

**Placeholder scan:** No TBD/TODO; every step has exact commands and full JSON/markdown blocks. (clean)

**Type consistency:** Marketplace keys (`caveman`, `compound-engineering-plugin`, `context-mode`, `gptaku-plugins`, `superpowers-marketplace`) and the plugin id `insane-search@gptaku-plugins` are identical across Task 1, Task 3, and the spec. The `length == 5` / `keys` assertions match the 5 declared entries. (consistent)
