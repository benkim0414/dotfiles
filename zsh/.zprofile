# Load SSH keys into the agent once per boot (login shells only).
# --inherit any reuses the existing SSH_AUTH_SOCK (systemd service on Linux,
# .zshenv-started agent on macOS) instead of spawning a duplicate agent.
if command -v keychain &>/dev/null; then
    eval "$(keychain --eval --quiet --inherit any --agents ssh ~/.ssh/id_ed25519)"
fi
