# Zsh Eval Cache Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent zsh from sourcing corrupted `fzf` and `zoxide` eval-cache files, while warning with Fedora install commands when shell integrations cannot be generated.

**Architecture:** Move the eval-cache helper into a small sourceable zsh helper file so it can be tested without loading the whole interactive `.zshrc`. The helper generates cache content into a temp file, rejects command-not-found prose and invalid zsh, atomically installs valid cache content, and only sources cache files that pass validation. `.zshrc` sources the helper and passes explicit install hints for `fzf` and `zoxide`.

**Tech Stack:** zsh startup files, POSIX shell test harness, Fedora `dnf` install guidance, git-tracked dotfiles.

## Global Constraints

- Never source cached content that is not valid zsh.
- Warn when required shell integrations cannot be generated.
- Tell the user which Fedora packages to install.
- Preserve the startup performance benefit of cached init output.
- Do not replace Antidote, Starship, or Mise setup.
- Do not remove eval caching for `fzf` and `zoxide`.
- Do not make optional tool failures silent.
- Do not add distro-wide package management automation to shell startup.

---

## File Structure

- Create `zsh/.config/zsh/eval-cache.zsh`: owns `_eval_cache`, `_eval_cache_warn`, and `_eval_cache_valid_zsh_file`.
- Modify `zsh/.zshrc`: source the helper and update `fzf`/`zoxide` call sites to pass install hints.
- Create `tests/zsh-eval-cache/run.sh`: isolated regression tests using fake commands and temporary `HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME`.
- Optional local cleanup after implementation: remove bad local files in `~/.cache/zsh/`.

### Task 1: Add Tested Eval-Cache Helper

**Files:**
- Create: `zsh/.config/zsh/eval-cache.zsh`
- Create: `tests/zsh-eval-cache/run.sh`

**Interfaces:**
- Produces: `_eval_cache name install_hint command [args...] -> sources valid cache or returns 0 after warning`
- Produces: `_eval_cache_valid_zsh_file path -> 0 when path is non-empty valid zsh and does not contain PackageKit prose`
- Produces: `_eval_cache_warn name install_hint -> writes "zsh: <name> init unavailable; install with: <install_hint>" to stderr`
- Consumes: `XDG_CACHE_HOME`, `HOME`, `path`, `command`, `zsh -n`

- [ ] **Step 1: Write the failing test**

Create `tests/zsh-eval-cache/run.sh`:

```bash
#!/usr/bin/env bash
set -u

DOTFILES=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$DOTFILES/zsh/.config/zsh/eval-cache.zsh"

PASS=0
FAIL=0
TMP=""

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

cleanup() {
  if [[ -n "$TMP" && -d "$TMP" ]]; then
    rm -rf "$TMP"
  fi
}

setup_case() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/bin" "$TMP/home/.config/zsh" "$TMP/cache"
  cp "$HELPER" "$TMP/home/.config/zsh/eval-cache.zsh"
}

write_fake() {
  local name="$1"
  local body="$2"
  printf '%s\n' '#!/usr/bin/env bash' "$body" >"$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

run_zsh() {
  local script="$1"
  HOME="$TMP/home" \
  XDG_CONFIG_HOME="$TMP/home/.config" \
  XDG_CACHE_HOME="$TMP/cache" \
  PATH="$TMP/bin:/usr/bin:/bin" \
    zsh -f -c "$script"
}

t_valid_output_is_cached_and_sourced() {
  setup_case
  write_fake fakefzf 'printf "%s\n" "export FZF_TEST_LOADED=1"'

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakefzf "sudo dnf install fzf" fakefzf; print -- "$FZF_TEST_LOADED"' 2>&1)
  if [[ "$output" == "1" && -s "$TMP/cache/zsh/eval-cache-fakefzf.zsh" ]]; then
    ok "valid generated output is cached and sourced"
  else
    bad "valid generated output is cached and sourced ($output)"
  fi
}

t_packagekit_output_is_rejected() {
  setup_case
  write_fake fakefzf 'cat <<'"'"'OUT'"'"'
The following packages have to be installed:
 fzf_0.73.1-1.fc44.x86_64  A command-line fuzzy finder written in Go
OUT'

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakefzf "sudo dnf install fzf" fakefzf; print -- "${FZF_TEST_LOADED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: fakefzf init unavailable; install with: sudo dnf install fzf"* ]] \
    && [[ "$output" == *"unset"* ]] \
    && [[ ! -s "$TMP/cache/zsh/eval-cache-fakefzf.zsh" ]]; then
    ok "PackageKit command-not-found output is rejected"
  else
    bad "PackageKit command-not-found output is rejected ($output)"
  fi
}

t_missing_command_warns_and_sources_valid_stale_cache() {
  setup_case
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'export STALE_CACHE_SOURCED=1' >"$TMP/cache/zsh/eval-cache-missingtool.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache missingtool "sudo dnf install missingtool" missingtool; print -- "${STALE_CACHE_SOURCED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: missingtool init unavailable; install with: sudo dnf install missingtool"* ]] \
    && [[ "$output" == *"1"* ]]; then
    ok "missing command warns and sources valid stale cache"
  else
    bad "missing command warns and sources valid stale cache ($output)"
  fi
}

t_invalid_existing_cache_is_not_sourced() {
  setup_case
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'The following packages have to be installed:' >"$TMP/cache/zsh/eval-cache-fakezoxide.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache fakezoxide "sudo dnf install zoxide" fakezoxide; print -- "${ZOXIDE_TEST_LOADED:-unset}"' 2>&1)
  if [[ "$output" == *"zsh: fakezoxide init unavailable; install with: sudo dnf install zoxide"* ]] \
    && [[ "$output" == *"unset"* ]]; then
    ok "invalid existing cache is not sourced"
  else
    bad "invalid existing cache is not sourced ($output)"
  fi
}

t_command_failure_keeps_valid_existing_cache() {
  setup_case
  write_fake flakytool 'exit 42'
  mkdir -p "$TMP/cache/zsh"
  printf '%s\n' 'export FLAKY_CACHE_SOURCED=1' >"$TMP/cache/zsh/eval-cache-flakytool.zsh"

  local output
  output=$(run_zsh 'source "$XDG_CONFIG_HOME/zsh/eval-cache.zsh"; _eval_cache flakytool "sudo dnf install flakytool" flakytool; print -- "${FLAKY_CACHE_SOURCED:-unset}"' 2>&1)
  if [[ "$output" == *"1"* ]] && [[ "$output" != *"zsh: flakytool init unavailable"* ]]; then
    ok "command failure keeps valid existing cache"
  else
    bad "command failure keeps valid existing cache ($output)"
  fi
}

main() {
  trap cleanup EXIT
  t_valid_output_is_cached_and_sourced
  cleanup
  t_packagekit_output_is_rejected
  cleanup
  t_missing_command_warns_and_sources_valid_stale_cache
  cleanup
  t_invalid_existing_cache_is_not_sourced
  cleanup
  t_command_failure_keeps_valid_existing_cache
  cleanup

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/zsh-eval-cache/run.sh
```

