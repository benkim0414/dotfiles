#!/usr/bin/env bash
set -euo pipefail

package="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(uname -s)" in
  Darwin) keymap=macos ;;
  Linux) keymap=linux ;;
  *) printf 'Herdr App dotfiles support macOS and Linux only.\n' >&2; exit 2 ;;
esac

mode="${1:-}"
case "$mode" in
  ''|--dry-run|--delete) ;;
  *) printf 'Usage: %s [--dry-run|--delete]\n' "$0" >&2; exit 2 ;;
esac

shared=(--no-folding -d "$package/.." -t "$HOME" herdr-app)
platform=(--no-folding -d "$package/keymaps" -t "$HOME" "$keymap")
if [[ "$mode" == --delete ]]; then
  stow --delete "${platform[@]}"
  stow --delete "${shared[@]}"
  exit
fi

keys="$HOME/.config/herdr-app/keys.json"
if [[ -L "$keys" && ! -e "$keys" ]]; then
  printf 'Move the dangling keys.json link aside, then retry: %s\n' "$keys" >&2
  exit 1
fi

# Find conflicts in both packages before linking either one.
stow --simulate --verbose "${shared[@]}"
stow --simulate --verbose "${platform[@]}"
if [[ "$mode" != --dry-run ]]; then
  stow "${shared[@]}"
  stow "${platform[@]}"
fi
