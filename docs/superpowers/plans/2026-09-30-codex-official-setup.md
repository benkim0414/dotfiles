# Replace user-level Codex customization

Approved in conversation on 2026-09-30. This document records the approved plan; it does not introduce a new design gate.

## Goal and decisions

Use verified OpenAI skills and documented native features. Keep short personal defaults in global AGENTS.md. Remove Superpowers, Compound Engineering, agentmemory, context-mode, custom ELI5, and shared third-party skills from Codex activation without deleting shared assets. Keep verified installed OpenAI plugins and bundled skills. Keep workspace-write and on-request, switch approvals_reviewer to user. Preserve personal consent safeguards; remove mandatory worktrees, commit formatting, and staging methods. Project standards remain repository guidance.

## Sources

- https://learn.chatgpt.com/guides/best-practices
- https://developers.openai.com/codex/agent-configuration/agents-md.md
- https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide.md
- https://learn.chatgpt.com/docs/prompting.md#prompting-codex
- https://developers.openai.com/codex/skills.md
- https://developers.openai.com/codex/hooks.md
- https://developers.openai.com/codex/plugins.md
- https://developers.openai.com/codex/config-reference.md
- https://learn.chatgpt.com/docs/agent-approvals-security.md
- https://learn.chatgpt.com/docs/sandboxing/auto-review.md
- https://developers.openai.com/codex/rules.md

## Global constraints

Work in this linked worktree. Do not edit the primary checkout or live user files, install software, access credentials, delete shared skills/plugin caches, merge, push, or activate live configuration. Prepare a concrete activation procedure and rollback; live activation needs separate authorization under the approved plan because ~/.codex points into the primary checkout. Preserve unrelated live configuration and user work. Never claim AGENTS.md enforces sandbox policy. Do not assume that author strings alone authenticate arbitrary third-party packages. Verify installed official package origins using available install metadata and first-party catalog evidence. Do not change models or unrelated integrations.

## Task 1: Instructions, configuration, and sourced research

Replace codex/.codex/AGENTS.md with short personal defaults. Keep relevant verification and review, focused changes, repository standards, preservation of unrelated edits, and explicit consent for sensitive operations. Retain safeguards for merges, destructive operations, force pushes/history rewrites, credentials, repository administration/settings/secrets, non-GitHub network, arbitrary-runtime GitHub API access, out-of-root writes, and broad permission prefixes. Remove plugin/worktree/commit/staging mandates.

Update config.base.toml: human boundary review, disable third-party plugins and context-mode registration/hooks, disable shared skills and custom ELI5 through documented skill entries, retain verified installed official plugins/bundled skills. Audit installed discovery behavior and effective settings using Codex 0.159.1 without model calls or credentials. Retire tracked custom hooks and hook-specific tests. Add docs/research/2026-09-30-codex-official-setup.md with citations for each recommendation, observed current state, explicit provenance evidence and uncertainty, user decisions, and migration validation. Use actual fetched official pages; do not label personal policies as official requirements or copy model-specific harness prompts into AGENTS.md.

## Task 2: Safe sync, integration tests, and activation procedure

Update bin/.local/bin/codex-sync to stop requiring or wiring retired hooks and to preserve unrelated existing live configuration. Update its tests to meaningfully cover generation, legacy managed hook retirement, repeated sync, unmanaged-file protection, linked-worktree behavior, unrelated live settings/verified official plugins, and retained permission/skill-disable decisions. Avoid deleting unmanaged hook files. Do not reinstate third-party plugin/hook state when preserving live config. Use deterministic merging with explicit ownership of replaced settings and no secret output. Native instructions file must remain short. Add an activation/rollback guide for the prepared branch without modifying main or live settings.

## Acceptance

Run shell syntax checks, sync integration tests, TOML parsing, installed Codex strict-config validation, and a fresh-session/app-server discovery check for AGENTS, skills, plugins, hooks and reviewer settings where locally feasible. Prove actual third-party skill exclusion including legacy ELI5; do not rely only on TOML inspection. Review each task and the whole branch, including Codex /review equivalent if local review entry point is available. Record unavailable interactive checks precisely. Commit logical changes separately with explicit staging and conventional subjects per currently active user instructions. Produce final changes, test results, and concrete pending activation action.
