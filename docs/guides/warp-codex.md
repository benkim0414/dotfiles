# Warp and Codex command workflow

Warp is the terminal in this setup. Codex CLI is the only AI path: use your
ChatGPT subscription through the `codex` command rather than Warp's built-in
AI features.

## Boundaries

Warp's native Generate, Explain, Agent/Oz, and Active AI features cannot use a
ChatGPT/Codex subscription. Bring-your-own-key (BYOK) requires an API key and
separate billing; local arbitrary endpoints are not a substitute.

In Warp, open **Settings > Features > Session**, disable Warp AI and Agent
features, leave BYOK unconfigured, and ensure the session starts **zsh** so
the Codex helper module loads. Ordinary terminal features, including Command
Inspector, remain available.

The command helpers send requests through the signed-in Codex CLI. They first
check that `codex login status` reports `ChatGPT`. If it instead reports
API-key auth, run `codex logout`, then run `codex login` and choose ChatGPT
sign-in.

Keep Codex installed and managed through `mise`; do not install or replace it
through another channel.

## Install Warp

On Fedora, run:

```sh
warp-install
```

This uses Warp's official RPM repository. Warp itself is not installed through
`mise` or an AppImage; `mise` manages Codex CLI only.

On macOS, run this from any location, adjusting the path if the repository
lives elsewhere:

```sh
brew bundle --file ~/workspace/dotfiles/Brewfile
```

## Use Codex from the terminal

Start an interactive Codex session when you want a normal conversation:

```sh
codex
```

The zsh helpers propose or explain commands without executing their output:

```sh
cmdgen "find the ten largest files below the current directory"
cmdexplain "find . -type f -print0 | xargs -0 du -h | sort -h | tail"
some-command 2>&1 | cmderr "why did this fail?"
```

`cmdgen` proposes one concise command with a safety note. `cmdexplain`
describes a command's effects, risks, assumptions, and safer alternatives when
relevant. `cmderr` accepts piped, non-empty terminal diagnostics and can focus
on an optional question.

## Safety and privacy

Helpers never execute the command text they return; inspect every suggestion
before running it. Their read-only sandbox limits Codex tools, but it does not
make a generated command safe. In particular, a command could still be
destructive, require elevated privileges, or make platform-specific
assumptions when you choose to run it yourself.

Each helper invokes Codex with the required contract:
`codex exec --ephemeral --sandbox read-only --skip-git-repo-check`.

Command text and diagnostic logs are sent to OpenAI under the signed-in
account. Before using `cmderr`, redact credentials, API keys, tokens, private
paths, and customer data from logs.

## Verify the setup

Confirm the installer, ChatGPT login state, and helper discovery:

```sh
command -v warp-install
codex login status
whence -w cmdgen cmdexplain cmderr
```

`codex login status` must report ChatGPT, and `whence` should identify all
three names as functions. Run the automated test suites after changing the
installer or helpers:

```sh
bin/tests/warp-install/run.sh
zsh/tests/codex-command-helpers/run.sh
```
