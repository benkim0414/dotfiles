# Zsh Eval Cache Validation Design

## Context

After a Fedora reinstall, login shells print errors such as:

```text
zsh: The: command not found...
zsh: fzf_0.73.1-1.fc44.x86_64: command not found...
zsh: zoxide_0.9.8-2.fc44.x86_64: command not found...
zsh: Desktop: command not found...
```

The repo's `zsh/.zshrc` initializes `fzf` and `zoxide` through `_eval_cache`, which stores generated shell code in `~/.cache/zsh/eval-cache-<name>.zsh` and sources it on startup. On the formatted Fedora machine, the cache files for `fzf` and `zoxide` contain PackageKit command-not-found install prompts before the real init code. When zsh sources those cache files, it treats prose and package names as commands.

## Goal

Make the zsh init cache safe after fresh installs and package changes:

- Never source cached content that is not valid zsh.
- Warn when required shell integrations cannot be generated.
- Tell the user which Fedora packages to install.
- Preserve the startup performance benefit of cached init output.

## Non-Goals

- Do not replace Antidote, Starship, or Mise setup.
- Do not remove eval caching for `fzf` and `zoxide`.
- Do not make optional tool failures silent.
- Do not add distro-wide package management automation to shell startup.

## Design

Update `zsh/.zshrc` so `_eval_cache` generates cache files atomically and validates them before sourcing.

The helper will:

1. Resolve the command path with `command -v`.
2. If the command is missing, print a concise warning and skip sourcing that integration.
3. Generate new output into a temporary file when the cache is missing, empty, or older than the resolved command.
4. Reject generated output if the command exits non-zero.
5. Reject generated output if it contains known PackageKit command-not-found text, including lines such as `The following packages have to be installed:`.
6. Run `zsh -n` on the temporary file and reject it if syntax validation fails.
7. Move the temporary file over the cache only after validation succeeds.
8. Source the cache only after confirming the final cache passes `zsh -n`.

If generation or validation fails, `_eval_cache` will remove the invalid temporary file, ignore any invalid existing cache, and print a warning. Warnings should name the integration and include install guidance.

The call sites will pass install hints:

```zsh
_eval_cache fzf "sudo dnf install fzf" fzf --zsh
_eval_cache zoxide "sudo dnf install zoxide" zoxide init zsh --cmd cd
```

The warning format will be short enough for shell startup:

```text
zsh: fzf init unavailable; install with: sudo dnf install fzf
zsh: zoxide init unavailable; install with: sudo dnf install zoxide
```

When a tool exists but emits invalid output, the message should still point at the install command because Fedora's PackageKit command-not-found output is the known failure mode after reinstall.

## Error Handling

Missing command:

- Do not generate a cache.
- Source an old cache only if it still passes validation.
- Print the install hint.

Command exits non-zero:

- Leave the previous valid cache in place only if it passes `zsh -n`.
- Otherwise skip sourcing and print the install hint.

Generated output is PackageKit prose or invalid zsh:

- Do not replace the cache with it.
- If the existing cache is also invalid, remove or ignore it.
- Print the install hint.

Temporary file cleanup:

- Use a process-specific temp file inside the cache directory.
- Remove it after failure.

## Testing

Add focused coverage if there is an obvious shell-test location for zsh startup helpers. Otherwise verify manually with temporary fake commands:

- A fake `fzf` that prints valid zsh output should produce and source a cache.
- A fake `fzf` that prints PackageKit-style install text should not be sourced and should print the install warning.
- A missing `zoxide` command should print the install warning and source a valid old cache if present.
- A pre-existing invalid cache should not be sourced.
- `zsh -n zsh/.zshrc` should pass after the change.

After implementation, delete the local bad cache files or let the corrected helper reject them on the next shell startup:

```sh
rm ~/.cache/zsh/eval-cache-fzf.zsh ~/.cache/zsh/eval-cache-zoxide.zsh
```
