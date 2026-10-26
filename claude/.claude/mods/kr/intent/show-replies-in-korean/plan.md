# Plan: kr mod
From: [spec.md](spec.md). Status: draft.

## Files that change

Paths are relative to the `claude/` package, except the last one, which is
at the repo root.

- `.claude/mods/kr/.claude-plugin/plugin.json`: `name` `kr`, `version`
  `0.1.0`, a one-line `description`, `types` `./types/index.d.ts`
- `.claude/mods/kr/hooks/hooks.json`: `{ "modules": ["./register.tsx"] }`
- `.claude/mods/kr/hooks/layout.ts`: pure, no `$`. `layoutFor(columns |
  undefined)` returns `{ mode: 'side', colWidth } | { mode: 'stacked' }`
  (R3, "Width rule")
- `.claude/mods/kr/hooks/translate.ts`: `protect(source)` →
  `{ text, spans }`; `restore(reply, spans)` → `{ ok, text } | { ok: false,
  reason }`; `codeEqual(source, reply)` for the unprotected fallback;
  `numbered(fields)` and `split(reply, count)` for AskUserQuestion;
  `fnv1a32`; and the one `$`-taking function `translate($, source,
  timeoutMs)`, declared at top level ("Translation call")
- `.claude/mods/kr/hooks/register.tsx`: `session.start`, `/kr`,
  `turn.step`, the `Write`/`Edit`/`AskUserQuestion`/`ExitPlanMode`
  `tool.call` hooks, and the `AssistantMessage`, `AskUserQuestion` and
  `ToolUse` render hooks
- `.claude/mods/kr/hooks/layout.test.ts`, `hooks/translate.test.ts`,
  `hooks/register.test.tsx`: `claude plugin test` suites
- `.claude/mods/kr/types/index.d.ts`: the `PluginState` contract, with `Ko`
  declared inside it and no `import` lines (`claude plugin validate`
  refuses them, as mermaid-ascii found)
- `.claude/mods/kr/tsconfig.json`:
  `{ "extends": "./.claude-plugin/types/tsconfig.json" }`. It only works
  once the engine has loaded the mod; until then, use "Type check before the
  mod loads"
- `.claude/settings.json`: `env.CLAUDE_CODE_PLUGIN_DIRS` gains
  `:~/.claude/mods/kr`
- `CLAUDE.md` (repo root): a `kr` entry under "Mods": what it shows, `/kr`
  to toggle it, Haiku on the subscription, nothing to install

`.gitignore` already covers `claude/.claude/mods/*/.claude-plugin/types/`.
There is no `render/` folder and no `node_modules`, so
`.stow-local-ignore` does not change.

## Order of work

Each step is one commit, test first where there is a test to write. The
work happens in the worktree `.claude/worktrees/kr`; Stow and live checks
wait for the merge. Git runs as `/usr/bin/git` inside the worktree, as in
context-bar.

