#!/bin/bash
#
# Install the uConsole login theme into <root> ("/" on a running uConsole, the
# mounted image during a build): Omarchy's SDDM theme plus a user picker (see
# Main.qml), as "omarchy-uconsole", and make SDDM use it. Omarchy's own theme
# is left untouched. Safe to run again.
#
# Takes effect the next time SDDM starts (a reboot, or
# `sudo systemctl restart sddm` while nobody is logged in).

set -euo pipefail

ROOT="${1:?usage: install-theme.sh <root>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${ROOT}/usr/share/sddm/themes/omarchy"
DST="${ROOT}/usr/share/sddm/themes/omarchy-uconsole"
CONF="${ROOT}/etc/sddm.conf.d/20-uconsole.conf"

[ -f "${SRC}/Main.qml" ] || { echo "ERROR: Omarchy's login theme is not installed (${SRC})." >&2; exit 1; }
[ -f "${CONF}" ] || { echo "ERROR: ${CONF} is missing; is this a uConsole Omarchy image?" >&2; exit 1; }

rm -rf "${DST}"
cp -r "${SRC}" "${DST}"
install -m 0644 "${HERE}/Main.qml" "${DST}/Main.qml"
sed -i 's/^Name=.*/Name=Omarchy (uConsole, user picker)/' "${DST}/metadata.desktop"

if grep -q '^\[Theme\]' "${CONF}"; then
    sed -i '/^\[Theme\]/,/^\[/ s/^Current=.*/Current=omarchy-uconsole/' "${CONF}"
    grep -q '^Current=omarchy-uconsole$' "${CONF}" || sed -i '/^\[Theme\]/a Current=omarchy-uconsole' "${CONF}"
else
    printf '\n[Theme]\nCurrent=omarchy-uconsole\n' >> "${CONF}"
fi
grep -q '^Current=omarchy-uconsole$' "${CONF}" \
    || { echo "ERROR: could not select the omarchy-uconsole theme in ${CONF}." >&2; exit 1; }
