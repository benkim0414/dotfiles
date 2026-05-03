# Start the SSH agent and load keys once per login; writes socket to ~/.keychain/.
# Only prompt from an interactive terminal so non-interactive shells do not
# fail through ssh-askpass when no TTY is available.
if command -v keychain &>/dev/null && [[ -o interactive && -t 0 ]]; then
    eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
fi