1. **Spike: the assumptions the spec rests on.** A throwaway mod at
   `.spike/kr/` in the worktree root, outside the `claude` package and never
   staged, run with `claude plugin test`, then deleted. It checks:
   - **(a) Identity** (spec concern 2): a message row the kit draws carries
     an `e.requestId` equal to that message's `uuid` in
     `$.session.messages()`.
   - **(b) `turn.step`:** an async-generator hook that sets a state flag,
     `yield* next(e)`, and clears it in `finally` forwards every chunk and
     leaves the flag false after the stream ends, an aborted stream
     included. The kit can raise a `turn.step` stream.
   - **(c) Model stub:** a test's own `on('model.complete', …)` hook can
     stand in for the model: answer a text, an `api-error`, and hold a
     reply on a promise the test releases.
   - **(d) Question rewrite:** a `ui.render` rewrite of
     `AskUserQuestion`'s `props.questions` that only appends to `question`
     and `description` validates, and the answer the kit returns is still
     the original `label`.
   - **(e) Plans directory:** whether the mod can read the
     `plansDirectory` setting at all; if not, the default stands, as the
     spec allows.

   Outcomes:
   - **All pass:** keep the spec's design.
   - **(a) fails:** stop. Eligibility needs another mapping, so the spec
     changes first, in its own commit, before step 2.
   - **(b) fails:** gate on `turn.complete` instead (translation waits for
     the turn's end), and update R10 and the Hooks section.
   - **(c) fails:** find the kit's own stub for `$.model.complete`
     (`mock.*` in `claude-code/testing`) and record it here.
   - **(d) fails:** Korean moves into `question` only; update R5.

   Record the result in this file under step 1. No repo commit unless the
   spec changes.
2. **Scaffold and the width rule.** `plugin.json`, `hooks.json`,
   `types/index.d.ts`, `tsconfig.json`, a stub `register.tsx` that only
   returns `next(e)`, and `layout.ts`. Write `layout.test.ts` first: 80,
   100 and 104 stack; 105 gives `colWidth` 50; 120 gives 57; 155 and 200
   give 75 (the cap); no viewport stacks. Mutation-check the threshold
   (`>` for `≥`) and the cap.
3. **Translation core.** `translate.ts`, test first in
   `translate.test.ts`:
   - `protect`/`restore` round-trip byte for byte: backtick and tilde
     fences, a longer fence around a nested fence (only the outer one is a
     span), inline spans, CRLF;
   - a reply that drops, duplicates or alters a placeholder fails
     `code-changed`;
   - a source already holding `⟦K` is sent unprotected, and `codeEqual`
     fails a reply that changes a code span;
   - a reply with a control character other than tab or newline fails
     `control-char`;
   - `split` on a wrong count fails `count-mismatch`;
   - `translate` with a stubbed `model.complete`: the request names
     `haiku`, the system block carries `cache: true`, `maxTokens` follows
     the formula and caps at 8192, and each `isAnswered: false` reason comes
     back as the failure reason.

   Mutation-check: the exactly-once placeholder count, the control-char
   check, and the fallback `codeEqual`.
4. **Toggle and replies.** In `register.tsx`: `session.start`, `/kr`,
   `turn.step`, and the `AssistantMessage` render hook. Test first in
   `register.test.tsx`, covering the spec's Verification items for them:
   - `/kr`, `/kr on`, `/kr off`, `/kr foo`: state and answer text;
   - identity (spike a, kept as a regression test);
   - the identical "Done." case: only the latest reply is bilingual;
   - a message created after `/kr on` is eligible;
   - `inFlight` gating: no call while the step streams, exactly one after;
   - one call per distinct text across redraws and repeated text;
   - a cached failure is not retried; `code-changed` draws its marker;
   - off then on reuses the cache with no new call;
   - an injected hash collision draws English alone;
   - drawing assertions loop over `['terminal', 'desktop'] as const`:
     desktop passes through.

   Mutation-check, one at a time: the terminal check, the `notEligible`
   check, the `inFlight` gate, the `source` equality check, the claim map
   (one call per text), and clearing `notEligible` on off.
5. **Questions.** The `AskUserQuestion` `tool.call` pre-translation and
   render rewrite, test first: Korean under each `question` and as
   `<라벨> — <설명>` under each `description`; `label`, `header` and
   `multiSelect` byte-identical; a count mismatch leaves it English with the
   marker; with the mode off, no model call; with it on, the
   pre-translation runs once whatever surface draws the dialog (R9, work).
   Mutation-check the mode check and the "labels untouched" rule (rewriting
   `label` must fail a test).
6. **Plan text.** The `Write`/`Edit` `tool.call` hooks that record
   `planPath`, the `ExitPlanMode` `tool.call` translation, and the
   `ToolUse` render hook, test first: after a `Write` into a temp plans
   directory, the row draws that file's Korean only; with no plan-file write
   in the session, the row is the engine's own even with a newer file
   present; a `Write` outside the plans directory or not ending `.md` is
   ignored. Mutation-check the fail-closed rule (falling back to the newest
   file must fail a test) and the `realPath` prefix check.

   Finally run `claude plugin validate` and the pre-load type check ("Type
   check before the mod loads"), and paste both outputs here with the types
   file's version line.
7. **Loading.** `env.CLAUDE_CODE_PLUGIN_DIRS` gains `:~/.claude/mods/kr`.
   A separate commit, because it changes every session on every machine.
8. **Docs.** The `CLAUDE.md` entry from "Files that change".

If implementation departs from this plan, update this file in the same
commit.

## Type check before the mod loads

The spec's section of the same name defines it. Run it at the end of every
step from 2 on, from the worktree root, in a session where the
plugin-authoring skill has loaded:

```sh
TYPES=<skill folder>/types/claude-code.d.ts   # the path the skill printed when it loaded
MOD="$PWD/claude/.claude/mods/kr"
OUT=<session scratchpad>/kr-tsc
head -1 "$TYPES"; claude --version            # versions must match, else reload the skill
mkdir -p "$OUT"
cat > "$OUT/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "es2023", "lib": ["es2023"], "types": [],
    "module": "esnext", "moduleResolution": "bundler",
    "strict": true, "noUncheckedIndexedAccess": true,
    "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment"
  },
  "files": ["$TYPES"],
  "include": ["$MOD/hooks/**/*", "$MOD/types/**/*"]
}
EOF
npx -y -p typescript@5.9.3 tsc -p "$OUT/tsconfig.json"
```

It passes when `tsc` exits 0 with no output. The config lives in the
session scratchpad, never in the mod folder or the repo, and nothing is
emitted.

## After the merge (main checkout, not the worktree)

1. `stow -t ~ -R claude`.
2. Start a new session with `claude --debug` the first time, to see the mod
   load and any skipped-hook lines. Once loaded, run `tsc -p` on the mod
   folder against the engine-written types.
3. Run `/kr on` in a 120-column terminal: the latest reply shows two
   columns, `번역 중…` first, then Korean. Narrow below 105: it stacks.
4. Ask for something that calls AskUserQuestion: Korean under questions and
   descriptions; picking an option returns its English label.
5. Enter plan mode and exit it: the Korean plan appears in the
   `ExitPlanMode` row while the approval dialog is open.
6. `/kr off`: replies draw English only. `/kr on` again: the latest reply's
   Korean returns at once.
7. Answer the spec's concerns and record them here: ctrl+o (1), a tall plan
   (3), pre-empted `tool.call` hooks (4), the reply indent (5).
8. Check WCAG 1.4.8's 80/40 figures on w3.org and correct the spec's "Width
   rule" if they differ.

## Risks

- **Spike (a) fails.** Eligibility by message id is the spec's core. If the
  ids do not match, the spec changes before any other step.
- **Plan usage.** Every translation is a Haiku call on Ben's subscription.
  The per-text cache and the latest-reply-only start keep it bounded; the
  live check notes how many calls a typical session makes.
- **Pre-empted hooks.** Another installed plugin already sends
  `prompt.attachment` past this mod. The live check confirms the mod's
  `tool.call` hooks run (spec concern 4).
- **`settings.json` is written at runtime.** Before step 7,
  `git diff claude/.claude/settings.json` must show nothing else. If it
  does, stop and ask Ben; never stash, discard or commit those changes
  unasked. Confirm with `git diff --cached` that the commit holds only the
  `CLAUDE_CODE_PLUGIN_DIRS` line.
- **Assertions that cannot fail.** Every model stub records whether it was
  called. "Passes through" and "no call" assertions are paired with a step
  where the same setup did draw or call, so a hook that never ran cannot
  pass as one that declined
  (`docs/solutions/conventions/assertions-that-pass-when-they-cannot-check-2026-09-18.md`).

## Proof

- The spike's result (step 1) is written in this file.
- `claude plugin validate`, `tsc` and `claude plugin test` on the mod folder
  all pass, with the output pasted.
- Each mutation check lists the guard and the test that caught it.
- The live check (After the merge) records steps 3–8 and the answers to the
  spec's concerns.
