# Claude Code Response Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude Code responses readable by defaulting caveman prose compression off, adding a custom output style that governs response structure, and fixing two theme colour problems.

**Architecture:** Three independent configuration changes in the dotfiles repo, each guarded by a bash test living in the package it guards — `claude/.claude/tests/` for the claude ones, `caveman/tests/` for the caveman one, matching the `atuin/tests/`, `bin/tests/`, `zsh/tests/` precedent. A new `caveman/` Stow package pins the plugin's default mode to `off` without disabling the plugin. A new `claude/.claude/output-styles/readable.md` supplies response-structure instructions and is selected via `outputStyle` in `settings.base.json`. Four hex edits in `claude/.claude/themes/catppuccin.json` clear WCAG AA and separate colliding role colours.

**Tech Stack:** GNU Stow, bash, `jq`, `node` (for WCAG luminance maths), Claude Code settings JSON, Catppuccin Mocha palette.

**Spec:** `docs/superpowers/specs/2026-09-18-claude-response-readability-design.md`

## Global Constraints

- **`outputStyle` matches the style file's `name` frontmatter exactly and case-sensitively.** The filename is ignored when `name` is present. A mismatch falls back to the Default style with **no warning and no error**. Verified empirically; see the spec's "Output style name resolution".
- **`keep-coding-instructions: true` is mandatory** in the output style. Without it, Claude Code discards its built-in software-engineering instructions, silently.
- Exact hex values, copied verbatim: `subtle` `#9399b2`, `permission` `#f9e2af`, `merged` `#94e2d5`, `mergedShimmer` `#89dceb`. Background is `#1e1e2e`.
- WCAG thresholds: AA normal text `4.5:1`, AAA `7.0:1`.
- **Never edit `~/.claude/` directly.** All edits happen in the repo; symlinks make them live.
- **Stage specific files only.** Never `git add -A`, `git add .`, `git add -u`, `git commit -a`, or `git commit -am`. Hook-enforced.
- Conventional commits, `type(scope): description`. Scope names the affected component: `claude` for changes to the `claude/` package (124 uses in history), `caveman` for changes confined to the new `caveman/` package — a peer of `herdr` (18 uses) and `ghostty` (6). Never use `spec`, `plan`, `docs`, or the repo name.
- Every commit message ends with the `Co-Authored-By` trailer shown in each commit step.
- Test scripts follow the repo convention: `#!/usr/bin/env bash`, `set -uo pipefail`, an `ok`/`bad` counter, a summary line, `exit 0` on success and `exit 1` on any failure.
- Comments in shell follow the existing house style: full sentences explaining *why*, not restating the code.

---

### Task 1: Theme contrast floor

Raises the one theme token that fails WCAG AA, and adds the regression test that keeps every future theme edit above the floor.

**Files:**
- Create: `claude/.claude/tests/theme-contrast/run.sh`
- Modify: `claude/.claude/themes/catppuccin.json` (the `subtle` entry)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `claude/.claude/tests/theme-contrast/run.sh`, an executable test that Task 2 extends with a role-separation block.

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/theme-contrast/run.sh`:

```bash
#!/usr/bin/env bash
# Theme contrast test.
#
# Asserts every foreground token in the custom Catppuccin theme clears the
# WCAG AA floor of 4.5:1 against the theme's own background. The 4.5 figure
# is WCAG's allowance for 20/40 visual acuity; 7.0 (AAA) corresponds to 20/80.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$HERE/../../themes/catppuccin.json"

command -v node >/dev/null 2>&1 || { echo "node required" >&2; exit 2; }
[[ -f "$THEME" ]] || { echo "missing $THEME" >&2; exit 2; }

THEME="$THEME" node <<'NODE'
const fs = require('fs');
const o = JSON.parse(fs.readFileSync(process.env.THEME, 'utf8')).overrides;
const bg = o.background;

