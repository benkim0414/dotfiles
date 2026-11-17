# kr

Shows assistant replies in Korean beside the English, on demand. Only the
drawing changes: stored messages, the transcript and the model's context stay
English.

## Status: in progress, not loaded

Steps 1–4 of the [plan](intent/show-replies-in-korean/plan.md) are built:
the `/kr` toggle, the translation core and the reply layout. Not built yet:

- Korean in `AskUserQuestion` dialogs (step 5).
- The Korean plan in the `ExitPlanMode` row (step 6).
- Loading (step 7): `CLAUDE_CODE_PLUGIN_DIRS` in
  `claude/.claude/settings.json` does not list `~/.claude/mods/kr` yet, so no
  session runs the mod.

## Use

- `/kr` toggles the mode. `/kr on` and `/kr off` set it. It starts off in
  every session.
- Turning it on translates the latest reply and every later reply, until it
  is turned off. Turning it off keeps cached translations, so turning it on
  again is instant.
- Terminal only. At 105 columns or wider, English and Korean sit side by
  side. Narrower, Korean is stacked under the English.
- While a translation runs, the Korean side shows `번역 중…`. A failure shows
  `번역 실패 (<reason>)` and is not retried.
- Code blocks and inline code stay English, byte for byte.

## Setup

Nothing to install. Translations use `$.model.complete` with `haiku` on the
session's own login; no API key is needed.

## Tests

`claude plugin test claude/.claude/mods/kr`

## Design

Intent, spec and plan: [`intent/show-replies-in-korean/`](intent/show-replies-in-korean/).
