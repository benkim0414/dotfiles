# Claude Code response readability — design

Date: 2026-09-18
Status: approved, ready for implementation plan

## Problem

Claude Code responses are hard to read. The reported failure modes are
structure/density and visual/colour, with a request to diagnose rather than
assume a cause.

Three surfaces were investigated: the terminal/Claude Code colour theme, the
response structure configuration, and the always-on prose compression supplied
by the `caveman` plugin.

## Diagnosis

### The theme is not the problem

A contrast audit of `claude/.claude/themes/catppuccin.json` against its own
`background` (`#1e1e2e`) found 56 of 58 foreground tokens at WCAG AAA (7:1 or
better). Only two fall below AA:

- `subtle` `#7f849c` at **4.44:1**, marginally under the 4.5:1 floor for body
  text.
- `inverseText` `#1e1e2e` at 1:1, which is a false positive — it is
  background-coloured by design, for text drawn on a coloured badge.

All diff fills and message backgrounds clear 5.6:1 against body text. WCAG's
own rationale sets 4.5:1 for 20/40 acuity and 7:1 for 20/80, so the theme is
already comfortably placed. This is a one-value fix, not a redesign.

### Caveman compression is the dominant cost

The `caveman@caveman` plugin is enabled in `settings.base.json` and registers
two hooks in its own `plugin.json`:

- `SessionStart` → `src/hooks/caveman-activate.js`
- `UserPromptSubmit` → `src/hooks/caveman-mode-tracker.js`

With no user or repo config present, the level resolves to `full`, which drops
articles, prefers fragments over sentences, and bans decorative tables. The
banned-tables rule matters as much as the sentence compression: it pushes
comparisons into prose, the densest possible form, which works directly against
the reported density complaint.

Dropped connectives ("because", "so that", "rather than") are the specific
readability cost. The reader must reconstruct the logical relation, and that
reconstruction is where a three-clause technical explanation becomes hard to
read.

### No response-structure configuration exists

There is no `output-styles/` directory in the repo or in `~/.claude/`, and no
`outputStyle` key in `settings.base.json`. Response shape is entirely default.
The `Response style` section of `claude/.claude/CLAUDE.md` is three bullets
about explaining config choices.

## Research

### Output styles are the sanctioned lever

Per the Claude Code documentation, output styles "change how Claude responds,
not what Claude knows" and set "role, tone, and output format for every
response". The same page routes project and codebase instructions to CLAUDE.md
instead. Response shape is therefore not a CLAUDE.md concern by design.

Verified mechanics:

- Style files live in an `output-styles/` directory. Frontmatter accepts
  `name`, `description`, `keep-coding-instructions`, `force-for-plugin`.
- **A custom style discards Claude Code's built-in software-engineering
  instructions unless `keep-coding-instructions: true`.** This fails silently.
- Selection persists through the `outputStyle` settings key. The
  `/output-style` picker writes it to project-local `settings.local.json`, but
  the key is valid in any settings file, so `settings.base.json` plus
  `claude-sync` is the correct home for a cross-device default.

Not verified: the docs page lists "four additional built-in output styles" but
the fetched content truncated after `Proactive`. `/output-style concise` is
confirmed valid. The remaining two names are unknown. Nothing in this design
depends on them.

### Output style name resolution

The documentation does not state whether `outputStyle` resolves against the
style's filename or its `name` frontmatter. Settled empirically with a probe
style whose two identifiers were made deliberately different — filename
`zzprobe.md`, frontmatter `name: QQProbe` — instructed to emit a unique marker
token. Each candidate value was then run through
`claude -p "what is 2+2" --settings '{"outputStyle":"<value>"}'`:

| Value | Corresponds to | Marker emitted |
| --- | --- | --- |
| `QQProbe` | `name` frontmatter, exact | **yes** |
| `zzprobe` | filename stem | no |
| `qqprobe` | `name`, lowercased | no |

**`outputStyle` matches the `name` frontmatter exactly and case-sensitively.**
The filename is irrelevant once `name` is present.

Two consequences for implementation:

1. With `name: Readable`, the setting must be `"outputStyle": "Readable"`.
   Writing `"readable"` would silently do nothing.
2. **Failure is silent.** Both non-matching values produced a normal answer
   with no warning and no error — Claude Code falls back to the Default style.
   There is no signal distinguishing "style applied" from "style name wrong",
   which is why this is asserted by test rather than left to inspection.

The probe also confirmed that a project-level `.claude/output-styles/`
directory is discovered, alongside the user-level `~/.claude/output-styles/`
this design uses.

### Caveman can be defaulted off without losing cavecrew

