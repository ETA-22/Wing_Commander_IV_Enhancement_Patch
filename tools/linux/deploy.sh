#!/bin/sh
# Copy the built DLL into a game folder over SSH, keeping the original as <dll>.bak-orig.
#   WC4_HOST      ssh destination, e.g. deck@steamdeck
#   WC4_GAME_DIR  remote folder holding the DLL (e.g. .../Wing Commander IV/WC4_Enhanced)
# usage: deploy.sh [build/dwrap.dll]     deploy
#        deploy.sh --restore [dwrap.dll] put the original back
# Password-only hosts: set SSHPASS and have sshpass installed.
set -eu
: "${WC4_HOST:?set WC4_HOST}" "${WC4_GAME_DIR:?set WC4_GAME_DIR}"
ssh_() { if [ -n "${SSHPASS:-}" ]; then sshpass -e ssh "$WC4_HOST" "$@"; else ssh "$WC4_HOST" "$@"; fi; }
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

if [ "${1:-}" = "--restore" ]; then
  dst="$WC4_GAME_DIR/$(basename "${2:-dwrap.dll}")"
  ssh_ "test -f $(q "$dst.bak-orig") && cp $(q "$dst.bak-orig") $(q "$dst") && sha256sum $(q "$dst")"
  exit
fi
dll=${1:-build/dwrap.dll}
[ -f "$dll" ] || { echo "no such file: $dll" >&2; exit 1; }
dst="$WC4_GAME_DIR/$(basename "$dll")"
ssh_ "test -f $(q "$dst") && { test -f $(q "$dst.bak-orig") || cp $(q "$dst") $(q "$dst.bak-orig"); }; cat > $(q "$dst.new") && mv $(q "$dst.new") $(q "$dst") && sha256sum $(q "$dst")" < "$dll"
sha256sum "$dll"
