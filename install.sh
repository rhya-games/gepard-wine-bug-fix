#!/bin/bash
# Installs / removes the Wine fix for "Gepard::T Code: 3::110::12" on CrossOver.
#
#   bash install.sh              install the fix
#   bash install.sh check        is the bug present / is the fix working?
#   bash install.sh uninstall    put the original file back
#   bash install.sh setup        new installs only: patch the game's setup.exe
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
# Prebuilt DLL = CrossOver 26.3.0 only. Details: DETAILS.md

set -u
cd "$(dirname "$0")" || exit 1

SUPPORTED="26.3.0"
DLL_SRC="wow64win.dll.crossover-26.3.0"
DLL_SHA256="c2cc2d3a25b9b74bd2269b209debfbaaaafcf28c40def18ada05993aab80d701"

# CX_APP can be overridden for testing.
CX_APP="${CX_APP:-}"
if [ -z "$CX_APP" ]; then
    for c in "/Applications/CrossOver.app" "$HOME/Applications/CrossOver.app"; do
        [ -d "$c" ] && CX_APP="$c" && break
    done
fi

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

die() { echo; echo "STOP: $*"; exit 1; }

ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    printf "%s [y/N] " "$1"
    read -r answer
    case "$answer" in y|Y|yes|YES) return 0 ;; esac
    return 1
}

[ -n "$CX_APP" ] && [ -d "$CX_APP" ] || die "CrossOver.app not found in /Applications or ~/Applications."

