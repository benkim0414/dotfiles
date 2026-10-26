# Spec: kr mod
From: [intent.md](intent.md). Status: draft.

## Requirements

- **R1.** `/kr` switches the mode. `/kr` flips it; `/kr on` and `/kr off`
  set it; any other argument changes nothing and answers with the usage
  line. The mode starts off in every new session and is never kept across
  sessions.
- **R2.** Turning the mode on makes the latest reply and every later reply
  eligible, until it is turned off. Eligibility belongs to a message, never
  to its text: an earlier reply whose text matches the latest reply's stays
  English.
  - **Latest reply:** the assistant messages after the last user prompt in
    `$.session.messages()`, read when `/kr on` runs. None (a new session,
    right after `/clear`): nothing is marked, and later replies still are.
  - **Later replies:** every assistant message that did not exist when
    `/kr on` ran.
  - **Off:** clears eligibility. Cached translations are kept, so turning the
    mode on again over the same latest reply is instant.
- **R3.** In the terminal transcript, an eligible `AssistantMessage` block is
  drawn with English and Korean together:
  - **Side by side** when `e.viewport.columns ≥ 105`: English on the left,
    Korean on the right, a 3-cell gutter between. Each column is
    `min(75, floor((columns − 2 − 3) / 2))` cells wide.
  - **Stacked** below 105 columns, or when the surface reports no viewport:
    English, a dim rule, then Korean, each at full width.
  - See "Width rule" for where 105 and 75 come from.
- **R4.** While a block's translation is pending, the Korean side shows a dim
  `번역 중…`. When it fails, it shows a dim `번역 실패 (<reason>)`, where
  `<reason>` is `$.model.complete`'s (`api-error 529`, `empty-reply`,
  `aborted`) or the mod's own (`code-changed`, `count-mismatch`,
  `control-char`). The failure is cached: a redraw never retries it.
- **R5.** While the mode is on, an `AskUserQuestion` dialog shows Korean
  appended under each `question` and under each option's `description`, the
  latter as `<라벨> — <설명>` so the option's wording is translated too.
  `label`, `header` and `multiSelect` stay exactly as the model sent them,
  so the answer returned is the original English label. A failed translation
  leaves the dialog English, with `번역 실패` under the first question.
- **R6.** While the mode is on, the `ExitPlanMode` transcript row shows the
  plan translated into Korean, **Korean only**: the English plan is in the
  approval dialog (an exception recorded in the intent). The plan comes from
  this session's own plan file (see "Plan text"). With no such file, the row
  is drawn as the engine draws it.
- **R7.** Kept in English inside every translation:
  - fenced code blocks and inline code, **byte for byte**, enforced by
    placeholders (see "Translation call");
  - file paths, commands, flags, identifiers and technical terms (hook,
    commit, worktree, …), by the prompt's instruction only. A translation that
    alters one of these outside code is not detected.
  - Markdown structure (headings, lists, tables, links) is kept.
- **R8.** Only the drawing changes. The stored messages, the transcript file
  and the model's context stay English. The mod adds no prompt section and
  writes no message. The one exception is the `/kr` output row (see R12).
- **R9.** **Drawing** is terminal-only: on `desktop`, `vscode` and `mobile`
  every `ui.render` hook returns `next(e)` untouched. **Translation work**
  is not tied to a surface: `tool.call` has none, so the `AskUserQuestion`
  and `ExitPlanMode` pre-translations run whenever the mode is on. The mode
  can only be set by `/kr`, typed into a session that is on.
- **R10.** Drawing never waits on a translation. A render hook only reads
  state; translation runs from `$.clock.after(0, …)` or from a `tool.call`
  hook. A reply's block is translated only once its model request has
  finished (see `inFlight`). Each distinct source text is translated at most
  once per session. Results are cached by text, failures included.
- **R11.** Translations use `$.model.complete` with `model: 'haiku'`, which
  runs on the session's own client (the Claude subscription login). No API
  key is read or required.
