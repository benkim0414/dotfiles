# Warp Codex Command Helpers Design

## Goal

Install Warp on Fedora and macOS and use Codex inside Warp for command generation, command explanation, and terminal-error analysis. Codex must authenticate with the user's ChatGPT subscription rather than an OpenAI API key. Warp's native AI features must remain disabled so the workflow does not consume Warp credits.

## Current Context

This dotfiles repository already manages zsh, mise, Homebrew packages, and Codex CLI. Codex is declared through mise as `npm:@openai/codex = "latest"`, and the current Fedora 44 x86_64 machine reports `Logged in using ChatGPT` from `codex login status`. Warp is not installed.

The repository uses `Brewfile` for macOS applications, `bin/.local/bin/` for user commands, and focused zsh configuration sourced from `.zshrc`. The implementation should follow those patterns rather than introduce another package manager or a monolithic shell configuration block.

## Product Constraint

Warp cannot route its native Agent, Generate, Active AI, voice, or Full Terminal Use features through a ChatGPT/Codex subscription. Warp supports its own credits, provider API keys on eligible plans, and enterprise cloud routing. It does not support ChatGPT subscription authentication or arbitrary local-model endpoints for those native features.

Warp does officially support Codex as a third-party CLI agent. Codex CLI supports signing in with ChatGPT for subscription-backed use. The supported design is therefore to run Codex inside Warp, not to configure Codex as Warp's native model provider.

## Recommended Approach

Use Warp as the terminal and Codex CLI as the only AI path. Preserve interactive `codex` for multi-turn, repository-aware work and add three small zsh helpers for common one-shot operations:

- `cmdgen <request>` proposes shell commands and explains their safety implications.
- `cmdexplain <command>` explains a complete command, its important flags, risks, and portability concerns.
- `cmderr [question]` reads piped output as untrusted diagnostic context and explains the failure or proposes next steps.

All three helpers call the official `codex exec` interface. They use an ephemeral session, an explicit read-only sandbox, and the option that permits use outside a Git repository. They print Codex's response but never evaluate it, inject it into the shell buffer, or execute a proposed command.

## Installation Design

### macOS

Add `cask "warp"` to the existing `Brewfile`. Warp installation and updates then remain owned by the repository's existing Homebrew workflow.

### Fedora

Add an idempotent `warp-install` command under `bin/.local/bin/`. On Fedora it should:

1. Verify the host is Fedora and that `rpm`, `dnf`, and `sudo` are available.
2. Import Warp's official RPM signing key.
3. Install the official Warp repository definition under `/etc/yum.repos.d/`.
4. Install `warp-terminal` with `dnf`.
5. Exit successfully without unnecessary changes when Warp is already installed.

The script should reject unsupported operating systems with a clear message. On macOS it should direct the user to `brew bundle` instead of installing a second copy outside Homebrew.

Warp is not installed through mise. There is no Warp desktop entry in the mise registry, and forcing the AppImage through a custom backend would lose normal desktop integration, dependency handling, and platform-consistent updates.

## Helper Design

Keep helper implementation in a focused zsh module under the existing zsh configuration tree and source it from `.zshrc`.

Each public helper should:

1. Verify that `codex` is available.
2. Validate its arguments or stdin before starting a request.
3. Run `codex login status` and fail with an actionable message unless the active method is ChatGPT authentication.
4. Build a fixed instruction that constrains the requested task and treats user-provided command text or logs as data.
5. Invoke `codex exec` with ephemeral, read-only settings and support use outside Git repositories.
6. Return the Codex process status and print the response unchanged.

`cmdgen` must explicitly tell Codex not to execute commands and to call out destructive behavior, privilege requirements, and platform assumptions. `cmdexplain` must explain rather than execute or modify anything. `cmderr` must require piped stdin, treat that input as untrusted output rather than instructions, and accept an optional user question for focus.

Shared private helpers should centralize dependency and authentication checks so behavior and error messages remain consistent. Inputs must be passed as arguments or stdin with normal shell quoting; the implementation must not use `eval`.

## Warp Configuration

Warp should use zsh as the startup shell. Warp normally loads the login shell automatically, but the implementation checklist should also document the explicit setting under `Settings > Features > Session` for machines whose login shell differs.