DLL_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
DLL="$DLL_DIR/wow64win.dll"
# CFBundleShortVersionString is just "26.3"; CFBundleVersion is "26.3.0.39832".
VERSION=$(defaults read "$CX_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null | cut -d. -f1-3)
BACKUP="$DLL.orig-$VERSION"

[ -f "$DLL" ] || die "Could not find $DLL"

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

    # CrossOver is closed now, so anything still running from a bottle is a leftover that can
    # make the next launch hang. Always stop it (no question asked).
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

GAME_BOTTLE=""   # set by require_game: the bottle that holds the game

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

# If the game's setup.exe is the known build that crashes on Macs, offer to fix it.
maybe_patch_setup() {
    command -v python3 >/dev/null || return 0
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" f
    local todo=()
    while IFS= read -r f; do
        python3 patch_opensetup_rosetta.py --check "$f" >/dev/null 2>&1 && todo+=("$f")
    done < <(find "$bottles" -ipath "*/drive_c/*" -iname "setup.exe" -not -ipath "*/windows/*" \
                 -not -ipath "*/Program Files*/Common Files/*" 2>/dev/null)
    [ ${#todo[@]} -gt 0 ] || return 0

    echo
    echo "The game's setup window (setup.exe) crashes on Macs unless it is fixed:"
    for f in "${todo[@]}"; do
        echo "  $f"
        if ask "Fix it now?"; then
            python3 patch_opensetup_rosetta.py "$f" >/dev/null && echo "  Fixed (backup kept next to it)." \
                || echo "  Could not fix it. Run: bash install.sh setup"
        else
            echo "  Skipped. You can fix it later with: bash install.sh setup"
        fi
    done
}

do_install() {
    require_game
    if [ "$VERSION" != "$SUPPORTED" ]; then
        echo "The ready-made fix is for CrossOver $SUPPORTED only; you have ${VERSION:-an unknown version}."
        echo "Checking whether your version has the bug at all..."
        echo
        do_check
        return
    fi
    [ -f "$DLL_SRC" ] || die "$DLL_SRC is missing. Run this from the downloaded folder."
    [ "$(shasum -a 256 "$DLL_SRC" | cut -d' ' -f1)" = "$DLL_SHA256" ] \
        || die "$DLL_SRC does not match the expected checksum. Re-download it."

    if cmp -s "$DLL_SRC" "$DLL"; then
        echo "The Wine fix is already installed."
    else
        check_writable
        ensure_crossover_closed

        [ -e "$BACKUP" ] || cp -p "$DLL" "$BACKUP" || die "Could not back up the original file (permission?)."
        cp "$DLL_SRC" "$DLL" || die "Could not write to CrossOver.app. See the App Management note above."
        cmp -s "$DLL_SRC" "$DLL" || die "Copy did not verify."

        echo "Installed the fix for CrossOver $VERSION."
        echo "Backup of the original: $BACKUP"
    fi

    maybe_patch_setup

    echo
    echo "Checking that the fix works (a few seconds)..."
    ( do_check ) || echo "(The check could not run. Try it later with: bash install.sh check)"

    [ "${INSTALL_QUIET:-0}" = 1 ] && return 0
    echo
    echo "Now open CrossOver and start the game."
    echo "A CrossOver update will remove the fix; run this script again afterwards."
}

do_uninstall() {
    check_writable
    ensure_crossover_closed
    [ -e "$BACKUP" ] || die "No backup for CrossOver $VERSION ($BACKUP), so nothing to restore.
If CrossOver was updated since you installed the fix, the fix is already gone."
    cp -p "$BACKUP" "$DLL" || die "Could not restore the original file."
    echo "Original file restored. The fix is removed."
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

do_check() {
    require_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local probe="rawinput_overflow_probe.exe"
    [ -f "$probe" ] || die "$probe is missing. Run this from the downloaded folder."
    [ -d "$bottles" ] || die "No CrossOver bottles found. Create one in CrossOver first."

    pick_bottle
    local bottle="$BOTTLE_NAME"

    local installed="no"
    cmp -s "$DLL_SRC" "$DLL" 2>/dev/null && installed="yes"

    echo "CrossOver version : ${VERSION:-unknown}"
    echo "Fix installed     : $installed"
    echo "Testing in bottle : $bottle (takes a few seconds)"

    local dest="$bottles/$bottle/drive_c/rawinput_overflow_probe.exe" out
    cp "$probe" "$dest" || die "Could not copy the test program into the bottle."
    out=$("$CX_APP/Contents/SharedSupport/CrossOver/bin/wine" --bottle "$bottle" --no-gui \
        --debugmsg -all --cx-app 'C:\rawinput_overflow_probe.exe' 2>&1)
    rm -f "$dest"

    echo
    case "$out" in
        *AFFECTED=no*)
            if [ "$installed" = "yes" ]; then
                echo "RESULT: the fix is installed and working."
            else
                echo "RESULT: your CrossOver does not have the bug. You do not need this fix."
            fi ;;
        *AFFECTED=yes*)
            if [ "$installed" = "yes" ]; then
                echo "RESULT: the fix is installed, but the bug is still showing."
                echo "Quit CrossOver completely (and leftovers: bash install.sh does this), then"
                echo "run 'bash install.sh check' again."
            elif [ "$VERSION" = "$SUPPORTED" ]; then
                echo "RESULT: the bug is present. Run:  bash install.sh"
            else
                echo "RESULT: the bug is present, but there is no ready-made fix for CrossOver"
                echo "$VERSION yet. See DETAILS.md (\"Other CrossOver versions\") to build one."
            fi ;;
        *)
            echo "RESULT: the test did not finish. Output was:"
            echo "$out" | tail -5
            exit 1 ;;
    esac
}

# True if a Wine process of the game in folder $1 is running (its command line holds the
# Windows path, e.g. ...\Programs\<game folder>\game.exe).
game_running() {
    ps -axo command | grep -F -- "\\$1\\" | grep -qv grep
}

# OPTIONAL: fit the game's window to the usable screen area (below the menu bar, above
# the Dock) by editing savedata/OptionInfo.lua. The 28 px title bar was measured on one Mac.
TITLE_BAR=28

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

# Optional Mac keyboard / trackpad settings, stored in the bottle's registry under
# HKCU\Software\Wine\Mac Driver. Wine reads them when the bottle starts.
KEYS_KEY='HKCU\Software\Wine\Mac Driver'
KEYS_ON="LeftCommandIsCtrl=N RightCommandIsCtrl=N LeftOptionIsAlt=Y RightOptionIsAlt=Y CaptureDisplaysForFullscreen=N"

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

# Sets GAME_DIR (the folder holding uaRO.exe; asks if there is more than one).
pick_game() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" f
    local found=()
    while IFS= read -r f; do found+=("$(dirname "$f")"); done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "uaRO.exe" -not -ipath "*/windows/*" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "uaRO.exe was not found in any bottle."
    pick_one "Which game folder?" "${found[@]}"
    GAME_DIR="$PICKED"
}

