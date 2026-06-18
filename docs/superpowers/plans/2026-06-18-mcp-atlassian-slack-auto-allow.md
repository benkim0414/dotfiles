# Atlassian + Slack MCP Auto-Allow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-allow every atlassian and slack MCP operation except the five destructive (delete/remove) tools, with the company-specific rules in a separate committed overlay file.

**Architecture:** Narrow the server-agnostic mutation `ask` globs in `settings.base.json` to destructive + high-impact verbs only (so non-destructive atlassian/slack writes no longer match `ask`, which beats `allow`). Add a company overlay (`claude/.claude/settings.overlay.json`) that allows `mcp__atlassian__*` + `mcp__slack__*` and re-gates the five destructive tools by exact name. Teach `claude-sync` to fold-merge the dotfiles overlay ahead of the (optional) claude-skills overlay.

**Tech Stack:** JSON settings, GNU Stow, `jq`, bash (3.2-compatible — macOS).

**Spec:** `docs/superpowers/specs/2026-06-18-mcp-atlassian-slack-auto-allow-design.md`

---

## File Structure

- Modify: `claude/.claude/settings.base.json` — remove 5 non-destructive verb globs from `permissions.ask`.
- Create: `claude/.claude/settings.overlay.json` — company allow/ask rules.
- Create: `claude/.claude/tests/mcp-permission-overlay/run.sh` — merge + precedence assertions.
- Modify: `bin/.local/bin/claude-sync` — layer dotfiles overlay before claude-skills overlay.
- Modify: `CLAUDE.md` — document the layered overlay and narrowed gate.

Commit order keeps every commit green: base narrowing (Task 1) precedes the overlay+test (Task 2), so the test passes the moment it lands.

---

## Task 1: Narrow the base global mutation gate

**Files:**
- Modify: `claude/.claude/settings.base.json` (`permissions.ask`, the `mcp__*__*<verb>*` block)

- [ ] **Step 1: Remove the 5 non-destructive verb globs**

In `claude/.claude/settings.base.json`, replace this exact block:

```json
      "mcp__*__*create*",
      "mcp__*__*delete*",
      "mcp__*__*remove*",
      "mcp__*__*update*",
      "mcp__*__*edit*",
      "mcp__*__*add*",
      "mcp__*__*transition*",
      "mcp__*__*sync*",
      "mcp__*__*deploy*",
      "mcp__*__*apply*",
      "mcp__*__*patch*",
      "mcp__*__*write*",
```

with (drops `create`/`update`/`edit`/`add`/`transition`; keeps destructive `delete`/`remove` and high-impact `sync`/`deploy`/`apply`/`patch`/`write`):

```json
      "mcp__*__*delete*",
      "mcp__*__*remove*",
      "mcp__*__*sync*",
      "mcp__*__*deploy*",
      "mcp__*__*apply*",
      "mcp__*__*patch*",
      "mcp__*__*write*",
```

- [ ] **Step 2: Validate JSON**

Run: `jq empty claude/.claude/settings.base.json && echo OK`
Expected: `OK`

- [ ] **Step 3: Confirm the dropped globs are gone and kept globs remain**

Run:
```bash
jq -r '.permissions.ask[] | select(startswith("mcp__*__"))' claude/.claude/settings.base.json
```
Expected output (exactly these 7 lines, in order):
```
mcp__*__*delete*
mcp__*__*remove*
mcp__*__*sync*
mcp__*__*deploy*
mcp__*__*apply*
mcp__*__*patch*
mcp__*__*write*
```

- [ ] **Step 4: Commit**