`src/hooks/caveman-config.js` documents and implements this resolution order:

```
1. CAVEMAN_DEFAULT_MODE environment variable
2. Repo-local config, walking up from cwd to filesystem root:
     <dir>/.caveman/config.json   (wins)
     <dir>/.caveman.json
3. User config defaultMode field:
     $XDG_CONFIG_HOME/caveman/config.json   (if XDG_CONFIG_HOME set)
     ~/.config/caveman/config.json          (macOS / Linux fallback)
     %APPDATA%\caveman\config.json          (Windows fallback)
4. 'full'
```

`VALID_MODES` includes `'off'`, and `readModeFromConfigFile` validates
`defaultMode` against that list, so `{"defaultMode": "off"}` is accepted rather
than silently ignored.

This matters because `claude/.claude/CLAUDE.md` instructs the use of
`caveman:cavecrew` for compressed delegation. Disabling the plugin outright
would remove those agents. Setting a user-level default of `off` keeps the
plugin enabled, keeps the `cavecrew` agents and `caveman:*` skills available,
and leaves `/caveman full` usable on demand for a single session.

### The config directory is safe for Stow

`getConfigDir()` resolves to `~/.config/caveman/` and holds only `config.json`.
All runtime state is written to `claudeDir` (`~/.claude/`), confirmed present on
this machine: `.caveman-active`, `.caveman-active.prev`, `.caveman-sessions/`,
`.caveman-history.jsonl`, `.caveman-mode-log.jsonl`,
`.caveman-statusline-suffix`.

This is the decisive difference from `herdr`, which rewrites its own
`config.toml` at runtime and therefore cannot be direct-stowed. `caveman`'s
config directory receives no runtime writes, so a Stow-folded directory symlink
is safe.

### Stow folding precedent under ~/.claude

`~/.claude/` is a real directory. Within it, `lib`, `tests`, and `docs` are
stow-folded directory symlinks into the repo, because Claude Code only reads
them. `hooks` and `themes` are real directories. Individual files such as
`statusline.sh` stow as file symlinks.

`output-styles/` follows the `lib`/`tests`/`docs` pattern: Claude Code reads it
and never writes to it — the `/output-style` picker writes its *selection* to
`settings.local.json`, not into the styles directory. Folding is therefore
correct and needs no `mkdir` pre-step.

## Design

Three independent changes, each revertable on its own.

### 1. Caveman default off — new `caveman/` Stow package

```
caveman/.config/caveman/config.json  →  ~/.config/caveman/config.json
```

```json
{ "defaultMode": "off" }
```

The plugin stays enabled in `settings.base.json`. No change to
`enabledPlugins` or `extraKnownMarketplaces`.

### 2. Custom output style — new directory in the `claude/` package

```
claude/.claude/output-styles/readable.md  →  ~/.claude/output-styles/readable.md
```

Selection in `claude/.claude/settings.base.json`:

```json
"outputStyle": "Readable"
```

The value is the style's `name` frontmatter, matched exactly and
case-sensitively — see "Output style name resolution" below. It is **not** the
filename stem.

`outputStyle` is a scalar, so the existing `claude-sync` deep-merge handles it
with overlay-wins semantics. No overlay sets it today.

Full style content:

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

### 3. Theme edits — `claude/.claude/themes/catppuccin.json`

The palette is saturated. After `subtle` takes Overlay2, the only unused
Catppuccin shade is Overlay0 `#6c7086`. Role separation must reassign accents
already in use, not draw from a free reservoir.

Most duplicate hexes are intentional. Excluding the `rainbow_*` and
`*_FOR_SUBAGENTS_ONLY` enumerations, the remaining duplicates are largely a
deliberate warm/cool shimmer ramp: `warningShimmer` is Peach because `warning`
is Yellow; `rememberShimmer` is Rosewater because `remember` is Pink.

The operative rule is therefore **not** "one hue per token" but: *never let two
roles share a hue when they appear on screen together.* By that test, four
edits are warranted:

| Token | Current | New | Ratio vs `#1e1e2e` | Rationale |
| --- | --- | --- | --- | --- |
| `subtle` | `#7f849c` Overlay1 | `#9399b2` Overlay2 | 4.44 → **5.81** (AA) | Clears the 4.5 floor for body text |
| `permission` | `#cba6f7` Mauve | `#f9e2af` Yellow | **12.91** (AAA) | Permission prompts currently render in the assistant's own colour. Yellow reads as "stop and decide". Shares with `warning`, which rarely co-occurs with a prompt. |
| `merged` | `#cba6f7` Mauve | `#94e2d5` Teal | **11.01** (AAA) | Same collision, lower frequency. Shares with `planMode`, which never appears beside a git merge marker. |
| `mergedShimmer` | `#f5c2e7` Pink | `#89dceb` Sky | **10.54** (AAA) | Follows `merged` so the shimmer ramp stays coherent. |

