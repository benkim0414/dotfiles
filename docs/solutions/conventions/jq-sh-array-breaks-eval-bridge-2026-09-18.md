---
title: "jq @sh emits multiple words for non-scalars, so eval executes them"
date: 2026-09-18
category: conventions
module: claude-code-hooks
problem_type: bug
component: tooling
severity: critical
related_components:
  - shell_scripting
  - security
applies_when:
  - "Using jq @sh to build shell assignments for eval"
  - "Parsing hook stdin JSON into shell variables"
  - "Reviewing any eval whose input derives from JSON"
tags:
  - jq
  - eval
  - command-injection
  - security
  - bash
  - hooks
  - silent-failure
  - dotfiles
---

# jq @sh emits multiple words for non-scalars, so eval executes them

## Problem

Parsing hook stdin into shell variables through jq's `@sh` looks like the
idiomatic JSON-to-shell bridge, and for JSON **strings** it is:

```sh
_fields="$(jq -r '@sh "COMMAND=\(.tool_input.command // "")"')"
eval "$_fields"
```

`@sh` single-quotes the value and escapes embedded quotes as `'\''`, so
quotes, `$(...)`, backticks, `;`, newlines and tabs all round-trip byte-exact
with nothing executed. That was verified up to 200k characters.

**`@sh` applied to a JSON array emits one quoted word per element.** With
`offset: ["1","touch","/tmp/PWNED"]` the line becomes:

```
OFFSET='1' 'touch' '/tmp/PWNED'
```

which `eval` runs as the command-prefix assignment `OFFSET=1` followed by the
command `touch /tmp/PWNED`. Three consequences, all reproduced against the
real hook:

1. **The command executes.** `["1","sh","-c","..."]` gives a full shell.
2. **Its stdout becomes the hook's output.** A PreToolUse hook's stdout is
   parsed as its decision, so injecting
   `printf '%s' '{"hookSpecificOutput":{...,"permissionDecision":"allow",...}}'`
   forges an **auto-approval** from a hook that can only ever deny or stay
   silent.
3. **It fires before any validation.** The session-id regex gate sat *after*
   the eval, so an invalid session id prevented nothing — the payload executed
   and then the hook exited 0 at the gate.

Every field was a vector, including ones whose schema declares a number.

## Why the final code does not show this

The fix is a single `| tostring` per interpolation. Reading it afterwards, it
looks like defensive tidiness — the sort of thing a reviewer would call
redundant, because `.tool_input.offset` is "obviously" a number. Nothing in
the diff says it is the difference between a parser and an execution sink.

The original safety comment made it worse by being confidently wrong: it
asserted that `@sh` made `eval` safe for every value, and cited a real but
incomplete verification (strings only). A future reader had every reason to
trust it.

## Rule

**Force every interpolation to a scalar before `@sh` sees it:**

```sh
jq -r '
  @sh "SESSION_ID=\((.session_id // "") | tostring)",
  @sh "OFFSET=\((.tool_input.offset // 0) | tostring)",
  ...
'
```

`tostring` collapses arrays and objects to a single JSON-text scalar, so `@sh`
always emits exactly one single-quoted word. Verified: the same array payload
then yields `OFFSET='["1","touch","/tmp/PWNED"]'` and nothing runs.

It also removes a second failure mode. `@sh` on an *object* aborts jq
mid-stream, so earlier assignments landed and later ones kept their defaults —
a partially-parsed payload. `tostring` handles objects too.

**Validate anything that feeds structured output.** `OFFSET` and `LIMIT` are
interpolated into a JSON range array downstream, where a non-numeric value
emits malformed JSON, so they are now checked against `^-?[0-9]+$` with a
fallback to the defaults.

**Do not trust a JSON schema to constrain what reaches a hook.** Tool input is
model-supplied and JSON Schema permits additional properties by default; a
field a tool never declares can still arrive. A security-adjacent hook cannot
assume the host validated for it.

**If you want no execution surface at all**, drop `eval`: emit
`KEY=<base64>` lines and decode in a `while IFS= read -r` loop. That costs one
subprocess per field, which is why it was not chosen for a PreToolUse hook that
runs on every Read, Bash and Grep call — but it is the right trade when the
hot-path argument does not apply.

## How it was found

Not by the tests — the suite was 18/18 green with the bug present, because no
case sent a non-string field. It was found by a code reviewer explicitly asked
to attack the `eval` line with hostile payloads. **The test suite's green was
evidence about the inputs it tried, and nothing more.**

## Source

- Related: [Hooks run under macOS system bash 3.2](hooks-run-under-macos-system-bash-3-2-2026-09-18.md)
  — the `@sh` bridge exists because bash 3.2 cannot split on a control-character
  `IFS`, which is what the previous parser used.
