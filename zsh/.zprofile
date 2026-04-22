# Start the SSH agent and load keys once per boot; writes socket to ~/.keychain/.
if command -v keychain &>/dev/null; then
    eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
fi
