# Optional extras that work for any game: window fit and Mac keyboard settings; do_extras runs
# them all together with the AzzyAI and launcher extras.
TITLE_BAR=28     # height of the window's title bar in points, measured on one Mac

# Wine's Mac driver settings (HKCU\Software\Wine\Mac Driver), written by `keys on`.
KEYS_KEY='HKCU\Software\Wine\Mac Driver'
KEYS_ON="LeftCommandIsCtrl=N RightCommandIsCtrl=N LeftOptionIsAlt=Y RightOptionIsAlt=Y CaptureDisplaysForFullscreen=N"

screen_area() {   # prints: usable-width usable-height x-origin top-offset
    osascript -l JavaScript -e '
        ObjC.import("AppKit");
        const s = $.NSScreen.screens.objectAtIndex(0);
        const f = s.frame, v = s.visibleFrame;
        console.log([Math.round(v.size.width), Math.round(v.size.height), Math.round(v.origin.x),
                     Math.round(f.size.height - v.origin.y - v.size.height)].join(" "));' 2>&1
}

lua_get() { sed -n "s/^OptionInfoList\[\"$2\"\] *= *\(-\{0,1\}[0-9]*\).*/\1/p" "$1" | head -1; }

do_window() {
    require_game
    local action="${ARG1:-fit}"
    case "$action" in fit|undo|status) ;; *) die "Usage: bash install.sh window [fit|undo|status]" ;; esac
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    command -v python3 >/dev/null || die "python3 is needed. Run: xcode-select --install"

    local found=() f
    while IFS= read -r f; do found+=("$f"); done < <(
        find "$bottles" -ipath "*/drive_c/*/savedata/*" -iname "OptionInfo.lua" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "Could not find the game's OptionInfo.lua. Start the game once first."
    pick_one "Which game's settings?" "${found[@]}"
    local file="$PICKED" backup="$PICKED.before-window-fit.backup"
    local gamedir; gamedir=$(basename "$(dirname "$(dirname "$file")")")

    local area w h x y
    area=$(screen_area)
    case "$area" in *[!0-9\ -]*|"") die "Could not read the screen size from macOS: $area" ;; esac
    read -r w h x y <<EOF2
$area
EOF2
    local fit_w=$w fit_h=$((h - TITLE_BAR))

    if [ "$action" = "status" ]; then
        echo "Game settings : $file"
        echo "Now           : $(lua_get "$file" WIDTH) x $(lua_get "$file" HEIGHT), windowed=$([ "$(lua_get "$file" ISFULLSCREENMODE)" = 0 ] && echo yes || echo no), position $(lua_get "$file" Window_XPos),$(lua_get "$file" Window_YPos)"
        echo "Would fit to  : $fit_w x $fit_h at $x,$y (usable area $w x $h, title bar $TITLE_BAR)"
        [ -e "$backup" ] && echo "Backup exists : $backup"
        return 0
    fi

    game_running "$gamedir" \
        && die "The game is running. Quit it completely first: it rewrites its settings when it closes."

    if [ "$action" = "undo" ]; then
        [ -e "$backup" ] || die "No backup found ($backup). Nothing to undo."
        cp -p "$backup" "$file" || die "Could not restore the backup."
        echo "Restored the previous window settings."
        return 0
    fi

    [ -e "$backup" ] || cp -p "$file" "$backup" || die "Could not back up OptionInfo.lua."
    python3 - "$file" "$fit_w" "$fit_h" "$x" "$y" <<'PYEOF' || die "Could not edit OptionInfo.lua."
import re, sys
path, w, h, x, y = sys.argv[1], *map(int, sys.argv[2:6])
s = open(path, newline="").read()
for key, val in (("ISFULLSCREENMODE", 0), ("WIDTH", w), ("HEIGHT", h), ("OLD_WIDTH", w),
                 ("OLD_HEIGHT", h), ("Window_XPos", x), ("Window_YPos", y)):
    s, n = re.subn(r'(OptionInfoList\["%s"\]\s*=\s*)-?\d+' % key, r'\g<1>%d' % val, s)
    if n != 1:
        sys.exit("expected exactly one %s line, found %d" % (key, n))
