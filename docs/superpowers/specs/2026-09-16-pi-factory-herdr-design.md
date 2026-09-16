# Personal Pi with Factory and visible Herdr workers

Date: 2026-09-16
Status: interaction design approved; written spec awaiting review.

## Goal and agreed experience

Configure a global personal Pi installation as the conversational entry point
to `benkim0414/factory`, running inside Herdr. Factory coordinates workers that
may use Claude Code, Pi, Hermes, OpenClaw, or other runtimes. Workers are visible
in their own Herdr terminals, and the user can send instructions directly to
them. They continue autonomously after those instructions; no hand-back step
is required.

The user approved this interaction model in conversation. This document records
the design and research; it does not claim the integration already exists.

```text
User <-> personal Pi coordinator in Herdr
                     |
              Factory commands/state
                     |
              Herdr worker delivery
                /        |        \
           Claude       Pi      other runtime
             pane      pane        pane
                \        |        /
                 results and evidence
                     |
              Factory review gate
```

Direct user input reaches each worker through its terminal. Factory remains
responsible for ticket identity, attempts, accepted scope, and approval evidence.
Pi interprets requests and calls Factory; it need not duplicate Factory's state
in an independent task manager.

## Evidence and current state

- Dotfiles already declares `pi = "latest"` in
  `mise/.config/mise/config.toml`. Keep mise as the installation owner instead of
  adding a second global npm installation. Resolve the installed executable and
  version before choosing a reproducible pin during implementation.
- Factory's README documents `workflow start --runtime manual`, prepared attempt
  worktrees, Markdown/JSON worker prompts, pane registration and attachment,
  manual result ingestion, and digest-bound human approval. Pane registration
  is descriptive metadata and does not control terminals. Factory separately
  documents an opt-in real Pi process runner. These are distinct execution
  paths, not proof of automatic visible-worker support.
- Factory currently documents `approved_local_patch` as its V1 terminal outcome.
  This design does not extend that to automatic PR publication or merging.
- Firstmate implements a similar visible-crew experience. It is a distribution
  of coordinator instructions, scripts, skills, and state, with Pi among its
  supported primary harnesses. It is an architectural reference, not a required
  additional coordinator.