// WCAG 2.2 relative luminance, then the contrast ratio of two colours.
function lum(hex) {
  const n = parseInt(hex.slice(1), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
function ratio(a, b) {
  const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

// Tokens naming a background fill rather than drawn text. These are measured
// against the text drawn on them, not against the base background, so the
// floor below does not apply to them.
const FILL = /[Bb]ackground|^diffAdded|^diffRemoved|^selectionBg$|^rate_limit_/;

// inverseText is background-coloured on purpose: it is drawn on top of a
// coloured badge and never on the base background.
const ALLOW_LOW = new Set(['inverseText']);

const AA = 4.5;
let fail = 0;
const ok  = (m) => console.log(`  ok   ${m}`);
const bad = (m) => { console.log(`  FAIL ${m}`); fail = 1; };

for (const [token, hex] of Object.entries(o)) {
  if (typeof hex !== 'string' || !hex.startsWith('#')) continue;
  if (FILL.test(token) || ALLOW_LOW.has(token)) continue;
  const r = ratio(hex, bg);
  const line = `${token.padEnd(38)} ${hex} ${r.toFixed(2).padStart(6)}:1`;
  if (r >= AA) ok(line); else bad(`${line} (want >= ${AA})`);
}

process.exit(fail);
NODE
rc=$?

echo
if [[ $rc -eq 0 ]]; then
  echo "theme-contrast: all passed"
else
  echo "theme-contrast: FAILURES"
fi
exit $rc
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x claude/.claude/tests/theme-contrast/run.sh
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash claude/.claude/tests/theme-contrast/run.sh`

Expected: FAIL. Exactly one failing line, and the summary `theme-contrast: FAILURES`:

```
  FAIL subtle                                 #7f849c   4.44:1 (want >= 4.5)
```

If any token other than `subtle` fails, stop and report — the theme has drifted from what the spec audited.

- [ ] **Step 4: Fix the failing token**

In `claude/.claude/themes/catppuccin.json`, change the `subtle` entry:

```json
    "subtle":        "#9399b2",
```

`#9399b2` is Catppuccin Mocha's Overlay2, so the value stays inside the palette. It measures 5.81:1 against `#1e1e2e`, up from 4.44:1.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash claude/.claude/tests/theme-contrast/run.sh`

Expected: PASS, ending with `theme-contrast: all passed`. The `subtle` line should now read:

```
  ok   subtle                                 #9399b2   5.81:1
```

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/tests/theme-contrast/run.sh claude/.claude/themes/catppuccin.json
git commit -F - <<'EOF'
fix(claude): raise subtle theme token to WCAG AA

The subtle token measured 4.44:1 against the theme background, just under
WCAG AA's 4.5:1 floor for body text. Move it to Catppuccin Overlay2
(#9399b2), which measures 5.81:1 and stays inside the palette.

Add a contrast test that computes WCAG relative luminance for every
foreground token, so future theme edits cannot reintroduce sub-AA text.
Background fills and inverseText are excluded: they are measured against
the text drawn on them, not against the base background.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Theme role separation

Permission prompts and merge markers currently render in the assistant's own colour, so they do not stand out in scrollback. Give them their own hues.

**Files:**
- Modify: `claude/.claude/tests/theme-contrast/run.sh` (append a separation block)
- Modify: `claude/.claude/themes/catppuccin.json` (`permission`, `merged`, `mergedShimmer`)

**Interfaces:**
- Consumes: `claude/.claude/tests/theme-contrast/run.sh` from Task 1, including its `o`, `ok`, `bad`, and `fail` bindings.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Extend the test with the failing assertion**

In `claude/.claude/tests/theme-contrast/run.sh`, insert this block immediately after the `for (const [token, hex] of Object.entries(o))` loop and immediately before `process.exit(fail);`:

```javascript

// Role separation. These pairs appear on screen together, so sharing a hue
// makes them indistinguishable: a permission prompt rendered in the
// assistant's own colour does not read as something awaiting a decision.
// The palette is saturated, so the rule is not "one hue per token" but
// "no shared hue between roles that co-occur".
const SEPARATE = [['claude', 'permission'], ['claude', 'merged']];
for (const [a, b] of SEPARATE) {
  if (!o[a] || !o[b]) {
    bad(`role separation: ${a} or ${b} is missing from the theme`);
  } else if (o[a].toLowerCase() === o[b].toLowerCase()) {
    bad(`${a} and ${b} both use ${o[a]} (must differ)`);
  } else {
    ok(`${a} ${o[a]} separated from ${b} ${o[b]}`);
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash claude/.claude/tests/theme-contrast/run.sh`

Expected: FAIL. The contrast assertions still pass; the two new ones fail:

```
  FAIL claude and permission both use #cba6f7 (must differ)
  FAIL claude and merged both use #cba6f7 (must differ)
```

- [ ] **Step 3: Reassign the colliding tokens**

In `claude/.claude/themes/catppuccin.json`, change these three entries:

```json
    "permission":    "#f9e2af",
```

```json
    "merged":        "#94e2d5",
```

```json
    "mergedShimmer":      "#89dceb",
```

Rationale, so the values are not arbitrary:

- `permission` → `#f9e2af` Yellow (12.91:1, AAA). Yellow reads as "stop and decide". It is shared with `warning`, which rarely co-occurs with a prompt. Peach was rejected: Peach is `bashBorder`, and a permission prompt for a Bash call is exactly when those two appear together.
- `merged` → `#94e2d5` Teal (11.01:1, AAA). Shared with `planMode`, which never appears beside a git merge marker.
- `mergedShimmer` → `#89dceb` Sky (10.54:1, AAA), so the shimmer follows `merged` and the ramp stays coherent.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash claude/.claude/tests/theme-contrast/run.sh`

Expected: PASS, ending with `theme-contrast: all passed`, including:

```
  ok   claude #cba6f7 separated from permission #f9e2af
  ok   claude #cba6f7 separated from merged #94e2d5
```

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/tests/theme-contrast/run.sh claude/.claude/themes/catppuccin.json
git commit -F - <<'EOF'
fix(claude): separate permission and merged from the assistant hue

permission, merged, and claude all rendered in Mauve #cba6f7, so a
permission prompt looked like ordinary assistant output instead of
something awaiting a decision.

Move permission to Yellow #f9e2af and merged to Teal #94e2d5, with
mergedShimmer following to Sky #89dceb. All three clear AAA. Peach was
rejected for permission because Peach is bashBorder, and a permission
prompt for a Bash call is precisely when those two co-occur.

The palette has no unused accents left, so the test asserts the narrower
rule these edits satisfy: no shared hue between roles that appear on
screen together.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Caveman default off

Stop prose compression at its source, while keeping the plugin enabled so its `cavecrew` agents survive.

**Files:**
- Create: `caveman/.config/caveman/config.json`
- Create: `caveman/tests/caveman-default-off/run.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a stowable `caveman/` Stow package. No later task depends on it.

- [ ] **Step 1: Write the failing test**

Create `caveman/tests/caveman-default-off/run.sh`:

```bash
#!/usr/bin/env bash
# caveman default-mode test.
#
# The caveman plugin resolves its level in this order:
#   CAVEMAN_DEFAULT_MODE env
#   -> repo-local .caveman/config.json or .caveman.json, walking up from cwd
#   -> user config (~/.config/caveman/config.json)
#   -> 'full'
#
# The stowed user config pins 'off'. Each assertion below guards one way a
# higher-priority source could silently override it.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
CONFIG="$REPO/caveman/.config/caveman/config.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

# The stowed user config must pin the default to 'off'. 'off' is a member of
# the plugin's VALID_MODES, so it is accepted rather than ignored as garbage.
if [[ ! -f "$CONFIG" ]]; then
  bad "missing $CONFIG"
elif ! jq empty "$CONFIG" 2>/dev/null; then
  bad "$CONFIG is not valid JSON"
else
  mode="$(jq -r '.defaultMode // empty' "$CONFIG")"
  if [[ "$mode" == "off" ]]; then
    ok "user config defaultMode = off"
  else
    bad "user config defaultMode = '${mode:-<unset>}' (want off)"
  fi
fi

# A repo-local config outranks the user config, so one committed anywhere in
# this repo would silently re-enable compression for every session run here.
repo_local="$(cd "$REPO" && git ls-files -- \
  '.caveman.json' '*/.caveman.json' \
  '.caveman/config.json' '*/.caveman/config.json')"
if [[ -z "$repo_local" ]]; then
  ok "no repo-local caveman config tracked"
else
  bad "repo-local caveman config outranks user config: ${repo_local//$'\n'/ }"
fi

# The environment variable outranks every file, so an export in the shell
# config would defeat the user config on every machine that stows zsh.
if grep -rn 'CAVEMAN_DEFAULT_MODE' "$REPO/zsh" >/dev/null 2>&1; then
  bad "CAVEMAN_DEFAULT_MODE set in the zsh package (env outranks user config)"
else
  ok "CAVEMAN_DEFAULT_MODE not set in zsh package"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "caveman-default-off: all passed"
else
  echo "caveman-default-off: FAILURES"
fi
exit $fail
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x caveman/tests/caveman-default-off/run.sh
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash caveman/tests/caveman-default-off/run.sh`

Expected: FAIL, with the config-missing assertion failing and the other two passing:

```
  FAIL missing /Users/ben/workspace/dotfiles/.claude/worktrees/claude-response-readability/caveman/.config/caveman/config.json
  ok   no repo-local caveman config tracked
  ok   CAVEMAN_DEFAULT_MODE not set in zsh package
```

- [ ] **Step 4: Create the Stow package**

```bash
mkdir -p caveman/.config/caveman
```

Create `caveman/.config/caveman/config.json`:

```json
{
  "defaultMode": "off"
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash caveman/tests/caveman-default-off/run.sh`

Expected: PASS, ending with `caveman-default-off: all passed`.

- [ ] **Step 6: Stow the package, dry run first**

```bash
stow -n -v -d "$PWD" -t ~ caveman
```

Expected: a `LINK: .config/caveman => ...` line and nothing else. No conflicts.

No `mkdir -p ~/.config/caveman` pre-step is wanted here. Unlike `herdr`, the plugin writes only `config.json` to this directory — all runtime state (`.caveman-active`, `.caveman-sessions/`, `.caveman-*.jsonl`) goes to `~/.claude/` — so tree-folding into a directory symlink is safe and keeps the package self-contained.

- [ ] **Step 7: Do NOT apply the stow from the worktree**

Stow resolves links relative to the package directory it is given, so
applying it here produces:

```
LINK: .config/caveman => ../workspace/dotfiles/.claude/worktrees/claude-response-readability/caveman/.config/caveman
```

That target disappears when the worktree is removed. The real stow happens
from the main checkout after merge — see Task 6, "Post-merge activation".

- [ ] **Step 8: Commit**

```bash
git add caveman/.config/caveman/config.json caveman/tests/caveman-default-off/run.sh
git commit -F - <<'EOF'
feat(claude): default caveman prose compression to off

The caveman plugin activated at level 'full' on every session, dropping
articles, preferring fragments, and banning tables. The table ban worked
directly against readability by pushing comparisons into prose.

Pin the plugin's default mode to off through a new caveman Stow package at
~/.config/caveman/config.json. The plugin stays enabled, so the
caveman:cavecrew agents that CLAUDE.md depends on keep working and
/caveman full still activates compression for a single session.

The config directory is config-only -- all runtime state is written to
~/.claude/ -- so Stow can tree-fold it safely, unlike herdr.

Test the two higher-priority sources that would silently override the
default: a repo-local .caveman config, and a CAVEMAN_DEFAULT_MODE export
in the zsh package.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Output style

The core deliverable: response-structure instructions that Claude Code sends with every request.

**Files:**
- Create: `claude/.claude/output-styles/readable.md`
- Create: `claude/.claude/tests/output-style/run.sh`
- Modify: `claude/.claude/settings.base.json` (add `outputStyle` after `defaultMode`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the style `name` value `Readable`, which `settings.base.json` must match byte-for-byte.

- [ ] **Step 1: Write the failing test**

Create `claude/.claude/tests/output-style/run.sh`:

```bash
#!/usr/bin/env bash
# Output-style wiring test.
#
# outputStyle resolves against the style file's `name` frontmatter, matched
# exactly and case-sensitively; the filename is ignored when `name` is
# present. A mismatch makes Claude Code fall back to the Default style with
# no warning and no error, so this agreement is asserted rather than
# eyeballed. Verified empirically -- see the design spec.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$HERE/../.." && pwd)"
STYLE="$CLAUDE_DIR/output-styles/readable.md"
BASE="$CLAUDE_DIR/settings.base.json"
OVERLAY="$CLAUDE_DIR/settings.overlay.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[[ -f "$BASE" ]] || { echo "missing $BASE" >&2; exit 2; }

fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

if [[ ! -f "$STYLE" ]]; then
  bad "missing $STYLE"
  echo
  echo "output-style: FAILURES"
  exit 1
fi

# Read one scalar out of the leading --- frontmatter block.
fm() {
  awk -v key="$1" '
    NR == 1 && $0 == "---" { inblock = 1; next }
    inblock && $0 == "---" { exit }
    inblock {
      idx = index($0, ":")
      if (idx == 0) next
      k = substr($0, 1, idx - 1)
      v = substr($0, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k == key) { print v; exit }
    }
  ' "$STYLE"
}

# Without this field a custom style discards Claude Code's built-in
# software-engineering instructions, and nothing reports that it happened.
kci="$(fm keep-coding-instructions)"
if [[ "$kci" == "true" ]]; then
  ok "keep-coding-instructions = true"
else
  bad "keep-coding-instructions = '${kci:-<unset>}' (want true)"
fi

style_name="$(fm name)"
if [[ -n "$style_name" ]]; then
  ok "style name = $style_name"
else
  bad "style declares no name frontmatter"
fi

# The selection must equal the name exactly. Case matters: a lowercased
# value resolves to nothing and falls back to Default.
base_sel="$(jq -r '.outputStyle // empty' "$BASE")"
if [[ -n "$style_name" && "$base_sel" == "$style_name" ]]; then
  ok "settings.base.json outputStyle = $base_sel"
else
  bad "settings.base.json outputStyle = '${base_sel:-<unset>}' (want '${style_name:-<name unset>}', exact case)"
fi

# claude-sync folds the overlay over the base, so confirm the overlay does
# not change the selection out from under us.
if [[ -f "$OVERLAY" ]]; then
  merged_sel="$(jq -s -r '(.[0] * .[1]).outputStyle // empty' "$BASE" "$OVERLAY")"
  if [[ -n "$style_name" && "$merged_sel" == "$style_name" ]]; then
    ok "survives the base+overlay merge as $merged_sel"
  else
    bad "overlay changes outputStyle to '${merged_sel:-<unset>}'"
  fi
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "output-style: all passed"
else
  echo "output-style: FAILURES"
fi
exit $fail
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x claude/.claude/tests/output-style/run.sh
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash claude/.claude/tests/output-style/run.sh`

Expected: FAIL with exactly:

```
  FAIL missing /Users/ben/workspace/dotfiles/.claude/worktrees/claude-response-readability/claude/.claude/output-styles/readable.md

output-style: FAILURES
```

- [ ] **Step 4: Create the output style**

```bash
mkdir -p claude/.claude/output-styles
```

Create `claude/.claude/output-styles/readable.md`:

````markdown
---
name: Readable
description: Structured, scannable technical prose for terminal reading
keep-coding-instructions: true
---

# Readable

Optimize every response for a reader scanning a terminal. A response
succeeds when the reader finds the answer without rereading it.

## Order

Lead with the answer, the result, or the decision. Reasoning, alternatives,
and caveats come after. Never open by restating the question or by
summarizing what you are about to say.

If the response reports work, the first line says what changed. If it
answers a question, the first line answers it.

## Paragraphs

One idea per paragraph, four sentences at most, blank line between
paragraphs. A wall of text is unreadable in a terminal regardless of how
good its content is.

Keep connectives intact — "because", "so that", "rather than". Dropping
them forces the reader to reconstruct the logic, which is where technical
prose becomes hard to read.

## Structure

Add `##` headings once a response passes roughly 15 lines, or whenever it
covers more than one topic. Below that threshold headings are noise.

Use a bulleted list for parallel items. Use a table when comparing two or
more things across the same dimensions. Nest at most two levels — deeper
nesting does not survive terminal wrapping.

Bold the term being defined or the value being changed, never a whole
sentence.

## Code and paths

Fence every code block with its language so it receives syntax
highlighting. Reserve fenced blocks for text the reader would copy:
commands, file contents, exact output. Never fence prose.

Use inline code for identifiers, paths, flags, and literal values.
Reference source locations as `path/to/file.ext:42` so they are clickable.

Quote the shortest decisive line of an error, never the whole log.

## Words

Prefer the common word over the rare one: "use" not "utilize", "start"
not "commence", "about" not "regarding". Keep sentences to one main clause
where the meaning allows it. No idioms and no figurative phrasing — they
cost a non-native reader a lookup and gain nothing.

This governs ordinary prose only. Technical terms stay exact and stay
unabbreviated: identifiers, API and tool names, CLI commands, file paths,
config keys, commit-type keywords, and error strings are reproduced
verbatim, never simplified, never paraphrased, never swapped for a
friendlier synonym.

## Endings

End with the next action or the open question. Do not end with a summary
of what you just said.

## Uncertainty

Say what you verified and what you did not, in one sentence, at the point
where it matters. Do not spread hedges through the prose.
````

- [ ] **Step 5: Select the style in settings**

In `claude/.claude/settings.base.json`, add the `outputStyle` key immediately after the `defaultMode` line, so the head of the file reads:

```json
  "model": "opus[1m]",
  "theme": "custom:catppuccin",
  "effortLevel": "auto",
  "defaultMode": "auto",
  "outputStyle": "Readable",
  "permissions": {
```

The value is `Readable` with a capital R, matching the style's `name` frontmatter byte-for-byte. `readable` would silently do nothing.

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash claude/.claude/tests/output-style/run.sh`

Expected: PASS, ending with `output-style: all passed`:

```
  ok   keep-coding-instructions = true
  ok   style name = Readable
  ok   settings.base.json outputStyle = Readable
  ok   survives the base+overlay merge as Readable
```

- [ ] **Step 7: Do NOT run `claude-sync` from the worktree**

`claude-sync` hardcodes `DOTFILES="${DOTFILES_DIR:-$HOME/workspace/dotfiles}"`,
so it always reads the main checkout and will not see worktree-only changes.
Running it here would regenerate `~/.claude/settings.json` from the old base
and silently do nothing useful. It belongs in Task 6, "Post-merge activation".

- [ ] **Step 8: Optional live smoke check, with a known limitation**

The style is not stowed yet, so it is not discoverable at its package path.
A project-level copy is discovered, and can be used to exercise it:

```bash
mkdir -p .claude/output-styles
cp claude/.claude/output-styles/readable.md .claude/output-styles/readable.md
CAVEMAN_DEFAULT_MODE=off claude -p "In one sentence, what does git rebase do?" \
  --settings '{"outputStyle":"Readable"}'
rm -f .claude/output-styles/readable.md && rmdir .claude/output-styles
```

**This check is weak and must not be treated as verification.** `Readable`'s
rules are stylistic, so a short answer exercises almost none of them and the
correct and incorrect `outputStyle` values produce near-identical output. The
resolution semantics were already proven by the marker probe recorded in the
spec; the static assertion in Step 6 is what guards them here.

`CAVEMAN_DEFAULT_MODE=off` is required for this check to mean anything at
all: with caveman active the response comes back fragmented even when the
style has loaded, because caveman's hook injection overrides the style.

- [ ] **Step 9: Commit**

```bash
git add claude/.claude/output-styles/readable.md claude/.claude/tests/output-style/run.sh claude/.claude/settings.base.json
git commit -F - <<'EOF'
feat(claude): add Readable output style for response structure

Response shape had no configuration at all: no output style existed and
settings.base.json set no outputStyle, so structure was entirely default.
Output styles are the mechanism Claude Code designates for this; CLAUDE.md
is for project and codebase instructions.

Add a Readable style covering answer-first ordering, paragraph size,
heading thresholds, table and nesting limits, code-fence discipline, and
plain-language word choice that exempts technical terms.

Two fields fail silently if wrong, so both are asserted by test:
keep-coding-instructions must be true or the built-in software-engineering
instructions are discarded, and outputStyle must equal the style's name
frontmatter exactly and case-sensitively or Claude Code falls back to
Default with no error.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Documentation

Record the non-obvious constraints in `CLAUDE.md` so the next session does not rediscover them.

**Files:**
- Modify: `CLAUDE.md` (Stow gotchas list, Package conventions list, new subsection under Claude Code settings)

**Interfaces:**
- Consumes: the file paths and behaviours established in Tasks 1–4.
- Produces: nothing.

- [ ] **Step 1: Add the Stow gotcha**

In `CLAUDE.md`, in the `# Stow gotchas` list, insert this bullet immediately after the `**Before stowing `herdr`**` bullet:

```markdown
- **`caveman` needs no pre-`mkdir`**: `~/.config/caveman/` holds only `config.json`; all runtime state (`.caveman-active`, `.caveman-sessions/`, `.caveman-*.jsonl`) is written to `~/.claude/`. Tree-folding into a directory symlink is therefore safe, unlike `herdr`, which rewrites its own config at runtime.
```

- [ ] **Step 2: Add the package convention**

In `CLAUDE.md`, in the `# Package conventions` list, append this bullet after the bullet describing the `codex/` package:

```markdown
- The `caveman/` package stows one file, `~/.config/caveman/config.json`, pinning the caveman plugin's default mode to `off`. See "Response readability".
```

- [ ] **Step 3: Add the Response readability subsection**

In `CLAUDE.md`, inside the `# Claude Code settings (layered merge)` section, add this subsection immediately before the `## Permission posture` subsection:

```markdown
## Response readability

Response shape is configured through a Claude Code output style, not through
`CLAUDE.md`. The style lives at `claude/.claude/output-styles/readable.md`
and is selected by `"outputStyle": "Readable"` in `settings.base.json`.

Two constraints, both silent failures when broken:

- `outputStyle` matches the style's `name` frontmatter **exactly and
  case-sensitively**. The filename is ignored when `name` is present. A
  mismatch falls back to the Default style with no warning and no error.
- `keep-coding-instructions: true` is mandatory. Without it a custom style
  discards Claude Code's built-in software-engineering instructions.

Both are asserted by `claude/.claude/tests/output-style/run.sh`. To check a
style change without touching stowed config, pass settings inline:
`claude -p "what is 2+2" --settings '{"outputStyle":"Readable"}'`.

Prose compression from the `caveman` plugin is defaulted off through the
stowed `caveman/.config/caveman/config.json` (`{"defaultMode": "off"}`). The
plugin stays enabled, so the `caveman:cavecrew` agents and `caveman:*` skills
stay available and `/caveman full` still activates compression for one
session. Resolution order is the `CAVEMAN_DEFAULT_MODE` env var, then a
repo-local `.caveman/config.json` or `.caveman.json` found by walking up from
the working directory, then the user config, then `full` -- so a stray
repo-local file or an exported env var silently overrides the default.
`caveman/tests/caveman-default-off/run.sh` guards all three.

Theme contrast and role separation are guarded by
`claude/.claude/tests/theme-contrast/run.sh`, which asserts every foreground
token clears WCAG AA (4.5:1) against the theme background, and that
`permission` and `merged` stay visually distinct from `claude`. The palette
is saturated -- Overlay0 is the only unused shade -- so the rule enforced is
"no shared hue between roles that co-occur", not "one hue per token".

Design: `docs/superpowers/specs/2026-09-18-claude-response-readability-design.md`.
```

- [ ] **Step 4: Verify the three edits landed and nothing else changed**

```bash
git diff --stat CLAUDE.md
grep -n 'caveman' CLAUDE.md
```

Expected: `CLAUDE.md` is the only changed file, and the `caveman` hits cover the Stow gotcha, the package convention, and the Response readability subsection.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -F - <<'EOF'
docs(claude): record response readability configuration

Document where response shape is configured and the two fields that fail
silently: outputStyle must match the style's name frontmatter exactly and
case-sensitively, and keep-coding-instructions must be true.

Record the caveman resolution order, since a repo-local config file or an
exported CAVEMAN_DEFAULT_MODE silently outranks the stowed user config,
and note that the caveman package needs no pre-mkdir because its config
directory receives no runtime writes.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Full verification

Prove nothing else broke, then confirm the change works in a real session.

**Files:** none modified.

**Interfaces:**
- Consumes: every artifact from Tasks 1–5.
- Produces: nothing.

- [ ] **Step 1: Run every test in the suite**

```bash
for t in claude/.claude/tests/*/run.sh; do
  echo "=== $t ==="
  bash "$t" || echo "!!! FAILED: $t"
done
```

Expected: every suite reports all passed. The pre-existing suites are `commit-scope`, `mcp-permission-overlay`, `notify-pane`, `permission-policy`, `read-once`, and `session-lib`; the new ones are `caveman-default-off`, `output-style`, and `theme-contrast`.

`settings.base.json` changed in Task 4, so `mcp-permission-overlay` and `permission-policy` are the ones most likely to surface a regression. If either fails, stop and report before continuing.

- [ ] **Step 2: Confirm the working tree is clean**

```bash
git status --porcelain
```

Expected: empty. Anything listed means a file was created but never staged — most likely a test script or the caveman config.

- [ ] **Step 3: Post-merge activation**

Nothing in Tasks 1–5 is live yet: the theme, the style, and the caveman
config all sit on the worktree branch, and both `stow` and `claude-sync`
target the main checkout. Run these from `~/workspace/dotfiles` **after** the
branch merges to `main`:

```bash
stow -n -v -t ~ caveman
```

Expected: `LINK: .config/caveman => ../workspace/dotfiles/caveman/.config/caveman`,
with no worktree path in it, and no conflicts. Then apply and verify:

```bash
stow -t ~ caveman
readlink -f ~/.config/caveman/config.json
claude-sync
jq -r '.outputStyle' ~/.claude/settings.json
readlink ~/.claude/output-styles
```

Expected: the config path resolves into `~/workspace/dotfiles/caveman/`,
`jq` prints `Readable`, and `~/.claude/output-styles` is a symlink ending in
`dotfiles/claude/.claude/output-styles`.

- [ ] **Step 4: Manual end-to-end check**

Start a fresh Claude Code session and confirm three things:

1. No caveman banner appears in the SessionStart output. Previously every session opened with `CAVEMAN MODE ACTIVE — level: full`.
2. `/output-style` with no argument lists `Readable` and marks it as current.
3. A normal response comes back as paragraphs and headings, with articles and connectives intact, rather than fragments.

Report the outcome of each. Item 1 is the one to watch: if the banner still appears, the stow did not take effect or a higher-priority source is overriding the user config — re-run `bash caveman/tests/caveman-default-off/run.sh` and check `readlink -f ~/.config/caveman/config.json`.
