# Start the SSH agent and load keys once per login; writes socket to ~/.keychain/.
# Only prompt from an interactive terminal so non-interactive shells do not
# fail through ssh-askpass when no TTY is available.
if command -v keychain &>/dev/null && [[ -o interactive && -t 0 ]]; then
    eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
fi

# Start Hyprland on the first TTY as a systemd-managed Wayland session.
# `uwsm check may-start` keeps this from firing inside nested terminals,
# SSH sessions, or an already-running graphical session.
if command -v uwsm &>/dev/null \
    && [[ -z ${DISPLAY-} && -z ${WAYLAND_DISPLAY-} && "$(tty)" == /dev/tty1 ]] \
    && uwsm check may-start &>/dev/null; then
    exec uwsm start hyprland.desktop
fi