Expected: FAIL before implementation because `zsh/.config/zsh/eval-cache.zsh` does not exist yet, or because `_eval_cache` is not implemented in the helper file.

- [ ] **Step 3: Write minimal implementation**

Create `zsh/.config/zsh/eval-cache.zsh`:

```zsh
_eval_cache_warn() {
  local name="$1"
  local install_hint="$2"
  print -u2 -- "zsh: ${name} init unavailable; install with: ${install_hint}"
}

_eval_cache_valid_zsh_file() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  if command grep -q \
    -e '^The following packages have to be installed:' \
    -e '^ \* Waiting in queue' \
    -e '^ \* Waiting for authentication' \
    -e '^ \* Downloading packages' \
    -e '^ \* Installing packages' \
    "$file" 2>/dev/null; then
    return 1
  fi
  zsh -n "$file" >/dev/null 2>&1
}

_eval_cache() {
  local name="$1"
  local install_hint="$2"
  shift 2

  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/eval-cache-${name}.zsh"
  local cache_dir="${cache:h}"
  local bin_path
  local temp
  local needs_refresh=0
  local refresh_failed=0

  bin_path="$(command -v "$1" 2>/dev/null)"
  if [[ -z "$bin_path" ]]; then
    if _eval_cache_valid_zsh_file "$cache"; then
      source "$cache"
    fi
    _eval_cache_warn "$name" "$install_hint"
    return 0
  fi

  if [[ ! -s "$cache" || "$bin_path" -nt "$cache" ]]; then
    needs_refresh=1
  elif ! _eval_cache_valid_zsh_file "$cache"; then
    needs_refresh=1
  fi

  if (( needs_refresh )); then
    mkdir -p "$cache_dir"
    temp="${cache}.${$}.tmp"
    if "$@" >| "$temp" && _eval_cache_valid_zsh_file "$temp"; then
      command mv -f "$temp" "$cache"
    else
      refresh_failed=1
      command rm -f "$temp"
    fi
  fi

  if _eval_cache_valid_zsh_file "$cache"; then
    if (( refresh_failed )); then
      _eval_cache_warn "$name" "$install_hint"
    fi
    source "$cache"
  else
    command rm -f "$cache"
    _eval_cache_warn "$name" "$install_hint"
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
bash tests/zsh-eval-cache/run.sh
```

Expected:

```text
5 passed, 0 failed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add zsh/.config/zsh/eval-cache.zsh tests/zsh-eval-cache/run.sh
git diff --cached --check
git commit -m "fix(zsh): add validated eval cache helper"
```

Expected: commit succeeds with only the helper and test files staged.

### Task 2: Wire Helper Into Zsh Startup

