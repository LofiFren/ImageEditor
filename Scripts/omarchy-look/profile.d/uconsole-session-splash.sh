# /etc/profile.d/uconsole-session-splash.sh -- Omarchy's logo on the session's
# text console while a desktop login starts.
#
# After the login screen closes, the screen shows the new session's text
# console for several seconds before Hyprland draws anything. SDDM's session
# script sources /etc/profile at that point, so start the splash there, in the
# background. Only for that case: a graphical (wayland) session on a VT, with
# no compositor yet. Console logins, SSH and terminals are left alone.

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ -n "${XDG_VTNR:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] \
    && [ -x /usr/local/bin/uconsole-session-splash ] && [ -w "/dev/tty${XDG_VTNR}" ] \
    && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ ! -e "${XDG_RUNTIME_DIR}/uconsole-session-splash.${XDG_SESSION_ID:-0}" ]; then
    : > "${XDG_RUNTIME_DIR}/uconsole-session-splash.${XDG_SESSION_ID:-0}"
    ( /usr/local/bin/uconsole-session-splash --console "/dev/tty${XDG_VTNR}" & ) >/dev/null 2>&1
fi