# OPTIONAL: launcher icons in the CrossOver bottle (the program list) for the game itself
# (not the patcher), its setup program and, if installed, the AzzyAI config tool.
# Entries: name | exe relative to the game folder | description
LAUNCHERS=(
    "UaRO Game|uaRO.exe|UaRO game"
    "UaRO Setup|setup.exe|UaRO graphics and sound setup"
    "AzzyAI Config|AI\\USER_AI\\AzzyAiConfigPreRe.exe|AzzyAI settings"
)

# Renames the installer's shortcut that starts the patcher ("<game folder>.lnk", in the Start
# Menu folder and on the Desktop) to "UaRO Patcher.lnk", or back. Only touches a shortcut whose
# target is UaRo Patcher.exe.
rename_patcher_shortcuts() {   # $1 = bottle dir, $2 = game folder name, $3 = from, $4 = to
    local f dir
    RENAMED=0
    while IFS= read -r f; do
        dir=$(dirname "$f")
        [ -e "$dir/$4.lnk" ] && continue
        grep -qai "UaRo Patcher" "$f" && mv "$f" "$dir/$4.lnk" && RENAMED=$((RENAMED + 1))
    done < <(find "$1/drive_c/users" \( -path "*/Start Menu/Programs/$2/$3.lnk" -o -path "*/Desktop/$3.lnk" \) 2>/dev/null)
}

# Builds sharp-enough icons for the Game and Patcher launchers from the game's own icnbig.ico
# (48 px; the Game's own exe icon is only 32 px, and the Patcher's launcher app is left with
# CrossOver's generic icon). Fills CrossOver's icon cache with larger sizes and replaces the
# icon of the two launcher apps in ~/Applications/CrossOver. Silently does nothing if the game
# has no icnbig.ico. Re-run `launchers` if CrossOver ever rebuilds those apps.
fix_launcher_icons() {   # $1 = bottle dir, $2 = game folder name, $3 = game dir, $4 = bottle name
    local ico="$3/icnbig.ico"
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
    for name in "UaRO Game" "UaRO Patcher"; do
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
    for name in "UaRO Game" "UaRO Patcher"; do
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
        rename_patcher_shortcuts "$bdir" "$gamename" "UaRO Patcher" "$gamename"
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
    rename_patcher_shortcuts "$bdir" "$gamename" "$gamename" "UaRO Patcher"
    "$cxmenu" --sync --bottle "$bottle" --mode install >/dev/null 2>&1
    fix_launcher_icons "$bdir" "$gamename" "$GAME_DIR" "$bottle"

    # (${arr[@]+...} keeps an empty list from tripping `set -u` on the macOS bash 3.2)
    [ "$RENAMED" -gt 0 ] && echo "Renamed the patcher's shortcut to: UaRO Patcher"
    for name in ${made[@]+"${made[@]}"}; do echo "Added launcher: $name"; done
    for name in ${skipped[@]+"${skipped[@]}"}; do echo "Skipped: $name (its program is not in the game folder yet)"; done
    echo "They appear in CrossOver under the bottle $bottle (reopen CrossOver if it is open)."
    echo "Remove them with: bash install.sh launchers remove"
}