open(path, "w", newline="").write(s)
PYEOF
    echo "Window fitted: ${fit_w} x ${fit_h} at ${x},${y}, windowed mode."
    echo "(Usable screen area $w x $h minus a $TITLE_BAR px title bar.)"
    echo "Backup of your previous settings: $backup"
    echo "Undo any time with:  bash install.sh window undo"
}

keys_wine() {
    "$CX_APP/Contents/SharedSupport/CrossOver/bin/wine" --bottle "$BOTTLE_NAME" --no-gui "$@" 2>/dev/null
}

keys_value() {   # prints the stored value of $1, or nothing
    keys_wine reg query "$KEYS_KEY" /v "$1" | awk -v n="$1" '$1 == n {print $NF}' | tr -d '\r'
}

do_keys_status() {
    local pair name v
    echo "Bottle: $BOTTLE_NAME"
    for pair in $KEYS_ON; do
        name="${pair%%=*}"
        v=$(keys_value "$name")
        printf "  %-30s %s\n" "$name" "${v:-not set (Wine default)}"
    done
    echo
    echo "  Mac Control key -> Left Ctrl is Wine's default; nothing to set."
}

do_keys() {
    require_game
    local action="${ARG1:-status}"
    case "$action" in on|off|status) ;; *) die "Usage: bash install.sh keys [on|off|status]" ;; esac
    pick_bottle
    local pair name val

    case "$action" in
        on)
            for pair in $KEYS_ON; do
                name="${pair%%=*}"; val="${pair#*=}"
                keys_wine reg add "$KEYS_KEY" /v "$name" /t REG_SZ /d "$val" /f >/dev/null \
                    || die "Could not write the setting $name to the bottle."
            done
            echo "Turned on, for bottle $BOTTLE_NAME:"
            echo "  - Both Command keys stay normal Mac Command keys (Cmd+C / Cmd+V, screenshots with"
            echo "    Cmd+Shift+3/4/5, Cmd+Tab and so on)"
            echo "  - Mac Control key = Left Ctrl (Wine's default, unchanged)"
            echo "  - Option keys work as Alt (in-game shortcuts are Option+letter)"
            echo "  - Wine does not capture the display in full screen (Cmd+Tab still does not work"
            echo "    in full screen; use windowed mode, see README)"
            echo
            echo "Quit CrossOver completely and reopen it, then start the game. Settings load when"
            echo "the bottle starts."
            ;;
        off)
            for pair in $KEYS_ON; do
                name="${pair%%=*}"
                keys_wine reg delete "$KEYS_KEY" /v "$name" /f >/dev/null
            done
            echo "Turned off for bottle $BOTTLE_NAME. Wine's defaults are back"
            echo "(Command = Alt, Option = unused). Restart CrossOver to apply."
            ;;
        status)
            do_keys_status
            ;;
    esac
}

# OPTIONAL extras. `extras` installs the fix AND adds both extras; `extras undo` removes the
# extras only. A problem with one extra does not stop the other.
do_extras() {
    require_game
    if [ "${ARG1:-}" = "undo" ]; then
        echo "== Mac keyboard settings: off =="; ARG1=off; ( do_keys ) || echo "(skipped)"
        echo; echo "== Game window: undo =="; ARG1=undo; ( do_window ) || echo "(skipped)"
        echo; echo "== AzzyAI: remove =="; ARG1=undo; ( do_azzyai ) || echo "(skipped)"
        echo; echo "== CrossOver launchers: remove =="; ARG1=remove; ( do_launchers ) || echo "(skipped)"
        return 0
    fi
    [ -z "${ARG1:-}" ] || die "Usage: bash install.sh extras [undo]"
    echo "== The fix =="; INSTALL_QUIET=1 do_install
    echo; echo "== Mac keyboard settings: on =="; ARG1=on; ( do_keys ) || echo "(skipped)"
    echo; echo "== Game window: fit =="; ARG1=fit; ( do_window ) || echo "(skipped)"
    echo; echo "== AzzyAI (asks first) =="; ARG1=install; ( do_azzyai ) || echo "(skipped)"
    echo; echo "== CrossOver launchers =="; ARG1=add; ( do_launchers ) || echo "(skipped)"
    echo
    echo "Now open CrossOver (quit it completely first if it was open) and start the game."
    echo "A CrossOver update will remove the fix; run this script again afterwards."
}
