#!/usr/bin/env bash
# Test harness for warp-install.
# Run: bash bin/tests/warp-install/run.sh
set -u

DOTFILES=$(cd "$(dirname "$0")/../../.." && pwd)
INSTALL="$DOTFILES/bin/.local/bin/warp-install"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

write_os_release() {
  printf 'ID=%s\n' "$1" > "$OS_RELEASE"
}

link_real_utility() {
  local utility=$1 utility_path
  utility_path=$(command -v "$utility") || return 1
  ln -s "$utility_path" "$FAKE/$utility"
}

setup_fakes() {
  FAKE="$TMP/fake"
  LOG="$TMP/sudo.log"
  OS_RELEASE="$TMP/os-release"
  REPO_PATH="$TMP/repos/warpdotdev.repo"
  rm -rf "$FAKE"
  mkdir -p "$FAKE"
  : > "$LOG"

  cat > "$FAKE/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$WARP_TEST_UNAME"
EOF
  cat > "$FAKE/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo' >> "$WARP_TEST_LOG"
printf ' %s' "$@" >> "$WARP_TEST_LOG"
printf '\n' >> "$WARP_TEST_LOG"
"$@"
EOF
  cat > "$FAKE/rpm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$FAKE/dnf" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$FAKE/install" <<'EOF'
#!/usr/bin/env bash
source_file=${@: -2:1}
destination=${@: -1}
mkdir -p "$(dirname "$destination")"
cp "$source_file" "$destination"
EOF
  chmod +x "$FAKE"/*
  local utility
  for utility in bash cat cp dirname mkdir mktemp readlink rm; do
    link_real_utility "$utility" || return 1
  done
}

run_installer() {
  run_installer_at "$INSTALL" "$@"
}

run_installer_at() {
  local installer=$1
  shift
  local test_path=${WARP_TEST_PATH:-"$FAKE"}
  WARP_TEST_UNAME=${1:-Linux} \
    WARP_TEST_LOG="$LOG" \
    WARP_INSTALL_OS_RELEASE="$OS_RELEASE" \
    WARP_INSTALL_REPO_PATH="$REPO_PATH" \
    PATH="$test_path" \
    "$installer" > "$TMP/stdout" 2> "$TMP/stderr"
}

t1_missing_fedora_binary_fails() {
  setup_fakes
  write_os_release fedora
  rm "$FAKE/rpm"
  if WARP_TEST_PATH="$FAKE" run_installer Linux; then
    bad "t1 Fedora missing binary fails"
  elif grep -qF 'required command not found: rpm' "$TMP/stderr"; then
    ok "t1 Fedora missing binary names rpm"
  else
    bad "t1 Fedora missing binary error"
  fi
}

t2_fedora_installs_from_official_repository() {
  setup_fakes
  write_os_release fedora
  if ! run_installer Linux; then
    bad "t2 Fedora installer succeeds"
    return
  fi

  local first second third count
  first=$(sed -n '1p' "$LOG")
  second=$(sed -n '2p' "$LOG")
  third=$(sed -n '3p' "$LOG")
  count=$(wc -l < "$LOG" | tr -d ' ')
  case "$second" in
    "sudo install -D -o root -g root -m 644 "*" $REPO_PATH") second_is_expected=1 ;;
    *) second_is_expected=0 ;;
  esac
  if [ "$first" = 'sudo rpm --import https://releases.warp.dev/linux/keys/warp.asc' ] \
    && [ "$second_is_expected" = 1 ] \
    && [ "$third" = 'sudo dnf install warp-terminal' ] \
    && [ "$count" = 3 ]; then
    ok "t2 Fedora invokes native package commands in order"
  else
    bad "t2 Fedora command order"
  fi

  if grep -qxF 'baseurl=https://releases.warp.dev/linux/rpm/stable' "$REPO_PATH" \
    && grep -qxF 'enabled=1' "$REPO_PATH" \
    && grep -qxF 'gpgcheck=1' "$REPO_PATH" \
    && grep -qxF 'gpgkey=https://releases.warp.dev/linux/keys/warp.asc' "$REPO_PATH"; then
    ok "t2 Fedora repository file uses the stable official source"
  else
    bad "t2 Fedora repository file contents"
  fi
}

t3_existing_warp_skips_sudo() {
  setup_fakes
  write_os_release fedora
  cat > "$FAKE/warp-terminal" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE/warp-terminal"
  if run_installer Linux && [ ! -s "$LOG" ]; then
    ok "t3 existing Warp skips sudo"
  else
    bad "t3 existing Warp skips sudo"
  fi
}

t4_darwin_prints_portable_brew_guidance() {
  setup_fakes
  write_os_release fedora
  mkdir -p "$TMP/another-directory"
  if (cd "$TMP/another-directory" && run_installer Darwin) \
    && grep -qxF "Install Warp from this dotfiles repository with: brew bundle --file $DOTFILES/Brewfile" "$TMP/stdout" \
    && [ ! -s "$LOG" ]; then
    ok "t4 Darwin prints portable brew bundle guidance without sudo"
  else
    bad "t4 Darwin guidance"
  fi
}

t5_darwin_stow_symlink_prints_repository_brewfile() {
  setup_fakes
  write_os_release fedora
  local stow_bin="$TMP/home/.local/bin"
  mkdir -p "$stow_bin" "$TMP/another-directory"
  ln -s "$INSTALL" "$stow_bin/warp-install"
  if (cd "$TMP/another-directory" && run_installer_at "$stow_bin/warp-install" Darwin) \
    && grep -qxF "Install Warp from this dotfiles repository with: brew bundle --file $DOTFILES/Brewfile" "$TMP/stdout" \
    && [ ! -s "$LOG" ]; then
    ok "t5 Darwin Stow symlink prints repository Brewfile guidance"
  else
    bad "t5 Darwin Stow symlink guidance"
  fi
}

t6_unsupported_linux_skips_sudo() {
  setup_fakes
  write_os_release ubuntu
  if run_installer Linux; then
    bad "t6 unsupported Linux fails"
  elif grep -qF 'unsupported Linux distribution: ubuntu' "$TMP/stderr" \
    && [ ! -s "$LOG" ]; then
    ok "t6 unsupported Linux fails before sudo"
  else
    bad "t6 unsupported Linux error"
  fi
}

main() {
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  t1_missing_fedora_binary_fails
  t2_fedora_installs_from_official_repository
  t3_existing_warp_skips_sudo
  t4_darwin_prints_portable_brew_guidance
  t5_darwin_stow_symlink_prints_repository_brewfile
  t6_unsupported_linux_skips_sudo
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
main "$@"