# The in-game /hoai and /merai switches are saved in savedata/OptionInfo.lua as
# CmdOnOffList["/hoai"] and ["/merai"] (1 = use the custom AI). Sets both to $2 in game folder $1.
# Returns 1 if the file does not exist yet (the game has never been started).
azzy_set_ai_switches() {
    local file="$1/savedata/OptionInfo.lua"
    [ -f "$file" ] || return 1
    [ -e "$file.before-azzyai.backup" ] || cp -p "$file" "$file.before-azzyai.backup"
    python3 - "$file" "$2" <<'PYEOF'
import re, sys
path, val = sys.argv[1], int(sys.argv[2])
s = open(path, newline="").read()
for key in ("/hoai", "/merai"):
    s, n = re.subn(r'(CmdOnOffList\["%s"\]\s*=\s*)\d+' % re.escape(key), r'\g<1>%d' % val, s)
    if n != 1:
        sys.exit("expected exactly one %s line, found %d" % (key, n))
open(path, "w", newline="").write(s)
PYEOF
}

# OPTIONAL: install the latest AzzyAI (a homunculus / mercenary AI) from its GitHub release.
# This build is made for uaRO pre-renewal only. The game's AI folder is replaced; the old one
# is kept as AI-BEFORE-AZZYAI. Third-party software, downloaded when you run this.
AZZY_REPO="RagnaJDC/AzzyAI-Pre-Renewal"
AZZY_MARKER=".azzyai-release"