**Files:**
- Modify: `zsh/.zshrc`
- Test: `tests/zsh-eval-cache/run.sh`

**Interfaces:**
- Consumes: `_eval_cache name install_hint command [args...]` from `zsh/.config/zsh/eval-cache.zsh`
- Produces: `.zshrc` startup behavior that calls `_eval_cache fzf "sudo dnf install fzf" fzf --zsh`
- Produces: `.zshrc` startup behavior that calls `_eval_cache zoxide "sudo dnf install zoxide" zoxide init zsh --cmd cd`

- [ ] **Step 1: Write the failing startup wiring check**

Append this test function to `tests/zsh-eval-cache/run.sh` before `main()`:

```bash
t_zshrc_wires_helper_and_install_hints() {
  local zshrc="$DOTFILES/zsh/.zshrc"
  if grep -q 'source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/eval-cache.zsh"' "$zshrc" \
    && grep -q '_eval_cache fzf "sudo dnf install fzf" fzf --zsh' "$zshrc" \
    && grep -q '_eval_cache zoxide "sudo dnf install zoxide" zoxide init zsh --cmd cd' "$zshrc"; then
    ok "zshrc wires eval-cache helper and install hints"
  else
    bad "zshrc wires eval-cache helper and install hints"
  fi
}
```

Call it from `main()` after `t_command_failure_keeps_valid_existing_cache`:

```bash
  t_zshrc_wires_helper_and_install_hints
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/zsh-eval-cache/run.sh
```

Expected: previous helper tests pass, and `zshrc wires eval-cache helper and install hints` fails because `.zshrc` still defines `_eval_cache` inline and calls it without install hints.

- [ ] **Step 3: Update `.zshrc` wiring**

Replace the inline `_eval_cache` function and the two existing call sites in `zsh/.zshrc`:

```zsh
source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/eval-cache.zsh"

_eval_cache fzf "sudo dnf install fzf" fzf --zsh
_eval_cache zoxide "sudo dnf install zoxide" zoxide init zsh --cmd cd
```

Do not change the surrounding Antidote, Starship, Mise, alias, or kubectl setup.

- [ ] **Step 4: Run syntax and regression tests**

Run:

```bash
zsh -n zsh/.zshrc
bash tests/zsh-eval-cache/run.sh
```

Expected:

```text
zsh -n zsh/.zshrc
# exits 0

bash tests/zsh-eval-cache/run.sh
# 6 passed, 0 failed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add zsh/.zshrc tests/zsh-eval-cache/run.sh
git diff --cached --check
git commit -m "fix(zsh): validate eval cache before sourcing"
```

Expected: commit succeeds with `.zshrc` and the updated test staged.

### Task 3: Verify Against Real Local Cache State

**Files:**
- Modify: none required
- Optional local cleanup: `~/.cache/zsh/eval-cache-fzf.zsh`, `~/.cache/zsh/eval-cache-zoxide.zsh`

**Interfaces:**
- Consumes: installed local `fzf` and `zoxide` commands if present
- Produces: final verification that bad existing cache files no longer produce startup command-not-found errors

- [ ] **Step 1: Run final repo verification**

Run:

```bash
zsh -n zsh/.config/zsh/eval-cache.zsh
zsh -n zsh/.zshrc
bash tests/zsh-eval-cache/run.sh
```

Expected:

```text
zsh -n zsh/.config/zsh/eval-cache.zsh
# exits 0
zsh -n zsh/.zshrc
# exits 0
bash tests/zsh-eval-cache/run.sh
# 6 passed, 0 failed
```

- [ ] **Step 2: Exercise the helper against the current local bad cache files**

Run:

```bash
ZDOTDIR="$PWD/zsh" zsh -f -c 'source zsh/.config/zsh/eval-cache.zsh; _eval_cache fzf "sudo dnf install fzf" fzf --zsh; _eval_cache zoxide "sudo dnf install zoxide" zoxide init zsh --cmd cd'
```

Expected: no `zsh: The: command not found`, no `zsh: Desktop: command not found`, and either no output or concise install warnings.

- [ ] **Step 3: Clean the local corrupted cache files if they remain invalid**

Run:

```bash
if zsh -n ~/.cache/zsh/eval-cache-fzf.zsh >/dev/null 2>&1; then
  printf 'fzf cache syntax is valid\n'
else
  rm -f ~/.cache/zsh/eval-cache-fzf.zsh
fi

if zsh -n ~/.cache/zsh/eval-cache-zoxide.zsh >/dev/null 2>&1; then
  printf 'zoxide cache syntax is valid\n'
else
  rm -f ~/.cache/zsh/eval-cache-zoxide.zsh
fi
```

Expected: invalid local cache files are removed. This is local machine cleanup, not a repo change.

- [ ] **Step 4: Inspect final branch state**

Run:

```bash
git status --short --branch
git log --oneline -3
```

Expected: worktree is clean, with the docs commit plus the two implementation commits on `worktree-zsh-eval-cache-validation`.