Two changes were considered and **rejected**:

- **Peach for `permission`.** Peach is `bashBorder`, and a permission prompt
  for a Bash call is precisely when the two co-occur. Worst available pairing.
- **Splitting the three `#313244` message backgrounds**
  (`userMessageBackground`, `bashMessageBackgroundColor`,
  `memoryBackgroundColor`). Bash blocks already carry a Peach border and memory
  blocks carry the Pink `remember` accent, so background hue is redundant
  signal. Splitting them would require off-palette surfaces, trading palette
  coherence for a distinction the borders already provide.

### 4. Documentation

- `CLAUDE.md` gains a short "Response readability" subsection under the Claude
  Code settings area, recording the output style, the caveman default, and why
  `keep-coding-instructions: true` is mandatory.
- The "Stow gotchas" list gains one line for the new `caveman` package.
- No change to `claude/.claude/CLAUDE.md` response-style bullets beyond a
  pointer: response shape now lives in the output style.

## Verification

### Caveman resolves to `off`

New test at `claude/.claude/tests/caveman-default-off/run.sh`, following the
`commit-scope` / `permission-policy` convention. It asserts our artifact and
its preconditions rather than plugin internals, because the plugin lives in a
hash-named cache directory that moves on every update.

Assertions, one per silent-breakage path:

1. `caveman/.config/caveman/config.json` parses as JSON and
   `defaultMode === "off"`.
2. No `.caveman/config.json` or `.caveman.json` exists anywhere in the repo.
   Repo-local config outranks user config, so a stray file would silently
   override the default.
3. `CAVEMAN_DEFAULT_MODE` is not exported anywhere in the `zsh/` package. The
   environment variable outranks everything.

### Output style loads with coding instructions intact

- Assert the frontmatter carries `keep-coding-instructions: true`. This is the
  field that fails silently and expensively.
- Assert `settings.base.json` sets `outputStyle` to a value that is
  **byte-identical to the style file's `name` frontmatter**. Resolution is
  case-sensitive and failure is silent, so a mismatch here disables the entire
  change with no visible symptom. This assertion is the single highest-value
  test in this design.

An end-to-end check backs the static assertion, reusing the probe technique:

```sh
claude -p "what is 2+2" --settings '{"outputStyle":"Readable"}'
```

Confirm the response obeys the style rather than falling back to Default.

### Theme contrast

New test at `claude/.claude/tests/theme-contrast/run.sh`, built from the audit
script used during this design. It asserts:

- Every foreground token clears 4.5:1 against `background`, with `inverseText`
  explicitly allowlisted as intentionally background-coloured.
- The separated pairs stay separated: `claude != permission`,
  `claude != merged`.

This converts a one-off analysis into a regression guard against future theme
edits.

### Stow

Dry run before apply:

```sh
stow -n -v -t ~ caveman
stow -n -v -t ~ -R claude
```

Then apply, then confirm `~/.config/caveman/config.json` and
`~/.claude/output-styles/readable.md` resolve into the repo.

### Regression

`settings.base.json` changes, so re-run the existing suites:
`mcp-permission-overlay`, `permission-policy`, `commit-scope`, `session-lib`,
`read-once`, `notify-pane`. Then run `claude-sync` to regenerate
`~/.claude/settings.json` and confirm `outputStyle` survives the merge.

### Manual end-to-end

Start a fresh session and confirm:

1. No caveman banner in the SessionStart output.
2. `/output-style` reports Readable as active.
3. A normal response returns paragraphs and headings, not fragments.

## Rejected alternatives

**CLAUDE.md only.** Expand the existing `Response style` section with
structure rules. No new files or mechanisms, cheapest to build. Rejected
because it fights the documented grain — Claude Code routes style away from
CLAUDE.md — and because `claude/.claude/CLAUDE.md` is already roughly 300 lines
of workflow rules that style guidance would compete with for attention on every
turn.

**Built-in output style only.** Turn caveman off, select a built-in style,
nudge the theme. Zero maintenance. Rejected because the built-ins are
general-purpose and the one aimed at brevity pushes toward *shorter*, which is
not the reported complaint. Shorter dense text is still dense.

**Disabling the caveman plugin.** Simplest way to stop the compression.
Rejected because `claude/.claude/CLAUDE.md` depends on `caveman:cavecrew` for
compressed delegation, and disabling the plugin removes those agents along with
the prose mode.
