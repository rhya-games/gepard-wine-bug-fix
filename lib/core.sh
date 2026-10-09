# Finds CrossOver and reads the facts the tools need. Sets CX_APP, DLL_DIR, DLL, VERSION,
# DLL_NAME, DLL_SRC (the ready-made fix for this version), DLL_SHA256 and BACKUP.
init_crossover() {
    CX_APP="${CX_APP:-}"
    if [ -z "$CX_APP" ]; then
        local c
        for c in "/Applications/CrossOver.app" "$HOME/Applications/CrossOver.app"; do
            [ -d "$c" ] && CX_APP="$c" && break
        done
    fi
    [ -n "$CX_APP" ] && [ -d "$CX_APP" ] || die "CrossOver.app not found in /Applications or ~/Applications."

    DLL_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
    DLL="$DLL_DIR/wow64win.dll"
    # CFBundleShortVersionString is just "26.3"; CFBundleVersion is "26.3.0.39832".
    VERSION=$(defaults read "$CX_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null | cut -d. -f1-3)
    DLL_NAME="wow64win.dll.crossover-$VERSION"
    DLL_SRC="$FIX_DIR/$DLL_NAME"
    DLL_SHA256=$(awk -v f="$DLL_NAME" '$2 == f {print $1}' "$FIX_DIR/SHA256SUMS" 2>/dev/null)
    BACKUP="$DLL.orig-$VERSION"
    [ -f "$DLL" ] || die "Could not find $DLL"
}

GAME_BOTTLE=""   # set by require_game: the bottle that holds the game

die() { echo; echo "STOP: $*"; exit 1; }

ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    printf "%s [y/N] " "$1"
    read -r answer
    case "$answer" in y|Y|yes|YES) return 0 ;; esac
    return 1
}

crossover_running() { pgrep -f "CrossOver.app/Contents/MacOS" >/dev/null 2>&1; }

# Leftover Windows processes from a CrossOver bottle that was force-quit. Their command
# line starts with a Windows path (C:\...), unlike other Wine runtimes (full unix path).
stale_pids() {
    ps -axo pid=,command= | awk '$2 ~ /^C:[\\]/ {print $1}'
}

# Make sure CrossOver is closed (asks first) and that no leftover processes remain (always cleared).
ensure_crossover_closed() {
    if crossover_running; then
        if ask "CrossOver is open. Quit it now? (save anything you need first)"; then
            osascript -e 'tell application "CrossOver" to quit' >/dev/null 2>&1
            local i=0
            while crossover_running && [ $i -lt 20 ]; do sleep 1; i=$((i + 1)); done
            crossover_running && die "CrossOver did not quit. Quit it yourself (CrossOver menu > Quit),
or use Apple menu > Force Quit, then run this again."
        else
            die "CrossOver is open. Quit it (CrossOver menu > Quit) and run this again."
        fi
    fi

    kill_leftovers
}

# Anything still running from a bottle once CrossOver is closed is a leftover that can make the
# next launch hang. Always stop it (no question asked).
kill_leftovers() {
    local pids
    pids=$(stale_pids | tr '\n' ' ')
    if [ -n "${pids// /}" ]; then
        echo "Stopping leftover Windows processes from CrossOver (PIDs: $pids)..."
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null
        sleep 2
        pids=$(stale_pids | tr '\n' ' ')
        # shellcheck disable=SC2086
        [ -n "${pids// /}" ] && kill -9 $pids 2>/dev/null && sleep 1
        echo "Done."
    fi
}

check_writable() {
    [ -w "$DLL_DIR" ] && return 0
    die "No permission to change files inside CrossOver.app.
Fix: open System Settings > Privacy & Security > App Management, turn on Terminal,
then quit and reopen Terminal and run this again. (If CrossOver was installed by
another user, run the command with sudo instead.)"
}

# The game must be installed in a CrossOver bottle first: a folder that holds both a .grf data
# archive and an .exe (the game's name differs per server, so we do not look for one name).
require_game() {
    [ "$SKIP_GAME_CHECK" = 1 ] && return 0
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" g d
    if [ -d "$bottles" ]; then
        while IFS= read -r g; do
            d=$(dirname "$g")
            if [ -n "$(find "$d" -maxdepth 1 -iname "*.exe" 2>/dev/null | head -1)" ]; then
                GAME_BOTTLE="${g#"$bottles"/}"; GAME_BOTTLE="${GAME_BOTTLE%%/*}"
                return 0
            fi
        done < <(find "$bottles" -ipath "*/drive_c/*" -iname "*.grf" \
                    -not -ipath "*/windows/*" 2>/dev/null | head -50)
    fi
    die "Ragnarok Online does not seem to be installed in a CrossOver bottle yet.
Install the game in CrossOver first (create a bottle and install it), then run this again.
(To skip this check anyway, add --skip-game-check.)"
}

# pick_one "question" item... : sets PICKED (asks if there is more than one item).
pick_one() {
    local question="$1"; shift
    local items=("$@")
    if [ ${#items[@]} -eq 1 ]; then PICKED="${items[0]}"; return; fi
    echo "$question"
    local i=1 f
    for f in "${items[@]}"; do echo "  $i) $f"; i=$((i + 1)); done
    printf "Number: "
    read -r n
    case "$n" in ''|*[!0-9]*) die "Not a number." ;; esac
    [ "$n" -ge 1 ] && [ "$n" -le ${#items[@]} ] || die "Not in the list."
    PICKED="${items[$((n - 1))]}"
}

# Sets BOTTLE_NAME; asks if there is more than one bottle.
pick_bottle() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    [ -d "$bottles" ] || die "No CrossOver bottles found. Create one in CrossOver first."
    local names=() d
    for d in "$bottles"/*/; do [ -d "$d" ] && names+=("$(basename "$d")"); done
    [ ${#names[@]} -gt 0 ] || die "No CrossOver bottles found. Create one in CrossOver first."

    BOTTLE_NAME="${names[0]}"
    if [ -n "$GAME_BOTTLE" ] && [ -d "$bottles/$GAME_BOTTLE" ]; then
        BOTTLE_NAME="$GAME_BOTTLE"      # the bottle that holds the game; no need to ask
    elif [ ${#names[@]} -gt 1 ]; then
        echo "Which bottle?"
        local i=1
        for d in "${names[@]}"; do echo "  $i) $d"; i=$((i + 1)); done
        printf "Number: "
        read -r n
        case "$n" in ''|*[!0-9]*) die "Not a number." ;; esac
        [ "$n" -ge 1 ] && [ "$n" -le ${#names[@]} ] || die "Not in the list."
        BOTTLE_NAME="${names[$((n - 1))]}"
    fi
}

# Sets GAME_DIR (the folder holding the game exe from the profile; asks if there are several).
pick_game() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" f
    local found=()
    while IFS= read -r f; do found+=("$(dirname "$f")"); done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "$GAME_EXE" -not -ipath "*/windows/*" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "$GAME_EXE was not found in any bottle."
    pick_one "Which game folder?" "${found[@]}"
    GAME_DIR="$PICKED"
}

# True if a Wine process of the game in folder $1 is running (its command line holds the
# Windows path, e.g. ...\Programs\<game folder>\game.exe).
game_running() {
    ps -axo command | grep -F -- "\\$1\\" | grep -qv grep
}
