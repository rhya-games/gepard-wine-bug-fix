# Game launching and CrossOver launcher icons. Names and files come from the profile.

# Starts the game. If CrossOver is closed, first stops any leftover processes (they can make
# CrossOver hang). Uses the "UaRO Game" launcher app when it exists, otherwise starts uaRO.exe
# through CrossOver's wine. PLAY_DRY_RUN=1 only prints what it would do.
do_play() {
    require_game
    pick_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local rel="${GAME_DIR#"$bottles"/}" bottle gamename winrel app
    bottle="${rel%%/*}"; gamename=$(basename "$GAME_DIR")
    winrel="${GAME_DIR#"$bottles/$bottle"/drive_c/}"
    game_running "$gamename" && { echo "The game is already running."; return 0; }

    if ! crossover_running; then
        if [ "${PLAY_DRY_RUN:-0}" = 1 ]; then
            local p; p=$(stale_pids | tr '\n' ' ')
            [ -n "${p// /}" ] && echo "(dry run) would stop leftover processes: $p"
        else
            kill_leftovers
        fi
    fi

    app=$(find "$HOME/Applications/CrossOver" -maxdepth 3 -name "$LAUNCHER_GAME.app" -path "*/$gamename/*" 2>/dev/null | head -1)
    if [ -n "$app" ]; then
        echo "Starting the game from its CrossOver launcher..."
        [ "${PLAY_DRY_RUN:-0}" = 1 ] && { echo "(dry run) would run: open \"$app\""; return 0; }
        open "$app"
    else
        echo "Starting the game through CrossOver (run 'bash install.sh launchers' for a proper icon)..."
        local win="C:\\${winrel//\//\\}"
        [ "${PLAY_DRY_RUN:-0}" = 1 ] && { echo "(dry run) would run: wine --bottle $bottle ... $win\\$GAME_EXE"; return 0; }
        "$CX_APP/Contents/SharedSupport/CrossOver/bin/wine" --bottle "$bottle" --workdir "$win" \
            --cx-app "$win\\$GAME_EXE" >/dev/null 2>&1 &
        disown 2>/dev/null
    fi
}

# Renames the installer's shortcut that starts the patcher ("<game folder>.lnk", in the Start
# Menu folder and on the Desktop) to "UaRO Patcher.lnk", or back. Only touches a shortcut whose
# target is UaRo Patcher.exe.
rename_patcher_shortcuts() {   # $1 = bottle dir, $2 = game folder name, $3 = from, $4 = to
    local f dir
    RENAMED=0
    while IFS= read -r f; do
        dir=$(dirname "$f")
        [ -e "$dir/$4.lnk" ] && continue
        grep -qai "${PATCHER_EXE%.exe}" "$f" && mv "$f" "$dir/$4.lnk" && RENAMED=$((RENAMED + 1))
    done < <(find "$1/drive_c/users" \( -path "*/Start Menu/Programs/$2/$3.lnk" -o -path "*/Desktop/$3.lnk" \) 2>/dev/null)
}

# Builds sharp-enough icons for the Game and Patcher launchers from the game's own icnbig.ico
# (48 px; the Game's own exe icon is only 32 px, and the Patcher's launcher app is left with
# CrossOver's generic icon). Fills CrossOver's icon cache with larger sizes and replaces the
# icon of the two launcher apps in ~/Applications/CrossOver. Silently does nothing if the game
# has no icnbig.ico. Re-run `launchers` if CrossOver ever rebuilds those apps.
fix_launcher_icons() {   # $1 = bottle dir, $2 = game folder name, $3 = game dir, $4 = bottle name
    local ico="$3/$ICON_FILE"
    [ -f "$ico" ] || return 0
    local tmp; tmp=$(mktemp -d) || return 0
    local base="$tmp/base.png" set="$tmp/icon.iconset" n
    sips -s format png "$ico" --out "$base" >/dev/null 2>&1 || { rm -rf "$tmp"; return 0; }
    mkdir -p "$set"
    for n in 16 32 48 64 128 256 512 1024; do
        sips -z $n $n "$base" --out "$tmp/s$n.png" >/dev/null 2>&1
    done
    cp "$tmp/s16.png" "$set/icon_16x16.png";      cp "$tmp/s32.png" "$set/icon_16x16@2x.png"
    cp "$tmp/s32.png" "$set/icon_32x32.png";      cp "$tmp/s64.png" "$set/icon_32x32@2x.png"
    cp "$tmp/s128.png" "$set/icon_128x128.png";   cp "$tmp/s256.png" "$set/icon_128x128@2x.png"
    cp "$tmp/s256.png" "$set/icon_256x256.png";   cp "$tmp/s512.png" "$set/icon_256x256@2x.png"
    cp "$tmp/s512.png" "$set/icon_512x512.png";   cp "$tmp/s1024.png" "$set/icon_512x512@2x.png"
    iconutil -c icns -o "$tmp/icon.icns" "$set" >/dev/null 2>&1 || { rm -rf "$tmp"; return 0; }

    # CrossOver's icon cache: add 48 px and larger sizes for the Game and Patcher icons.
    local conf="$1/cxmenu.conf" name id
    for name in "$LAUNCHER_GAME" "$LAUNCHER_PATCHER"; do
        id=$(awk -v n="/$name.lnk]" 'index($0, n) {f=1; next} /^\[/ {f=0} f && /^"Icon"/ {gsub(/.*= *"|"/, ""); print; exit}' "$conf")
        [ -n "$id" ] || continue
        for n in 48 64 128 256 512; do
            mkdir -p "$1/windata/cxmenu/icons/hicolor/${n}x${n}/apps"
            cp "$tmp/s$n.png" "$1/windata/cxmenu/icons/hicolor/${n}x${n}/apps/$id.png" 2>/dev/null \
                || sips -z $n $n "$base" --out "$1/windata/cxmenu/icons/hicolor/${n}x${n}/apps/$id.png" >/dev/null 2>&1
        done
    done
    "$CX_APP/Contents/SharedSupport/CrossOver/bin/cxmenu" --install --bottle "$4" >/dev/null 2>&1

    # The launcher apps CrossOver made for them.
    local app
    for name in "$LAUNCHER_GAME" "$LAUNCHER_PATCHER"; do
        app=$(find "$HOME/Applications/CrossOver" -maxdepth 3 -name "$name.app" -path "*/$2/*" 2>/dev/null | head -1)
        [ -n "$app" ] && [ -d "$app/Contents/Resources" ] || continue
        cp "$tmp/icon.icns" "$app/Contents/Resources/CrossOverHelper.icns" && touch "$app"
    done
    rm -rf "$tmp"
}

