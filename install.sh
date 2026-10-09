#!/bin/bash
# Ragnarok Online tools for CrossOver on macOS: the Gepard fix, plus optional extras.
#
#   bash install.sh              install the fix
#   bash install.sh check        is the bug present / is the fix working?
#   bash install.sh uninstall    put the original file back
#   bash install.sh setup        new installs only: patch the game's setup.exe
#   bash install.sh play         clear leftover processes, then start the game
# OPTIONAL extras (not needed for the fix):
#   bash install.sh extras       install the fix AND add the extras (window fit, Mac keys, AzzyAI, launchers)
#   bash install.sh extras undo  remove both extras (the fix stays installed)
#   bash install.sh window       fit the game window to the usable screen area
#   bash install.sh window undo  put the game's window settings back
#   bash install.sh window status  show the current and the fitted size
#   bash install.sh keys on      Mac Option=Alt, Command stays Command, no display capture
#   bash install.sh keys off     undo the Mac key settings
#   bash install.sh keys status  show what is set
#   bash install.sh azzyai       install the latest AzzyAI (uaRO pre-renewal) from GitHub
#   bash install.sh azzyai undo  put the game's original AI folder back
#   bash install.sh launchers    add CrossOver launcher icons (game, setup, AzzyAI config)
#   bash install.sh launchers remove  remove them (and restore the patcher shortcut name)
#
# Add -y to answer "yes" to the questions (quit CrossOver, fix setup.exe). Leftover processes
# are always stopped, without asking.
# Everything except "uninstall" first checks that the game is installed in a CrossOver
# bottle; --skip-game-check turns that check off.
#
# Ready-made DLLs live in fix/ (wow64win.dll.crossover-<version>, listed in fix/SHA256SUMS).
# Game-specific settings live in profiles/<name>/profile.conf (default: uaro; PROFILE=name to
# switch). Code is in lib/. Docs: docs/

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1
FIX_DIR="$ROOT/fix"

for part in core fix extras game uaro; do
    # shellcheck source=/dev/null
    . "$ROOT/lib/$part.sh"
done

PROFILE="${PROFILE:-uaro}"
PROFILE_DIR="$ROOT/profiles/$PROFILE"
[ -f "$PROFILE_DIR/profile.conf" ] || die "There is no profile named '$PROFILE' (looked for $PROFILE_DIR/profile.conf)."
# shellcheck source=/dev/null
. "$PROFILE_DIR/profile.conf"

ASSUME_YES=0
SKIP_GAME_CHECK=0
CMD=""
ARG1=""
n=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --skip-game-check) SKIP_GAME_CHECK=1 ;;
        *)
            n=$((n + 1))
            case $n in 1) CMD="$arg" ;; 2) ARG1="$arg" ;; esac ;;
    esac
done

init_crossover

case "${CMD:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    check)     do_check ;;
    extras)    do_extras ;;
    keys)      do_keys ;;
    window)    do_window ;;
    azzyai)    do_azzyai ;;
    launchers) do_launchers ;;
    setup)     do_setup ;;
    play)      do_play ;;
    *)         echo "Usage: bash install.sh [install|check|uninstall|setup|play|extras|window|keys|azzyai|launchers] [-y]"; exit 1 ;;
esac