do_azzyai() {
    require_game
    local action="${ARG1:-install}"
    case "$action" in install|undo|status) ;; *) die "Usage: bash install.sh azzyai [undo|status]" ;; esac
    pick_game
    local game="$GAME_DIR" gamename; gamename=$(basename "$game")
    local ai="$game/AI" marker="$game/AI/$AZZY_MARKER"

    if [ "$action" = "status" ]; then
        if [ -f "$marker" ]; then echo "AzzyAI installed: $(cut -f1 "$marker") ($(cut -f2 "$marker"))"
        else echo "AzzyAI is not installed (the game uses its original AI folder)."; fi
        ls -d "$game"/AI-BEFORE-AZZYAI* 2>/dev/null | sed 's/^/Backup of the original: /'
        return 0
    fi

    game_running "$gamename" && die "The game is running. Quit it completely first."

    if [ "$action" = "undo" ]; then
        [ -f "$marker" ] || die "AzzyAI does not look installed (no marker in $ai)."
        local backup; backup=$(ls -dt "$game"/AI-BEFORE-AZZYAI* 2>/dev/null | head -1)
        [ -n "$backup" ] || die "No backup of the original AI folder was found, so nothing to restore."
        local removed="$game/AI-AZZYAI-REMOVED"; [ -e "$removed" ] && removed="$removed-$(date +%s)"
        mv "$ai" "$removed" && mv "$backup" "$ai" || die "Could not restore the original AI folder."
        echo "Restored the original AI folder."
        azzy_set_ai_switches "$game" 0 && echo "/hoai and /merai are switched back off in the game's settings."
        echo "Your AzzyAI files (and any settings you changed) are kept in: $removed"
        echo "Delete that folder when you no longer need it."
        return 0
    fi

    command -v curl >/dev/null && command -v python3 >/dev/null || die "curl and python3 are needed."
    local name url published
    if [ -n "${AZZYAI_ZIP:-}" ]; then   # offline/testing: use a local zip instead of GitHub
        name=$(basename "$AZZYAI_ZIP"); url=""; published="local"
    else
        local info
        info=$(curl -fsSL -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/$AZZY_REPO/releases" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    for a in r.get("assets", []):
        if a["name"].lower().endswith(".zip"):
            print("\t".join([a["name"], a["browser_download_url"], r.get("published_at", "")]))
            sys.exit(0)
sys.exit(1)') || die "Could not find the latest AzzyAI release on GitHub (are you online?)."
        IFS=$'\t' read -r name url published <<EOF2
$info
EOF2
    fi

    if [ -f "$marker" ] && [ "$(cut -f1 "$marker")" = "$name" ] && [ "$(cut -f2 "$marker")" = "$published" ]; then
        echo "AzzyAI is already up to date ($name)."
        azzy_set_ai_switches "$game" 1 && echo "/hoai and /merai are switched on in the game's settings."
        return 0
    fi

    echo "Latest AzzyAI: $name (github.com/$AZZY_REPO)"
    echo "This build is for uaRO pre-renewal only, and it replaces the game's AI folder"
    echo "(the original is kept). Check your server's rules about AI scripts."
    ask "Install it?" || { echo "Skipped. Install it later with: bash install.sh azzyai"; return 0; }

    local tmp; tmp=$(mktemp -d) || die "Could not create a temporary folder."
    trap 'rm -rf "$tmp"' RETURN
    local zip="$tmp/azzyai.zip"
    if [ -n "${AZZYAI_ZIP:-}" ]; then cp "$AZZYAI_ZIP" "$zip" || die "Could not read $AZZYAI_ZIP."
    else
        echo "Downloading (about 40 MB)..."
        curl -fL --progress-bar -o "$zip" "$url" || die "The download failed."
    fi
    unzip -tq "$zip" >/dev/null 2>&1 || die "The download is not a valid zip file."
    ditto -xk "$zip" "$tmp/x" || die "Could not unpack the download."
    [ -f "$tmp/x/AI/AI.lua" ] && [ -d "$tmp/x/AI/USER_AI" ] || die "The download does not have the expected AI folder."

    if [ -e "$ai" ]; then
        if [ -f "$marker" ]; then       # an older AzzyAI: keep it aside, the original backup stays
            local old="$game/AI-AZZYAI-OLD"; [ -e "$old" ] && rm -rf "$old"
            mv "$ai" "$old" || die "Could not move the old AzzyAI aside."
            echo "Your previous AzzyAI folder (and settings) is kept in: $old"
        else
            local backup="$game/AI-BEFORE-AZZYAI"; [ -e "$backup" ] && backup="$backup-$(date +%s)"
            mv "$ai" "$backup" || die "Could not back up the game's AI folder."
            echo "Backup of the original AI folder: $backup"
        fi
    fi
    mv "$tmp/x/AI" "$ai" || die "Could not put the AzzyAI folder in place."
    printf '%s\t%s\n' "$name" "$published" > "$marker"
    echo "AzzyAI installed ($name)."
    if azzy_set_ai_switches "$game" 1; then
        echo "/hoai and /merai are switched on in the game's settings, so you do not need to type them."
        echo "Start the game and summon your homunculus or mercenary (log in again if one is out)."
    else
        echo "Start the game once, then run this again to switch AzzyAI on (or type /hoai and /merai in the game)."
    fi
    echo "To change its settings, run AI\\USER_AI\\AzzyAiConfigPreRe.exe from the game folder."
    echo "Remove it with: bash install.sh azzyai undo"
    echo "For a CrossOver icon for its settings tool, run: bash install.sh launchers"
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

do_setup() {
    require_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    [ -d "$bottles" ] || die "No CrossOver bottles found at $bottles"
    command -v python3 >/dev/null || die "python3 is needed. Run: xcode-select --install"

    local found=() f
    while IFS= read -r f; do found+=("$f"); done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "setup.exe" -not -ipath "*/windows/*" \
            -not -ipath "*/Program Files*/Common Files/*" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "Could not find the game's setup.exe in any bottle."

    local target
    pick_one "Which one is your Ragnarok Online setup.exe?" "${found[@]}"
    target="$PICKED"

    echo "Patching: $target"
    python3 patch_opensetup_rosetta.py "$target" || die "Patch failed. See DETAILS.md (OpenSetup)."
    echo "Done. Start the game; setup will open. Pick a resolution and click OK."
}

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
    *)         echo "Usage: bash install.sh [install|check|uninstall|setup|extras|window|keys|azzyai|launchers] [-y]"; exit 1 ;;
esac