do_launchers() {
    require_game
    local action="${ARG1:-add}"
    case "$action" in add|remove) ;; *) die "Usage: bash install.sh launchers [remove]" ;; esac
    pick_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local rel="${GAME_DIR#"$bottles"/}" bottle bdir gamename winrel wingame
    bottle="${rel%%/*}"; bdir="$bottles/$bottle"; gamename=$(basename "$GAME_DIR")
    winrel="${GAME_DIR#"$bdir"/drive_c/}"; wingame="C:\\${winrel//\//\\}"
    local wine="$CX_APP/Contents/SharedSupport/CrossOver/bin/wine"
    local cxmenu="$CX_APP/Contents/SharedSupport/CrossOver/bin/cxmenu"
    local entry name exe desc

    if [ "$action" = "remove" ]; then
        for entry in "${LAUNCHERS[@]}"; do
            IFS='|' read -r name exe desc <<EOF2
$entry
EOF2
            find "$bdir/drive_c/users" -path "*/Start Menu/Programs/$gamename/$name.lnk" -delete 2>/dev/null
        done
        rename_patcher_shortcuts "$bdir" "$gamename" "$LAUNCHER_PATCHER" "$gamename"
        "$cxmenu" --sync --bottle "$bottle" --mode install >/dev/null 2>&1
        echo "Removed the launcher icons from the CrossOver bottle $bottle."
        return 0
    fi

    # Wine's script engine has no SpecialFolders, so build the Start Menu path ourselves.
    local user; user=$(ls "$bdir/drive_c/users" 2>/dev/null | grep -vi "^public$" | head -1)
    [ -n "$user" ] || die "Could not find the Windows user folder in the bottle."
    mkdir -p "$bdir/drive_c/users/$user/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/$gamename" \
        || die "Could not create the Start Menu folder."
    local winmenu="C:\\users\\$user\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\$gamename"

    local vbs="$bdir/drive_c/launchers-$$.vbs" made=() skipped=() exepath dirpart
    {
        echo 'Set sh = CreateObject("WScript.Shell")'
        echo "folder = \"$winmenu\""
        for entry in "${LAUNCHERS[@]}"; do
            IFS='|' read -r name exe desc <<EOF2
$entry
EOF2
            exepath="$GAME_DIR/${exe//\\//}"
            if [ ! -f "$exepath" ]; then skipped+=("$name"); continue; fi
            made+=("$name")
            dirpart="${exe%\\*}"; [ "$dirpart" = "$exe" ] && dirpart=""
            echo "Set l = sh.CreateShortcut(folder & \"\\$name.lnk\")"
            echo "l.TargetPath = \"$wingame\\$exe\""
            echo "l.WorkingDirectory = \"$wingame${dirpart:+\\$dirpart}\""
            echo "l.Description = \"$desc\""
            echo "l.Save"
        done
    } > "$vbs"
    "$wine" --bottle "$bottle" --no-gui wscript.exe //nologo "C:\\$(basename "$vbs")" >/dev/null 2>&1
    local rc=$?
    rm -f "$vbs"
    [ $rc -eq 0 ] || die "Could not create the launchers (Wine's script engine failed)."
    rename_patcher_shortcuts "$bdir" "$gamename" "$gamename" "$LAUNCHER_PATCHER"
    "$cxmenu" --sync --bottle "$bottle" --mode install >/dev/null 2>&1
    fix_launcher_icons "$bdir" "$gamename" "$GAME_DIR" "$bottle"

    # (${arr[@]+...} keeps an empty list from tripping `set -u` on the macOS bash 3.2)
    [ "$RENAMED" -gt 0 ] && echo "Renamed the patcher's shortcut to: $LAUNCHER_PATCHER"
    for name in ${made[@]+"${made[@]}"}; do echo "Added launcher: $name"; done
    for name in ${skipped[@]+"${skipped[@]}"}; do echo "Skipped: $name (its program is not in the game folder yet)"; done
    echo "They appear in CrossOver under the bottle $bottle (reopen CrossOver if it is open)."
    echo "Remove them with: bash install.sh launchers remove"
}
