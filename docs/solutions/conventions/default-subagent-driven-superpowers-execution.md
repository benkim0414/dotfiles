---
title: "Default Superpowers plan execution to subagent-driven development"
date: "2026-05-24"
category: "conventions"
module: "dotfiles/codex"
problem_type: "convention"
component: "development_workflow"
severity: "medium"
applies_when:
  - "A Superpowers implementation plan is ready to execute in Codex"
  - "A plugin skill offers a choice between subagent-driven development and inline execution"
  - "A user preference should survive plugin cache updates"
related_components:
  - "assistant"
  - "documentation"
  - "tooling"
tags:
  - "codex"
  - "superpowers"
  - "subagent-driven-development"
  - "agents-md"
  - "workflow-defaults"
---

# Default Superpowers plan execution to subagent-driven development

## Context

The user wanted Codex to use `superpowers:subagent-driven-development` whenever
it is working from a Superpowers implementation plan. The immediate friction was
that the Superpowers workflow can ask the user to choose between subagent-driven
development and inline execution through `superpowers:executing-plans`.

The first obvious fix was to patch the cached plugin skill files under
`~/.codex/plugins/cache/`. That would solve the current prompt text, but it is
not durable: plugin updates can replace cached skill files, and local edits to
third-party plugin cache content are easy to forget or lose.

The durable fix was to record the preference in Codex-owned instructions. The
tracked copy lives in `codex/.codex/AGENTS.md`, and the same rule was applied to
the live `/home/benkim0414/.codex/AGENTS.md` after explicit approval because
that file is outside the workspace. Session history search found no relevant
prior sessions for this specific default-execution preference.

## Guidance

Prefer a user instruction override over patching third-party plugin skills when
the desired behavior is a standing personal workflow preference.

For this repo, record the default in `codex/.codex/AGENTS.md`:

```markdown
## Default Implementation Workflow

- When a Superpowers implementation plan is ready to execute, always use `superpowers:subagent-driven-development`.
- Do not offer `superpowers:executing-plans`, inline execution, or a choice between subagents and the main agent unless the user explicitly asks for an alternative or subagents are unavailable.
- If a loaded plugin skill suggests asking the user to choose an execution mode, treat this standing instruction as the user's preselection of subagent-driven development.
```

Apply the same block to the live user instruction file when it is not symlinked
from the dotfiles package. In this case, `/home/benkim0414/.codex/AGENTS.md`
was a regular file containing only the Compound tool map, so the live rule had
to be added separately.

Keep the exception narrow. The rule should bypass routine execution-mode
prompts, but it should not prevent the user from explicitly choosing another
mode, and it should not force subagent-driven execution when subagents are
unavailable.

## Why This Matters

Cached plugin files are implementation details of the plugin installer. Editing
them creates a hidden fork that can be overwritten during upgrades and is hard
to explain to future sessions. A user-level `AGENTS.md` rule is visible,
version-controlled, and higher priority than plugin instructions.

This also keeps the intent clear. The user is not changing the public
Superpowers skill for everyone; they are selecting a local Codex workflow
default. When `writing-plans` or another loaded skill presents the execution
choice, the standing instruction answers that choice up front.

The tracked and live instruction layers both matter:

- `codex/.codex/AGENTS.md` preserves the preference in dotfiles history.
- `/home/benkim0414/.codex/AGENTS.md` makes the preference effective for new
  Codex sessions immediately.

## When to Apply

- A Superpowers implementation plan is complete and ready to execute.
- A plugin skill asks whether to use subagents or inline/main-agent execution.
- A user preference should be enforced without modifying cached plugin content.
- A live Codex instruction file is not managed by a symlink from the dotfiles
  package and needs the same durable rule applied explicitly.

Do not use this pattern for one-off task choices that the user has not made
standing policy, or for safety-sensitive approval behavior that belongs in
`config.base.toml` and the auto-review policy instead.

## Examples

Before, the plugin prompt could ask for an execution choice:

```text
1. Subagent-Driven
2. Inline Execution
```

After, Codex treats that question as pre-answered:

```text
Use superpowers:subagent-driven-development unless the user explicitly asks for
an alternative or subagents are unavailable.
```

The same approach applies to other plugin-default preferences: prefer a concise
standing instruction in the user-owned `AGENTS.md` layer when the behavior is a
personal workflow default rather than a bug in the plugin itself.

## Related

- `docs/solutions/workflow-issues/subagent-driven-mechanical-edit-fidelity-2026-05-19.md` -- older guidance that recommended orchestrator-direct edits for small mechanical plan tasks; refresh this if the default-subagent preference should supersede that exception.
- `docs/solutions/workflow-issues/inherit-scoped-codex-approvals-in-subagents-2026-05-19.md` -- durable Codex config and instruction inheritance for subagents.
- `docs/solutions/workflow-issues/codex-standing-worktree-approvals.md` -- another example of recording standing workflow preferences in `codex/.codex/AGENTS.md`.
- `docs/solutions/conventions/superpowers-spec-plan-commit-scopes-2026-05-19.md` -- existing convention for durable user-level Codex guidance.
