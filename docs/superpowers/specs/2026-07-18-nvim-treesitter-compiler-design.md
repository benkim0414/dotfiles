# Nvim Treesitter Compiler Design

## Goal

Fix Neovim Treesitter parser installation failures like:

```text
[nvim-treesitter/install/json] error: Error during "tree-sitter build"
Error: Failed to compile parser
Caused by:
    Failed to execute the C compiler ...
    Error: No such file or directory (os error 2)
```

The failure should be resolved for both macOS/Homebrew machines and Linux
machines. Fresh dotfile installs should make the compiler dependency explicit,
and Neovim should avoid repeatedly surfacing low-level parser build errors when
the dependency is missing.

## Current Context

The Neovim Treesitter plugin is configured in
`nvim/.config/nvim/lua/plugins/syntax.lua`. On startup it installs the essential
parsers `lua`, `go`, `python`, `json`, and `markdown`, then auto-installs parsers
for newly opened filetypes.

The observed environment has `nvim` available but no `cc`, `gcc`, `clang`, or
`tree-sitter` command on `PATH`. The reported JSON parser error fails while
executing the compiler command, before any C compiler diagnostics can run. That
points to a missing compiler executable rather than a bad JSON parser source.

The repo already uses `Brewfile` as the package manifest for Homebrew-managed
tools. It does not currently have an equivalent distro package manifest for
Linux system packages.

## Recommended Approach

Make the compiler dependency explicit and make Neovim's Treesitter bootstrap
dependency-aware.

1. Add a Homebrew compiler package to `Brewfile`.
2. Document Linux package installation commands for the required C compiler.
3. Add a small compiler preflight in `syntax.lua` before Treesitter parser
   installs run.

The Neovim preflight should accept any available compiler from this set:
`cc`, `gcc`, or `clang`. If none is executable, Neovim should show one concise
warning explaining that Treesitter parser installation requires a C compiler and
skip both the startup parser install and FileType auto-install. Existing parser
runtime behavior should otherwise remain unchanged.

## Alternatives Considered

### Local-only compiler install

Installing `gcc` or `clang` directly on the current machine would fix the
immediate error, but it would not help a fresh dotfiles setup and would leave the
requirement implicit.

### Disable automatic parser installs

Removing startup and FileType parser installs would avoid the startup error, but
it would hide the missing dependency until a manual `:TSInstall` run and would
weaken the current bootstrap behavior.

### Force one compiler

Hard-coding `gcc` or `clang` in Neovim would be more brittle across platforms.
Checking the standard compiler names lets macOS Command Line Tools, Homebrew
GCC, Fedora GCC, and Clang-based systems work without special cases.

## Implementation Boundaries

In scope:

- `Brewfile` package list update for Homebrew-managed machines.
- Linux setup guidance in existing repository documentation.
- `syntax.lua` preflight around `nvim-treesitter.install.install`.
- Focused validation of headless Neovim startup and Treesitter parser install
  behavior.

Out of scope:

- Creating a new Linux package manager automation system.
- Reworking the plugin manager or replacing `nvim-treesitter`.
- Changing the list of essential Treesitter parsers.
- Installing system packages from inside Neovim.

## Error Handling

If a compiler is unavailable, Neovim should notify at warning level and skip
parser installation attempts for that session. The message should name the
missing dependency and point to installing `gcc`, `clang`, or system build
tools.

If a compiler is available but parser compilation fails for another reason, the
existing Treesitter install error should still surface. The preflight must not
swallow real parser or compiler failures.

## Validation

Validation should include:

- Confirm the current failing condition with `command -v cc`, `command -v gcc`,
  and `command -v clang` when reproducing on a machine without compiler tools.
- Run a headless Neovim startup smoke test to ensure missing compilers no longer
  emit repeated Treesitter parser build stack traces.
- After installing compiler tools, run a JSON parser install check, such as a
  headless `TSInstallSync json` invocation, and confirm the parser compiles.
- Inspect `git diff` and stage only the logical files for each commit.

## Risks

The main risk is choosing a Homebrew package that is unnecessary on macOS systems
where Apple's Command Line Tools already provide `cc`. That is acceptable
because the repo uses Homebrew for portable tool setup and the preflight accepts
the system compiler when it exists. Linux remains documentation-only because the
repo has no distro package manifest today; adding one would be a separate design.