```bash
git add claude/.claude/settings.base.json
git commit -m "feat(claude): narrow global MCP mutation gate to destructive verbs

Drop create/update/edit/add/transition from the server-agnostic ask
globs so non-destructive writes are no longer force-prompted. Keep
delete/remove (destructive) and sync/deploy/apply/patch/write
(high-impact). ask>allow means these globs cannot be overridden by an
overlay, so the gate must narrow here for the atlassian/slack overlay to
take effect.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add the company overlay + verification test

**Files:**
- Create: `claude/.claude/settings.overlay.json`
- Create: `claude/.claude/tests/mcp-permission-overlay/run.sh`

- [ ] **Step 1: Write the overlay file**

Create `claude/.claude/settings.overlay.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__atlassian__*",
      "mcp__slack__*"
    ],
    "ask": [
      "mcp__atlassian__jira_delete_issue",
      "mcp__atlassian__jira_remove_issue_link",
      "mcp__atlassian__jira_remove_watcher",
      "mcp__atlassian__confluence_delete_page",
      "mcp__atlassian__confluence_delete_attachment"
    ]
  }
}
```

- [ ] **Step 2: Write the verification test**

Create `claude/.claude/tests/mcp-permission-overlay/run.sh` (bash 3.2-safe — no `mapfile`):

```bash
#!/usr/bin/env bash
# Verifies the atlassian/slack auto-allow-except-destructive policy.
# Merges settings.base.json + settings.overlay.json with the same jq
# semantics as claude-sync, then resolves representative MCP tools through
# Claude Code's deny -> ask -> allow precedence (first match wins).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HERE/../.."
BASE="$CLAUDE_DIR/settings.base.json"
OVERLAY="$CLAUDE_DIR/settings.overlay.json"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[[ -f "$BASE" ]]    || { echo "missing $BASE" >&2; exit 2; }
[[ -f "$OVERLAY" ]] || { echo "missing $OVERLAY" >&2; exit 2; }

jq empty "$BASE"    || { echo "base is not valid JSON" >&2; exit 1; }
jq empty "$OVERLAY" || { echo "overlay is not valid JSON" >&2; exit 1; }

MERGED="$(jq -n --slurpfile base "$BASE" --slurpfile over "$OVERLAY" '
  def merge(b):
    if (type == "array") and (b | type == "array") then
      if all(type == "string") and (b | all(type == "string"))
      then reduce (. + b)[] as $x ([]; if index($x) then . else . + [$x] end)
      else . + b end
    elif (type == "object") and (b | type == "object") then
      reduce (b | to_entries[]) as $e (.;
        if has($e.key) then .[$e.key] |= merge($e.value)
        else . + {($e.key): $e.value} end)
    else b end;
  $base[0] | merge($over[0])
')" || { echo "merge failed" >&2; exit 1; }

DENY=();  while IFS= read -r l; do DENY+=("$l");  done < <(jq -r '.permissions.deny[]?'  <<<"$MERGED")
ASK=();   while IFS= read -r l; do ASK+=("$l");   done < <(jq -r '.permissions.ask[]?'   <<<"$MERGED")
ALLOW=(); while IFS= read -r l; do ALLOW+=("$l"); done < <(jq -r '.permissions.allow[]?' <<<"$MERGED")

anymatch() { local tool="$1"; shift; local p; for p in "$@"; do [[ "$tool" == $p ]] && return 0; done; return 1; }

classify() {
  local tool="$1"
  anymatch "$tool" "${DENY[@]}"  && { echo deny;  return; }
  anymatch "$tool" "${ASK[@]}"   && { echo ask;   return; }
  anymatch "$tool" "${ALLOW[@]}" && { echo allow; return; }
  echo classifier
}

fail=0
expect() {
  local tool="$1" want="$2" got
  got="$(classify "$tool")"
  if [[ "$got" == "$want" ]]; then
    printf '  ok   %-52s -> %s\n' "$tool" "$got"
  else
    printf '  FAIL %-52s -> %s (want %s)\n' "$tool" "$got" "$want"; fail=1
  fi
}

# Bucket A (reads) + Bucket B (non-destructive writes) -> allow
expect mcp__atlassian__jira_get_issue              allow
expect mcp__atlassian__jira_search                 allow
expect mcp__atlassian__jira_create_issue           allow
expect mcp__atlassian__jira_update_issue           allow
expect mcp__atlassian__jira_add_comment            allow
expect mcp__atlassian__jira_transition_issue       allow
expect mcp__atlassian__confluence_create_page      allow
expect mcp__atlassian__confluence_update_page      allow
expect mcp__slack__slack_post_message              allow
expect mcp__slack__slack_reply_to_thread           allow
expect mcp__slack__slack_add_reaction              allow