Sources: [Factory README](https://github.com/benkim0414/factory#readme),
[Firstmate README](https://github.com/kunchenguid/firstmate#readme).
Factory was read through authenticated `gh repo view`; its source code and live
runtime were not inspected in this research. Implementation planning must inspect
the relevant source before specifying an integration contract in detail.

## Recommended architecture

### Personal Pi configuration

Manage intentional global configuration through a dotfiles package targeting
`~/.pi/agent`. Keep provider/model defaults, curated skills, prompts, and pinned
package declarations under version control. Credentials, sessions, caches,
downloaded packages, and machine-specific state remain outside tracked files.
Check the dotfiles deployment convention before choosing exact tracked files.

Do not select a provider or model without checking the user's available
credentials and preferences. That choice is independent of the Factory/Herdr
interaction design and need not block the integration contract.

Keep the generic personal Pi setup useful outside Factory. Load Factory-specific
coordinator instructions and tools explicitly for the coordinator session, so
an ordinary worker Pi does not accidentally inherit the coordinator role.
Reuse portable skills selectively; avoid loading every existing Codex or Claude
plugin as though its tools and semantics were available in Pi.

Pi supports global settings and project overrides. Preserve project trust
prompts and review executable project resources before loading them. Package
extensions execute code with the Pi process's privileges. A temporary `pi -e`
trial still executes the package and is not a security boundary.

Sources: [settings](https://pi.dev/docs/latest/settings),
[security](https://pi.dev/docs/latest/security),
[packages](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md).

### Pi-to-Factory boundary

Start with Factory's documented CLI exposed through a narrowly scoped Pi skill.
Add a small Pi extension only where needed for structured tools or asynchronous
notifications. Factory owns durable records; prompts and Pi conversation history
are not the authoritative task database.

The coordinator needs operations to create/start a task, inspect current state,
obtain a worker prompt, receive results and blockers, and present the current
review packet. Confirm actual commands and cancellation semantics in source.
Do not invent a Factory HTTP or MCP service.

Pi RPC is not necessary for this human-facing coordinator: the user is running
Pi interactively. RPC may be useful for a future worker adapter, but a headless
RPC process does not by itself provide a worker TUI in a Herdr pane.

### Factory-to-Herdr boundary

Add or reuse a terminal backend that launches a selected runtime inside its
prepared attempt worktree and binds the attempt to exact session/workspace/tab/
pane identifiers. Human-readable labels help navigation but must not be the
authority for routing or cleanup.

Each worker gets a separate terminal endpoint. Exact workspace/tab layout is a
presentation choice; side-by-side split panes are not required. New workers
should appear without stealing focus from the coordinator or a worker the user
is currently inspecting.

Factory's existing manual workflow is the initial compatibility path for any
runtime that can read the prompt and return the required result artifact.
Automatic launch, steering, progress, cancellation, and recovery must be verified
per runtime. Implement and verify Claude Code and Pi first; Hermes and OpenClaw
remain compatibility targets until their control interfaces have been checked.

### Direct interaction and concurrent delivery

Workers continue autonomously after direct user input. There is no exclusive
human-control mode or hand-back action.

The delivery layer must preserve unsent user input. If it cannot establish safe
delivery, retain the coordinator message as pending and report that state.
Do not clear the composer or blindly retry whole prompts. Track message identity
and distinguish queued, delivered, and unknown outcomes to avoid duplicates.
Use native runtime steering when available; verify terminal delivery otherwise.

A worker reports material changes, blockers, and final evidence to Factory.
Direct instructions that change acceptance criteria or scope require updating
the Factory ticket and refreshing any affected approval snapshot. Clarification
within the existing scope does not require the user to hand control back.
This reporting is a required integration behavior, not an existing guarantee
that Factory observes every keystroke. Conflicting coordinator and user
instructions should be surfaced for reconciliation rather than silently lost.

### State, completion, and recovery

Use the Factory attempt as the durable identity for the worktree, worker
endpoint, result artifacts, and any resumable harness session. A terminal status
such as idle or done is an observation, not proof that acceptance criteria passed.
Continue to use validated result artifacts and the current review packet.

After restart, reconcile persisted attempt/endpoint identities with real process
liveness before reconnecting or launching a replacement. Avoid duplicate workers.
Expose an explicit unavailable/unknown condition when liveness cannot be proven.
Cancellation targets the identified attempt and endpoint and records its outcome;
retaining worktree changes for review is separate from stopping execution.

## Firstmate comparison and lessons

Firstmate provides working visible workers and supervision today; Factory offers
the user's existing evidence and approval workflow but needs terminal automation.
Adopting Firstmate would also adopt another coordinator lifecycle. The recommended
approach is to retain Factory and borrow the verified terminal-backend patterns.

Current Firstmate documentation describes a task tab/pane per worker and, on
Herdr 0.8.0+, default separate presentation workspaces per task. That presentation
can be disabled. Its scripts support inspecting and steering workers without
switching the user's view. It documents native idle-state limitations, stale
agent registrations, and restart behavior: restored terminal layout does not
mean worker processes survived. Its harness support includes Claude Code and Pi;
Hermes/OpenClaw support was not found in the consulted configuration document.

Sources: [Herdr backend](https://github.com/kunchenguid/firstmate/blob/main/docs/herdr-backend.md),
[harness configuration](https://github.com/kunchenguid/firstmate/blob/main/docs/configuration.md).

## Package research and selection policy

The official Pi extension catalog displayed these monthly download counts during
research on 2026-09-16. These are approximate catalog observations, not unique
users, a security review, or a complete ranking across every Pi package type.

| Package | Catalog downloads/month | Relevance to this setup |
| --- | ---: | --- |
| `pi-mcp-adapter` | 939.7K | Optional only if a required service uses MCP. Factory's known interface is CLI. |
| `pi-web-access` | 435.2K | Candidate for coordinator research after source/configuration review. |
| `@juicesharp/rpiv-ask-user-question` | 162.4K | Optional structured questions; not essential to dispatch. |
| `@juicesharp/rpiv-todo` | 147.6K | Optional conversation checklist; must not become a second Factory task database. |
| `pi-lens` | 88.9K | More relevant to coding workers than the coordinator. |
| `pi-background-tasks` | 86.3K | Defer; child-process management overlaps Factory's responsibilities. |
| `@tintinweb/pi-subagents` | 46.9K | Defer; Factory already owns worker dispatch. |
| `@gotgenes/pi-permission-system` | 41.2K | Evaluate separately; an extension is not OS isolation. |

Source: [official Pi extension catalog](https://pi.dev/packages?type=extension).
Recheck versions, maintenance, license, dependencies, and compatibility before
installation. Pin selected packages to exact npm versions or immutable Git refs.
Begin with Pi core and a curated Factory skill; no third-party package above is
required merely to launch the coordinator. The official
[pi-skills repository](https://github.com/badlogic/pi-skills) is another source
of selectively reusable skills, not an instruction to enable its entire bundle.

Earlier discussion cited Factory.ai/Droid compatibility. Those claims concern a
different product and are not evidence about `benkim0414/factory`.

## Boundaries and rollout

This dotfiles change will configure the personal Pi foundation and document the
coordinator entry point. Factory lifecycle and Herdr backend changes belong in
the Factory repository as separate implementation work. Do not imply that
installing Pi packages alone supplies that integration.

Suggested sequence after spec approval:

1. Inspect installed Pi/Herdr versions, dotfiles deployment, and Factory source;
   resolve provider/model preferences and record exact compatibility assumptions.
2. Configure global Pi and the explicitly loaded Factory coordinator skill.
3. Prove one manual visible worker round trip through Factory's existing gates.
4. Implement Herdr launch/delivery and completion reporting for Claude Code/Pi.
5. Verify autonomous direct steering, concurrent messages, restart, and cancellation.
6. Add other runtimes individually; add optional packages only for demonstrated needs.

This sequence is design guidance, not the detailed implementation plan. No
runtime installs, credentials changes, worker launches, Factory code changes,
automatic merges, or PR publication are authorized by this documentation step.
Worktrees isolate changes but do not sandbox processes. Before unattended worker
execution, choose and validate the intended filesystem/network boundary rather
than assuming Herdr or Pi supplies it.

## Validation criteria

- A new shell resolves one intended mise-managed Pi installation; configuration
  deploys without tracking credentials or runtime state.
- A coordinator Pi can create a Factory task, retrieve a prompt, and present the
  current review packet; an ordinary Pi session does not acquire coordinator duties.
- Each launched worker uses the correct attempt worktree and recorded endpoint;
  spawning preserves the user's current terminal focus.
- Direct user steering reaches both initial runtimes and work continues without
  a hand-back step. Material scope changes reach Factory before approval.
- Concurrent coordinator delivery preserves typed input, reports uncertainty, and
  avoids duplicate submissions. Permission dialogs are not treated as free input.
- A worker reporting idle cannot trigger approval without valid result evidence.
- Cancellation, worker exit, and Herdr restart do not create duplicate workers or
  remove unrelated panes or worktrees. Missing capabilities are reported explicitly.
- Existing Factory stale-result and digest-bound approval checks remain effective.

For this documentation step, validate the diff, scan for placeholders and
contradictions, and verify the distinction between existing capabilities and
proposed integration. Runtime tests belong to the subsequent implementation.