- **R12.** `/kr` answers in one short English line (`kr: on`, `kr: off`, or
  the usage line). `command.run` text is also read by the model, so it says
  nothing more.

## Width rule

Sources, gathered 2026-10-26:

- Bringhurst's long-standing range for one column of Latin text is 45–75
  characters per line, ideally 66
  ([Wikipedia: Line length](https://en.wikipedia.org/wiki/Line_length)).
  Ruder recommends 50–60
  ([Baymard](https://baymard.com/blog/line-length-readability)).
- WCAG 1.4.8 (AAA) caps lines at 80 characters, or 40 for CJK scripts,
  as quoted by
  [Oregon State](https://blogs.oregonstate.edu/calverta/line-width-in-digital-typography-for-accessibility-and-comprehension/).
  This is a secondary source; check it against w3.org before the spec is
  approved.
- A Korean web-reading study found reading rate improved at 50 characters
  per line with 100% line spacing
  ([Shin & Park 2003](https://koreascience.or.kr/article/JAKO200310103403108.pub?orgId=kiie)).

In terminal cells, a Hangul syllable is 2 cells and a Latin letter 1. One
column width has to serve both languages:

- **Floor 50 cells.** English gets 50 characters, inside 45–75 and Ruder's
  50–60. Korean gets 25 syllables. Below that, Korean wraps too often to
  read in parallel, so the layout stacks instead.
- **Cap 75 cells.** English stops at Bringhurst's upper bound. Korean gets 37
  syllables, under WCAG's 40-character CJK cap. Past this, extra width is
  left empty rather than stretching lines.
- **Threshold.** Side by side needs `2 (reply indent) + 50 + 3 (gutter) + 50
  = 105` columns. That splits the common widths cleanly: 80 and 100 stack,
  120 and up go side by side.

## Plan-text spike (2026-10-26)

A throwaway mod drew two magenta lines under the `ExitPlanMode` row and a
band above the prompt, and logged every draw. A real plan approval showed:

- **The row is redrawn while the dialog is open.** The call started at
  23:36:11.813 and ended at 23:37:06.886, and the row was redrawn at
  23:36:11.844. Its added lines sit directly above the dialog and stay in
  the transcript after the answer.
- **The band is not drawn** while the call runs: no `AbovePrompt` render was
  logged in that window.
- **`isRunning` was `false` on every render**, mid-call included, so nothing
  here depends on it.
- **`prompt.attachment` never reached the mod.** Its `plan_mode` detail
  carries the session's `planFilePath`, but another installed plugin
  (`cc-plugin-sec-default`) runs first and sends the event on past the mod's
  hook. The plan path therefore comes from the mod's own `tool.call` hooks
  ("Plan text").

## Design

### Files

```
CLAUDE.md                                 # repo root: Mods section gains a kr entry
claude/.claude/
├── settings.json                         # CLAUDE_CODE_PLUGIN_DIRS gains ~/.claude/mods/kr
└── mods/kr/
    ├── .claude-plugin/plugin.json        # name, version 0.1.0, description, types
    ├── hooks/hooks.json                  # { "modules": ["./register.tsx"] }
    ├── hooks/register.tsx                # command, step, tool and render hooks
    ├── hooks/translate.ts                # placeholders, prompt, $.model.complete call
    ├── hooks/layout.ts                   # R3 width rule, pure
    ├── hooks/layout.test.ts              # width rule at 80/104/105/120/200 and no viewport
    ├── hooks/translate.test.ts           # placeholder protect/restore, pure
    ├── hooks/register.test.tsx           # claude plugin test
    ├── types/index.d.ts                  # PluginState contract
    ├── tsconfig.json                     # extends ./.claude-plugin/types/tsconfig.json
    └── intent/show-replies-in-korean/    # intent.md, spec.md, plan.md
```

No `render/` directory and no `node_modules`: everything runs in the hooks
module.

`tsconfig.json` is the one-line config mermaid-ascii and context-bar use:
`{ "extends": "./.claude-plugin/types/tsconfig.json" }`. The engine writes
the file it extends, and the types beside it, into `.claude-plugin/types/`
once it has loaded the mod. Root `.gitignore` already excludes
`claude/.claude/mods/*/.claude-plugin/types/`.

### Type check before the mod loads

Until the engine has loaded the mod (in the worktree, on a fresh clone, in
CI), `.claude-plugin/types/` does not exist and `tsc -p` on the mod folder
cannot run. The check then uses a throwaway config outside the mod folder
and the repo:

- **Types:** the API file the plugin-authoring skill writes when it loads,
  `<skill folder>/types/claude-code.d.ts`. It holds the `claude-code` API,
  the `claude-code/testing` kit and the built-in tools' input types, so it is
  the only types file needed. Its folder is per process and changes after a
  restart, so take the path the skill prints when it loads, never a recorded
  one. Its first line (`// Written by Claude Code 2.1.309.`) must match
  `claude --version`; if it does not, load the skill again.
- **Config:** `<session scratchpad>/kr-tsc/tsconfig.json`, with the options
  the types file's own header gives:

  ```json
  {
    "compilerOptions": {
      "target": "es2023", "lib": ["es2023"], "types": [],
      "module": "esnext", "moduleResolution": "bundler",
      "strict": true, "noUncheckedIndexedAccess": true,
      "noEmit": true, "skipLibCheck": true,
      "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment"
    },
    "files": ["<TYPES>"],
    "include": ["<MOD>/hooks/**/*", "<MOD>/types/**/*"]
  }
  ```

  `<TYPES>` is the types file's absolute path and `<MOD>` the absolute path
  of `claude/.claude/mods/kr` in the checkout being checked. `hooks/**/*`
  takes the test files too. `noEmit` writes nothing; `types: []` keeps any
  installed `@types` out; `lib` names no DOM, as the header requires.
- **Command:** `npx -y -p typescript@5.9.3 tsc -p <session
  scratchpad>/kr-tsc/tsconfig.json`, the TypeScript version context-bar was
  checked with, pinned so a global install cannot change the result. It
  passes when it exits 0 with no output.

Once the mod has loaded, `tsc -p claude/.claude/mods/kr` checks against the
engine-written types instead.

### Flow

```mermaid
sequenceDiagram
    participant U as /kr on
    participant T as turn.step hook
    participant S as $.state
    participant M as $.model.complete (haiku)
    participant R as ui.render hook
    U->>S: isOn = true; notEligible = all assistant ids but the latest reply's
    T->>S: inFlight = true ... stream ends ... inFlight = false
    R->>S: read isOn, notEligible[requestId], inFlight, ko[textId]
    alt off, or requestId in notEligible
        R-->>R: next(e)
    else eligible, ko cached
        R-->>R: draw English + Korean (R3)
    else eligible, no ko, inFlight
        R-->>R: draw English + 번역 중… (no call yet)
    else eligible, no ko, not inFlight
        R->>R: $.clock.after(0, translate) unless already claimed
        R-->>R: draw English + 번역 중…
        R->>M: translate(text)
        M-->>S: ko[textId] = { ok, text } or { ok: false, reason }
        S-->>R: readers redraw
    end
```

### Identity

Two identities, kept apart:

- **Eligibility: the message.** `ui.render`'s envelope carries
  `e.requestId`, "the message id for a message". At `/kr on`, every
  assistant message id in `$.session.messages()` except the latest reply's
  goes into `notEligible`. While on, a block is eligible when its
  `requestId` is not in that set. Messages created later were never put
  there, so they are eligible. Off clears `notEligible`. This relies on
  `requestId` matching the message `uuid` that `$.session.messages()`
  reports; a plugin test pins that (Verification).
- **Translation cache: the text.** `textId = fnv1a32(text)`, as in
  `mermaid-ascii`. The hash only names the state member, and every cached
  value carries the `source` it was made from. A hit requires `source` to
  equal the text drawn, so a hash collision draws English alone and never
  the wrong Korean. Identical text in two eligible messages shares one
  translation.

### Hooks

- **`session.start`:** `$.command.register({ name: 'kr', description:
  'Show replies in Korean beside English (this session)', argumentHint:
  '[on|off]' })`.
- **`command.run` `{ command: 'kr' }`:** parse `e.args.trim()` (R1). On
  turning on, read `$.session.messages()` and fill `notEligible` (R2). On
  turning off, clear it. Return `{ text }` (R12).
- **`turn.step` (async generator), main loop only:** set `inFlight = true`,
  `yield* next(e)`, then set `inFlight = false` in a `finally`. The hook
  forwards every chunk untouched and reads nothing from the result. A step is
  one model request, so once the flag drops, every block of that request is
  final. That is how R10's "finished request" is known, with no text
  matching and no use of `TurnStepResult.answer`, which joins all of a
  response's blocks into one string.
- **`ui.render` `{ component: 'AssistantMessage' }`:** terminal check (R9);
  off, or `requestId` in `notEligible` → `next(e)`. Otherwise read
  `ko[textId]` and `inFlight`. On a miss with no request in flight, schedule
  a translation (R10). Return a tree from `$.ui.resolve(e)`: a `Box` row of
  two width-fixed `Box`es holding `Markdown` (side by side), or a column
  `Box` with a dim rule (stacked). `isSummary` blocks are drawn the same way;
  a hook's own tree drops the terminal's ` · summary` mark, which is
  accepted.
- **`tool.call` `{ tool: 'Write' }` and `{ tool: 'Edit' }`:** after
  `await next(e)` succeeds, if `file_path` resolves (`$.fs.stat(…, {
  resolve: true }).realPath`) under the plans directory and ends `.md`,
  record it as `planPath`. This needs no mode check; it only remembers a
  path.
- **`tool.call` `{ tool: 'AskUserQuestion' }`:** while on, translate every
  `question`, option `label` and option `description` in one call before
  `next(e)`, bounded by `timeoutMs: 10000`. This delays the dialog by up to
  the timeout, but not drawing, so the dialog opens already translated
  instead of redrawing under the person's cursor.
- **`ui.render` `{ component: 'AskUserQuestion' }`:** terminal check (R9);
  rewrite `props.questions` from the cache (R5). Append `\n<ko question>` to
  each `question` and `\n<ko label> — <ko description>` to each option's
  `description`; leave `label`, `header`, `multiSelect` and every other
  field untouched. A rewrite that breaks the tool's schema draws the
  original, by the engine's rule.
- **`tool.call` `{ tool: 'ExitPlanMode' }`:** while on and `planPath` is set,
  read it, translate it (`timeoutMs: 30000`), store the result under
  `plan[tool_use_id]`, then `next(e)`. The row is redrawn as soon as that
  state lands, which the spike shows happens while the dialog is open.
- **`ui.render` `{ component: 'ToolUse', props: { tool: 'ExitPlanMode' } }`:**
  terminal check (R9); with `plan[tool_use_id]` set, return a column `Box`
  holding `await next(e)` (the engine's row) followed by the Korean plan as
  `Markdown`, or R4's markers when pending or failed. No condition on
  `isRunning`.

### Plan text

`ExitPlanMode`'s input carries no plan, and the approval dialog is not a
`ui.render` component. The session-bound `planFilePath` from
`prompt.attachment` does not reach the mod in this setup (see "Plan-text
spike"). So the path is the last `.md` file this session wrote or edited
under the plans directory, as seen by the mod's own `Write` and `Edit`
`tool.call` hooks. Another session's plan is never chosen, because another
session's tool calls never pass through this session's hooks. With no such
write, no plan is translated (R6): the mod never guesses.

The plans directory is `~/.claude/plans/`, resolved with `realPath`. If the
mod can read the `plansDirectory` setting, that value wins. Whether it can
is checked against the types when implementing; until then the default is
used.

### Translation call

`translate.ts` turns a source into a request, calls the model and checks the
reply:

1. **Protect.** Replace each top-level fenced block (fence rules as in
   `mermaid-ascii` R1) and each inline code span with a placeholder
   `⟦K<n>⟧`, numbered from 0 in order. A source that already contains `⟦K`
   is sent unprotected, and the code check below still applies.
2. **Call.** `$.model.complete({ model: 'haiku', system, prompt,
   maxTokens, timeoutMs })`. `system` is one fixed text marked `cache:
   true`:
   - Translate the given Markdown from English to natural Korean.
   - Copy every `⟦K<n>⟧` placeholder exactly, once each, in place.
   - Keep file paths, commands, flags, identifiers and technical terms in
     English.
   - Keep the Markdown structure.
   - Output only the translation.

   `maxTokens` is `4 × ceil(source.length / 3)`, capped at 8192.
3. **Check and restore.** Every placeholder must appear exactly once; else
   the result is a failure, `code-changed`. Placeholders are replaced with
   the exact original spans. An unprotected source fails `code-changed` when
   its fenced blocks and inline spans, in order, are not byte-equal in the
   reply. A reply holding a control character other than tab or newline
   fails `control-char`, as in `mermaid-ascii` R7.

`AskUserQuestion` fields go in one call as a numbered list (questions, then
each option's label and description), protected the same way. The reply is
split on the same numbers; a count mismatch fails `count-mismatch`.

### State contract

```ts
type Ko = { source: string; ok: true; text: string }
        | { source: string; ok: false; reason: string }

interface PluginState {
  kr: {
    isOn: boolean
    inFlight: boolean               // a main-loop model request is streaming
    notEligible: StateFamily<true>  // by message id; filled on, cleared off
    ko: StateFamily<Ko>             // by text id; kept across off/on
    plan: StateFamily<Ko>           // by ExitPlanMode tool_use_id
    planPath: string | null         // this session's last plan-file write
  }
}
```

Session-scoped `$.state` only (intent: session-only toggle). `$.store` is
not used.

### Loading

`claude/.claude/settings.json`: append `:~/.claude/mods/kr` to
`env.CLAUDE_CODE_PLUGIN_DIRS`. After merge, `stow -t ~ -R claude` from the
main checkout. There is no per-machine install step.

## How each constraint in the intent is met

| Constraint | How |
|---|---|
| Display only | Render hooks rewrite drawings; the stored text is never touched (R8). |
| Haiku via the subscription client | `$.model.complete({ model: 'haiku' })`, the session's own client (R11). |
| Session-only state | `$.state`, no `$.store` (state contract). |
| Never blocks drawing | Render hooks read state only; translation runs from timers or `tool.call` hooks (R10). |
| Answers stay English | `label` untouched; its Korean goes into the description (R5). |
| Lives in dotfiles | `claude/.claude/mods/kr`, loaded through `CLAUDE_CODE_PLUGIN_DIRS`. |

## Open questions from the intent

All four are decided here.

- **Plan text:** in scope, Korean only, from this session's own plan-file
  write. Shown in the `ExitPlanMode` row, which the spike shows is drawn
  while the dialog is open (R6, "Plan text", "Plan-text spike").
- **Width threshold:** 105 columns, with columns of 50–75 cells ("Width
  rule").
- **Failure:** dim `번역 실패 (<reason>)` in place, cached (R4).
- **Streaming:** translate once the block's model request has finished,
  known from the `inFlight` flag (R10).

## Verification

- `claude plugin validate` on `claude/.claude/mods/kr`, and the type check:
  the pre-load config ("Type check before the mod loads") until the mod has
  loaded, `tsc -p` on the mod folder after.
- `translate.test.ts` (pure):
  - placeholders round-trip: fenced blocks (backtick and tilde, longer
    fences around a nested fence) and inline spans come back byte for byte;
  - a stubbed reply that drops, duplicates or alters a placeholder fails
    `code-changed`;
  - a source already holding `⟦K` falls back to the byte-equality check.
- `layout.test.ts` (pure): 80, 104, 105, 120 and 200 columns, and no
  viewport (R3).
- `claude plugin test claude/.claude/mods/kr`, with `$.model.complete`
  stubbed by the test's own hook:
  - `/kr`, `/kr on`, `/kr off`, `/kr foo`: state and answer text (R1, R12);
  - off: an `AssistantMessage` passes through untouched;
  - **identity:** the `requestId` a drawn message row carries equals that
    message's `uuid` in `$.session.messages()`;
  - **identical text:** an earlier reply and the latest reply both say
    "Done."; after `/kr on`, only the latest is drawn bilingual (R2);
  - a message created after `/kr on` is eligible;
  - while `inFlight`, an eligible block draws `번역 중…` and makes no model
    call; when the step ends, exactly one call is made (R10);
  - one model call per distinct text, across redraws and repeated text;
  - a stubbed `api-error` draws `번역 실패 (api-error 529)` and is not
    retried on redraw (R4);
  - a stub that changes a code block draws `번역 실패 (code-changed)`;
  - off then on: eligibility is reset and the cached Korean reappears for the
    latest reply with no new call;
  - an injected hash collision draws English alone for the loser;
  - **AskUserQuestion:** Korean appended to each `question` and as
    `<라벨> — <설명>` to each `description`; `label`, `header` and
    `multiSelect` byte-identical; a mismatched count leaves it English with
    the failure marker (R5);
  - **ExitPlanMode:** after a `Write` to a temp plans directory, the row
    draws that file's Korean only; with no plan-file write in the session,
    the row is the engine's own, even with a newer file present (R6);
  - **R9, drawing:** `desktop` passes through on every `ui.render` hook;
  - **R9, work:** with the mode on, the `AskUserQuestion` pre-translation
    runs once whatever surface later draws the dialog; with the mode off, it
    makes no model call.
- Live, after merge and restow:
  - `/kr on` in a 120-column terminal: the latest reply shows two columns.
    Narrow the window below 105 and it stacks.
  - Ask for something that calls AskUserQuestion: Korean appears under
    questions and descriptions, and picking an option returns its English
    label.
  - Enter plan mode and exit it: the Korean plan appears in the
    `ExitPlanMode` row while the approval dialog is open.
  - Open ctrl+o and record what it shows ("Areas of concern" 1).

## Areas of concern

1. **ctrl+o.** `AssistantMessage` has no `isExpanded` prop, so ctrl+o may draw
   the two-column tree too. That is acceptable, because the stored message
   stays English (R8), but it should be recorded at the live check.
2. **`requestId` vs session uuid.** Eligibility assumes the render envelope's
   message id is the uuid `$.session.messages()` reports. If the plugin test
   shows otherwise, eligibility needs another mapping before anything else is
   built.
3. **A tall plan dialog.** The spike's dialog was short. A long plan may push
   the row above the screen while the dialog is open, so the person scrolls
   up or reads it after answering.
4. **Pre-empted hooks.** `cc-plugin-sec-default` already sends
   `prompt.attachment` past this mod. If it, or another plugin, does the same
   to `tool.call` for `Write`, `Edit`, `AskUserQuestion` or `ExitPlanMode`,
   the matching feature does nothing. The spike saw the mod's `ExitPlanMode`
   `tool.call` hook run, so that one is not affected today.
5. **Reply indent.** The width rule assumes a 2-column reply indent, the same
   assumption as `mermaid-ascii`'s "Areas of concern" 4.