# Bucket C (destructive) -> ask
expect mcp__atlassian__jira_delete_issue            ask
expect mcp__atlassian__jira_remove_issue_link       ask
expect mcp__atlassian__jira_remove_watcher          ask
expect mcp__atlassian__confluence_delete_page       ask
expect mcp__atlassian__confluence_delete_attachment ask

echo
if [[ $fail -eq 0 ]]; then echo "mcp-permission-overlay: all passed"; else echo "mcp-permission-overlay: FAILURES"; fi
exit $fail
```

- [ ] **Step 3: Make the test executable**

Run: `chmod +x claude/.claude/tests/mcp-permission-overlay/run.sh`

- [ ] **Step 4: Run the test — expect PASS**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: every line `ok`, final line `mcp-permission-overlay: all passed`, exit 0.

(If any Bucket B tool shows `ask`, Task 1's base narrowing was not applied. If a Bucket C tool shows `allow`, it is wrongly listed in the overlay `allow` or missing from `ask`.)

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/settings.overlay.json claude/.claude/tests/mcp-permission-overlay/run.sh
git commit -m "feat(claude): auto-allow atlassian/slack MCP except destructive

Company overlay allows mcp__atlassian__* and mcp__slack__* and re-gates
the five destructive tools (jira delete_issue/remove_issue_link/
remove_watcher, confluence delete_page/delete_attachment) by exact name
in ask, which beats allow. Test merges base+overlay and asserts the
deny->ask->allow resolution for representative tools.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Layer the dotfiles overlay in claude-sync

**Files:**
- Modify: `bin/.local/bin/claude-sync` (variable block + merge block)

- [ ] **Step 1: Update the header comment and overlay variables**

Replace this exact block (the file header lines describing base/overlay/output and the variable assignments):

```bash
# Base settings:   $DOTFILES/claude/.claude/settings.base.json   (always present)
# Overlay:         $CLAUDE_SKILLS_DIR/settings.overlay.json      (optional, from claude-skills)
# Output:          ~/.claude/settings.json                       (generated, not a symlink)
```

with:

```bash
# Base settings:   $DOTFILES/claude/.claude/settings.base.json      (always present)
# Overlays (in merge order, later wins on scalar conflict):
#   1. $DOTFILES/claude/.claude/settings.overlay.json              (company, optional)
#   2. $CLAUDE_SKILLS_DIR/settings.overlay.json                    (claude-skills, optional)
# Output:          ~/.claude/settings.json                          (generated, not a symlink)
```

- [ ] **Step 2: Update the variable assignments**

Replace this exact block:

```bash
DOTFILES="${DOTFILES_DIR:-$HOME/workspace/dotfiles}"
SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/workspace/claude-skills}"
BASE="$DOTFILES/claude/.claude/settings.base.json"
OVERLAY="$SKILLS/settings.overlay.json"
OUTPUT="$HOME/.claude/settings.json"
```

with:

```bash
DOTFILES="${DOTFILES_DIR:-$HOME/workspace/dotfiles}"
SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/workspace/claude-skills}"
BASE="$DOTFILES/claude/.claude/settings.base.json"
DOTFILES_OVERLAY="$DOTFILES/claude/.claude/settings.overlay.json"
SKILLS_OVERLAY="$SKILLS/settings.overlay.json"
OUTPUT="$HOME/.claude/settings.json"
```

- [ ] **Step 3: Replace the merge block**

Replace this exact block:

```bash
# Merge settings: base + overlay -> output
if [[ -f "$OVERLAY" ]]; then
  jq -n --slurpfile base "$BASE" --slurpfile over "$OVERLAY" '
    def merge(b):
      if (type == "array") and (b | type == "array") then
        if all(type == "string") and (b | all(type == "string"))
        then reduce (. + b)[] as $x ([]; if index($x) then . else . + [$x] end)
        else . + b
        end
      elif (type == "object") and (b | type == "object") then
        reduce (b | to_entries[]) as $e (.;
          if has($e.key) then .[$e.key] |= merge($e.value)
          else . + {($e.key): $e.value} end)
      else b end;
    $base[0] | merge($over[0])
  ' > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
  echo "settings.json: merged base + overlay -> $OUTPUT"
