#!/usr/bin/env bash
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for tool in stow jq; do
  command -v "$tool" >/dev/null || { printf '%s required\n' "$tool" >&2; exit 2; }
done
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
mkdir -p "$TMP/bin" || exit 2
printf '#!/bin/sh\nprintf "%%s\\n" "$TEST_SYSTEM"\n' > "$TMP/bin/uname" || exit 2
chmod +x "$TMP/bin/uname" || exit 2

for system in Darwin Linux; do
  home="$TMP/$system"
  app="$home/.config/herdr-app"
  mkdir -p "$app" || exit 2
  printf 'device state\n' > "$app/shared.json" || exit 2
  if ! TEST_SYSTEM="$system" PATH="$TMP/bin:$PATH" HOME="$home" bash "$PKG/install.sh"; then
    bad "$system install"
    continue
  fi
  case "$system" in
    Darwin) create=cmd-n; copy=cmd-c; select=cmd-1; other=ctrl-shift-n ;;
    Linux) create=ctrl-shift-n; copy=ctrl-shift-c; select=ctrl-1; other=cmd-n ;;
  esac
  if [[ -L "$app/keys.json" ]] && jq -e --arg create "$create" --arg copy "$copy" --arg select "$select" --arg other "$other" '
    .global[$create] == "space.new" and .global[$other] == null and
    .global[$select] == "tab.select:1" and .terminal[$copy] == "terminal.copy" and
    .global["ctrl-s"] == "mod.open:prefix" and .global["ctrl-h"] == null and
    .["layout:vim-nav"]["ctrl-h"] == "vim-nav.left"
  ' "$app/keys.json" >/dev/null; then
    ok "$system native bindings and shared shortcuts"
  else
    bad "$system keymap"
  fi
  if [[ -L "$app/layouts/vim-nav.json" && -L "$app/mods/prefix/main.js" && -L "$app/mods/vim-nav/main.js" && ! -L "$app/mods/prefix" && ! -L "$app/mods/prefix/gpui-kit.d.ts" && ! -L "$app/mods/prefix/jsconfig.json" && ! -e "$home/tests" && ! -e "$home/keymaps" && ! -e "$home/install.sh" ]] &&
    cmp -s "$app/shared.json" <(printf 'device state\n'); then
    ok "$system shared layout and mods leave device state alone"
  else
    bad "$system layout or mod links"
  fi
done

home="$TMP/conflict"
app="$home/.config/herdr-app"
mkdir -p "$app" || exit 2
printf 'existing keymap\n' > "$app/keys.json" || exit 2
if TEST_SYSTEM=Linux PATH="$TMP/bin:$PATH" HOME="$home" bash "$PKG/install.sh" > "$TMP/conflict.log" 2>&1; then
  bad 'installer accepts an existing keymap without reporting a conflict'
elif grep -q 'keys.json' "$TMP/conflict.log" && cmp -s "$app/keys.json" <(printf 'existing keymap\n') && [[ ! -e "$app/mods" ]]; then
  ok 'existing keymap is preserved and no shared files are installed on conflict'
else
  bad 'installer did not report and handle the keymap conflict'
fi

home="$TMP/upgrade"
app="$home/.config/herdr-app"
legacy="$TMP/legacy/herdr-app/.config/herdr-app"
mkdir -p "$home" "$legacy" || exit 2
printf 'old keymap\n' > "$legacy/keys.json" || exit 2
stow --no-folding -d "$TMP/legacy" -t "$home" herdr-app || exit 2
mv "$legacy/keys.json" "$legacy/keys.old.json" || exit 2
if TEST_SYSTEM=Linux PATH="$TMP/bin:$PATH" HOME="$home" bash "$PKG/install.sh" > "$TMP/upgrade.log" 2>&1; then
  bad 'installer accepts a dangling keymap link without requiring manual migration'
elif grep -q 'Move the dangling keys.json link aside' "$TMP/upgrade.log" && [[ -L "$app/keys.json" && ! -e "$app/mods" ]]; then
  mv "$app/keys.json" "$app/keys.json.old-link" || exit 2
  if TEST_SYSTEM=Linux PATH="$TMP/bin:$PATH" HOME="$home" bash "$PKG/install.sh" &&
    jq -e '.global["ctrl-shift-n"] == "space.new"' "$app/keys.json" >/dev/null && [[ -L "$app/keys.json.old-link" ]]; then
    ok 'legacy link can be moved aside without losing the old link'
  else
    bad 'installation failed after moving the legacy link aside'
  fi
else
  bad 'installer did not explain how to migrate the legacy link'
fi
exit "$fail"
