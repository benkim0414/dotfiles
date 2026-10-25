# Intent: kr mod
Author: Ben Kim. Status: draft.

## Problem

Claude Code replies in English. Sometimes I want to read a reply in Korean,
but not always, and the work itself (files, commits, the model's context)
must stay in English. Asking the model to answer in Korean would put Korean
into the transcript and the model's context, and switching it on and off by
hand in each prompt is tedious.

## Proposed outcome

A Claude Code mod that, while switched on, shows a Korean translation next
to each English reply in the terminal transcript.

- `/kr` turns the mode on or off (`/kr on` and `/kr off` set it). The choice
  lasts for this session only and starts off in each new session.
- Turning it on translates the latest reply and every later reply until it
  is turned off.
- Translated: assistant reply text, `AskUserQuestion` questions and options,
  and plan text. Not translated: thinking, tool calls, tool output.
- Kept in English inside the Korean: fenced code blocks and inline code;
  file paths, commands and identifiers; technical terms (hook, commit,
  worktree, ...).
- English and Korean are always shown together: side by side when the
  terminal is wide enough, one above the other when it is narrow.
- Exception: plan text is shown in Korean only. The English plan is already
  in the approval dialog, so the Korean stands alone in the transcript.

## Affected users and systems

- **The person reading the transcript:** sees each reply in both languages
  while the mode is on.
- **The model:** unchanged. It still writes English and sees only English.
- **Claude Code:** `ui.render` hooks on `AssistantMessage` and
  `AskUserQuestion` (plan text: see Open questions), terminal surface only.

## Constraints

- **Display only.** The stored message, the transcript file and the model's
  context stay English. The mod rewrites only the drawing.
- **Translator: `$.model.complete` with `haiku`.** It runs on the session's
  own client, so it uses the Claude subscription login with no API key. Each
  translation counts against plan usage.
- **Session-only state.** The on/off flag lives in `$.state` (session
  scope), not `$.store`.
- **Never blocks drawing.** Translation runs outside the render hook and is
  cached per message, so a redraw never translates again.
- **Answers stay English.** A translated `AskUserQuestion` option still
  returns its original English label as the answer.
- **Lives in dotfiles.** It ships in the `claude` Stow package under
  `claude/.claude/mods/kr/` and loads through `CLAUDE_CODE_PLUGIN_DIRS` like
  the other mods.

## Open questions

- Plan text: the plan-approval dialog is not a `ui.render` component. Can the
  plan be reached through the `ExitPlanMode` `ToolUse` entry, or is plan text
  out of scope?
- The terminal width at which side by side falls back to stacked.
- What shows when a translation fails (`api-error`, `aborted`): English
  alone plus a toast, or a marker in place of the Korean?
- A streaming reply: translate once the message is finished, or in chunks as
  it arrives?

## Later changes (each gets its own intent)

- Target languages other than Korean.
- Remembering the toggle across sessions (`$.store`).

## Background

- `$.model.complete` and `ui.render`: the plugin-authoring reference and the
  `claude-code` types (`RenderComponent` lists what can be redrawn).
- The `mermaid-ascii` mod: the same display-only rewrite of
  `AssistantMessage`, with work outside the render hook and a per-block
  cache.