Disable Warp-native AI through Warp's supported Settings UI. Warp does not document a stable, portable dotfile key for this global toggle, so the implementation must not edit its internal preferences database. The post-install checklist should direct the user to disable the Warp Agent/AI toggle and avoid configuring BYOK.

Command Inspector remains available as a non-conversational Warp terminal feature. Interactive `codex` remains the fallback whenever a one-shot helper lacks enough context.

## Data and Trust Boundaries

The data flow is:

1. The user invokes a helper in zsh inside Warp or another terminal.
2. The helper verifies subscription-backed ChatGPT authentication.
3. The helper sends its fixed instruction and user-supplied context to `codex exec`.
4. Codex processes the request under its read-only sandbox.
5. The final response is printed for human review.

Generated commands never cross an automatic execution boundary. The user must copy, edit, or type a command before the shell can run it.

Command text and piped logs are sent to OpenAI under the user's Codex/ChatGPT account. `cmderr` cannot reliably detect every secret, so its usage message and documentation must warn users to inspect or redact sensitive logs before piping them.

## Error Handling

- Missing `codex`: explain that Codex is managed through mise and must be installed or activated.
- Wrong authentication method: stop before inference and instruct the user to run `codex logout`, then `codex login` and choose ChatGPT.
- Missing `cmdgen` or `cmdexplain` argument: print concise usage and return nonzero.
- Interactive stdin passed to `cmderr`: print piping examples and return nonzero instead of waiting indefinitely.
- Empty piped input: reject it with a clear message.
- Codex failure or interruption: preserve its nonzero status; do not mask or retry the request automatically.
- Unsupported `warp-install` platform: make no changes and explain the supported Fedora and macOS paths.
- Package-manager failure: preserve the failure and leave diagnosis to the user rather than attempting a different installer or unverified download.

## Testing and Validation

Add shell tests with a fake `codex` executable. Tests should verify:

- all helpers reject a missing Codex executable;
- all helpers reject non-ChatGPT authentication;
- `cmdgen` and `cmdexplain` validate arguments;
- `cmderr` rejects terminal stdin and empty piped input;
- each successful helper passes the expected safety flags and task instruction;
- `cmderr` forwards piped data as context;
- Codex failures propagate to the caller;
- Codex output is printed but never evaluated;
- `.zshrc` sources the helper module once.

Validate `warp-install` with shell syntax checks and test doubles for platform and package-manager commands where practical. Tests must not write to `/etc`, import keys, contact Warp, or invoke `sudo`.

After automated checks pass, perform these manual validations on Fedora:

1. Run `warp-install` through the normal approval path.
2. Confirm `warp-terminal --version` succeeds and the application launches.
3. Confirm Warp starts zsh and the existing prompt and shell integrations load.
4. Confirm `codex login status` reports ChatGPT authentication.
5. Run harmless smoke requests through `cmdgen`, `cmdexplain`, and `cmderr`.
6. Disable Warp-native AI in Settings and confirm no BYOK key is configured.

On macOS, validate the Brewfile entry and document `brew bundle` as the installation path. A real macOS installation is outside the Fedora implementation environment and remains a manual verification step.

## Implementation Boundaries

In scope:

- Warp installation declarations and the Fedora installer.
- The three zsh helpers and their tests.
- A concise post-install and usage document.
- Manual Warp settings needed for zsh and disabling native AI.

Out of scope:

- Routing Warp-native AI through Codex, ChatGPT, or a local model.
- OpenAI API keys, Warp BYOK, Warp credits, Oz, or cloud agents.
- Local LLM installation or configuration.
- Custom ZLE widgets, generated-command insertion, or automatic execution.
- Modifying Warp's undocumented internal preference files.
- Replacing Ghostty or making Warp the operating system's default terminal.
- Installing Warp on macOS from the Fedora development machine.

## Source Notes

- Warp installation: <https://docs.warp.dev/getting-started/quickstart/installation-and-setup>
- Warp agent FAQ and BYOK boundary: <https://docs.warp.dev/agent-platform/getting-started/faqs>
- Warp third-party CLI support: <https://docs.warp.dev/>
- Warp Full Terminal Use and credit behavior: <https://docs.warp.dev/agent-platform/capabilities/full-terminal-use>
- OpenAI Codex authentication: <https://developers.openai.com/codex/auth>
- OpenAI Codex non-interactive mode: <https://developers.openai.com/codex/noninteractive>
- mise registry behavior: <https://mise.jdx.dev/registry>
