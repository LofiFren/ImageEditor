# /etc/profile.d/uconsole-drm.sh -- point Hyprland at the uConsole's screen.
#
# A CM4 exposes two DRM devices: v3d (the 3D engine, render-only, no outputs)
# and vc4 (the display controller the DSI panel hangs off). Their cardN
# numbers are not stable between boots or kernels. If Hyprland's backend picks
# the v3d one it finds no monitors and the screen stays black, so point it at
# whichever card is driven by vc4.
#
# Lives in profile.d so every login path picks it up: SDDM's Wayland sessions
# source /etc/profile, and so do console logins. The SDDM greeter, which does
# not, gets it through /usr/local/bin/uconsole-hyprland.

if [ -z "${AQ_DRM_DEVICES:-}" ]; then
    for _uconsole_card in /sys/class/drm/card[0-9]; do
        case "$(basename "$(readlink -f "${_uconsole_card}/device/driver")" 2>/dev/null)" in
            vc4*)
                export AQ_DRM_DEVICES="/dev/dri/$(basename "${_uconsole_card}")"
                break
                ;;
        esac
    done
    unset _uconsole_card
fi