else
  cp "$BASE" "$OUTPUT"
  echo "settings.json: copied base (no overlay found) -> $OUTPUT"
fi
```

with:

```bash
# Merge settings: base + ordered overlays -> output.
# Overlays are folded left-to-right; later overlays win on scalar conflicts.
overlays=()
[[ -f "$DOTFILES_OVERLAY" ]] && overlays+=("$DOTFILES_OVERLAY")
[[ -f "$SKILLS_OVERLAY" ]]   && overlays+=("$SKILLS_OVERLAY")

if (( ${#overlays[@]} > 0 )); then
  jq -n \
     --slurpfile base "$BASE" \
     --slurpfile overlays <(jq -s '.' "${overlays[@]}") '
    def merge(b):
      if (type == "array") and (b | type == "array") then
        if all(type == "string") and (b | all(type == "string"))
        then reduce (. + b)[] as $x ([]; if index($x) then . else . + [$x] end)
        else . + b
        end
      elif (type == "object") and (b | type == "object") then
        reduce (b | to_entries[]) as $e (.;
          if has($e.key) then .[$e.key] |= merge($e.value)
          else . + {($e.key): $e.value} end)
      else b end;
    reduce $overlays[0][] as $o ($base[0]; merge($o))
  ' > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
  echo "settings.json: merged base + ${#overlays[@]} overlay(s) -> $OUTPUT"
else
  cp "$BASE" "$OUTPUT"
  echo "settings.json: copied base (no overlay found) -> $OUTPUT"
fi
```

- [ ] **Step 4: Syntax check**

Run: `bash -n bin/.local/bin/claude-sync && echo OK`
Expected: `OK`

- [ ] **Step 5: Dry merge against worktree files (no stow, no live write)**

This reuses the new merge logic without running `claude-sync` (which would stow the main repo and overwrite live settings). It folds base + the worktree overlay and confirms the merged `allow`/`ask` are present:

```bash
jq -n \
  --slurpfile base "claude/.claude/settings.base.json" \
  --slurpfile overlays <(jq -s '.' "claude/.claude/settings.overlay.json") '
  def merge(b):
    if (type=="array") and (b|type=="array") then
      if all(type=="string") and (b|all(type=="string"))
      then reduce (.+b)[] as $x ([]; if index($x) then . else .+[$x] end)
      else .+b end
    elif (type=="object") and (b|type=="object") then
      reduce (b|to_entries[]) as $e (.; if has($e.key) then .[$e.key]|=merge($e.value) else .+{($e.key):$e.value} end)
    else b end;
  reduce $overlays[0][] as $o ($base[0]; merge($o))
' | jq '{allow: (.permissions.allow|map(select(test("atlassian|slack")))), ask: (.permissions.ask|map(select(test("delete|remove"))))}'
```
Expected: `allow` includes `mcp__atlassian__*` and `mcp__slack__*`; `ask` includes the 5 destructive exact names plus `mcp__*__*delete*` and `mcp__*__*remove*`.

- [ ] **Step 6: Commit**

```bash
git add bin/.local/bin/claude-sync
git commit -m "feat(claude): layer dotfiles overlay in claude-sync

Fold-merge base + claude/.claude/settings.overlay.json + the optional
claude-skills overlay (in that order) into settings.json. Dotfiles
overlay always applies; claude-skills still merges when present and wins
on scalar conflicts.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Document the policy

**Files:**
- Modify: `CLAUDE.md` ("Claude Code settings (dual-repo merge)" and "Permission posture" sections)

- [ ] **Step 1: Update the "dual-repo merge" intro**

In `CLAUDE.md`, replace this exact block:

```markdown
# Claude Code settings (dual-repo merge)

Base settings live in `claude/.claude/settings.base.json`. Work-specific
additions live in `~/workspace/claude-skills/settings.overlay.json`.

Run `claude-sync` after editing either file to regenerate `~/.claude/settings.json`.
The script deep-merges arrays (concatenate + deduplicate) and objects (overlay wins).
Without claude-skills cloned, it copies the base as-is.
```

with:

```markdown
# Claude Code settings (layered merge)

Base settings live in `claude/.claude/settings.base.json`. Overlays are
folded on top in order (later wins on scalar conflict):

1. `claude/.claude/settings.overlay.json` -- company overlay, committed
   to this repo (e.g. atlassian/slack MCP auto-allow). Always applies.
2. `~/workspace/claude-skills/settings.overlay.json` -- claude-skills
   overlay, optional. Merges when the repo is cloned.

Run `claude-sync` after editing any of them to regenerate
`~/.claude/settings.json`. The script deep-merges arrays (concatenate +
deduplicate) and objects (overlay wins). With no overlay present it
copies the base as-is.
```

- [ ] **Step 2: Add the atlassian/slack policy note under "Permission posture"**

In `CLAUDE.md`, find this exact bullet under "Permission posture":

```markdown
- `ask` rules still gate MCP mutations: the `mcp__*__*create*`,
  `*delete*`, `*update*`, `*write*` (etc.) globs, plus two destructive
  context-mode tools --
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub).
```

Replace it with:

```markdown
- `ask` rules gate destructive + high-impact MCP mutations: the
  `mcp__*__*delete*`, `*remove*`, `*sync*`, `*deploy*`, `*apply*`,
  `*patch*`, `*write*` globs, plus two destructive context-mode tools --
  `mcp__plugin_context-mode_context-mode__ctx_purge` (wipes the FTS5
  knowledge base, irreversible) and
  `mcp__plugin_context-mode_context-mode__ctx_upgrade` (pulls, builds,
  and installs from GitHub). The non-destructive write verbs
  (`create`/`update`/`edit`/`add`/`transition`) are intentionally NOT
  globally gated -- under `defaultMode: auto` they fall to the
  classifier, and the company overlay auto-allows them for atlassian and
  slack.
- atlassian + slack MCP posture (company overlay,
  `claude/.claude/settings.overlay.json`): `mcp__atlassian__*` and
  `mcp__slack__*` are auto-allowed; the five destructive tools
  (`jira_delete_issue`, `jira_remove_issue_link`, `jira_remove_watcher`,
  `confluence_delete_page`, `confluence_delete_attachment`) are re-gated
  by exact name in `ask` (ask beats allow). Verified by
  `claude/.claude/tests/mcp-permission-overlay/run.sh`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document atlassian/slack MCP auto-allow policy

Record the layered overlay order (base + dotfiles overlay + claude-skills
overlay) and the narrowed global mutation gate plus the
auto-allow-except-destructive posture for atlassian and slack.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Run the test suite for the new policy**

Run: `bash claude/.claude/tests/mcp-permission-overlay/run.sh`
Expected: `mcp-permission-overlay: all passed`, exit 0.

- [ ] **Confirm no other test regressed**

Run: `bash claude/.claude/tests/permission-policy/run.sh && bash claude/.claude/tests/commit-scope/run.sh 2>/dev/null; echo "done"`
Expected: existing suites still pass (unaffected by these changes).

- [ ] **Note for the user:** `claude-sync` regenerates the live
  `~/.claude/settings.json` from the **main** repo, so the new policy
  goes live only after this branch is merged to main and the user runs
  `claude-sync`. Do not run `claude-sync` from the worktree (it stows the
  main repo and would not reflect these changes).

---

## Self-Review

**Spec coverage:** Component 1 (narrow base) -> Task 1. Component 2 (overlay) -> Task 2 Step 1. Component 3 (claude-sync layering) -> Task 3. Component 4 (docs) -> Task 4. Verification (jq validity, precedence assertions, committed test) -> Task 2 Step 2 + Final verification. All spec sections covered.

**Placeholder scan:** No TBD/TODO; every code/JSON/command step carries full content.

**Type/name consistency:** The 5 destructive tool names are identical across spec, overlay (Task 2), test (Task 2), and docs (Task 4): `jira_delete_issue`, `jira_remove_issue_link`, `jira_remove_watcher`, `confluence_delete_page`, `confluence_delete_attachment`. The kept base globs (`delete`/`remove`/`sync`/`deploy`/`apply`/`patch`/`write`) match between Task 1 and the Task 4 docs bullet. The jq `merge` function is byte-identical between `claude-sync` (Task 3) and the test (Task 2).
