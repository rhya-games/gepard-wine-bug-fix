#!/bin/bash
# Installs / removes the Wine fix for "Gepard::T Code: 3::110::12" on CrossOver.
#
#   bash install.sh              install the fix
#   bash install.sh check        is the bug present / is the fix working?
#   bash install.sh uninstall    put the original file back
#   bash install.sh setup        new installs only: patch the game's setup.exe
#
# Add -y to answer "yes" to the questions (quit CrossOver, stop leftovers).
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
CMD=""
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        *) [ -z "$CMD" ] && CMD="$arg" ;;
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

# Make sure CrossOver is closed and nothing is left running, asking before acting.
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

    local pids
    pids=$(stale_pids | tr '\n' ' ')
    if [ -n "${pids// /}" ]; then
        echo "Leftover Windows processes from CrossOver are still running (PIDs: $pids)."
        echo "These can make CrossOver hang the next time it opens."
        if ask "Stop them?"; then
            # shellcheck disable=SC2086
            kill $pids 2>/dev/null
            sleep 2
            pids=$(stale_pids | tr '\n' ' ')
            # shellcheck disable=SC2086
            [ -n "${pids// /}" ] && kill -9 $pids 2>/dev/null && sleep 1
            echo "Stopped."
        else
            echo "Leaving them running. If CrossOver hangs later, restart your Mac."
        fi
    fi
}

check_writable() {
    [ -w "$DLL_DIR" ] && return 0
    die "No permission to change files inside CrossOver.app.
Fix: open System Settings > Privacy & Security > App Management, turn on Terminal,
then quit and reopen Terminal and run this again. (If CrossOver was installed by
another user, run the command with sudo instead.)"
}

do_install() {
    [ "$VERSION" = "$SUPPORTED" ] || die "This fix is built for CrossOver $SUPPORTED only; you have ${VERSION:-unknown}.
Rebuild it for your version (see DETAILS.md), or check whether you still need it."
    [ -f "$DLL_SRC" ] || die "$DLL_SRC is missing. Run this from the downloaded folder."
    [ "$(shasum -a 256 "$DLL_SRC" | cut -d' ' -f1)" = "$DLL_SHA256" ] \
        || die "$DLL_SRC does not match the expected checksum. Re-download it."
    if cmp -s "$DLL_SRC" "$DLL"; then
        echo "Already installed. Nothing to do."
        return 0
    fi

    check_writable
    ensure_crossover_closed

    [ -e "$BACKUP" ] || cp -p "$DLL" "$BACKUP" || die "Could not back up the original file (permission?)."
    cp "$DLL_SRC" "$DLL" || die "Could not write to CrossOver.app. See the App Management note above."
    cmp -s "$DLL_SRC" "$DLL" || die "Copy did not verify."

    echo "Installed the fix for CrossOver $VERSION."
    echo "Backup of the original: $BACKUP"
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

do_check() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local probe="rawinput_overflow_probe.exe"
    [ -f "$probe" ] || die "$probe is missing. Run this from the downloaded folder."
    [ -d "$bottles" ] || die "No CrossOver bottles found. Create one in CrossOver first."

    local names=() d
    for d in "$bottles"/*/; do [ -d "$d" ] && names+=("$(basename "$d")"); done
    [ ${#names[@]} -gt 0 ] || die "No CrossOver bottles found. Create one in CrossOver first."

    local bottle="${names[0]}"
    if [ ${#names[@]} -gt 1 ]; then
        echo "Which bottle should I test with?"
        local i=1
        for d in "${names[@]}"; do echo "  $i) $d"; i=$((i + 1)); done
        printf "Number: "
        read -r n
        case "$n" in ''|*[!0-9]*) die "Not a number." ;; esac
        [ "$n" -ge 1 ] && [ "$n" -le ${#names[@]} ] || die "Not in the list."
        bottle="${names[$((n - 1))]}"
    fi

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
            else
                echo "RESULT: the bug is present. Run:  bash install.sh"
            fi ;;
        *)
            echo "RESULT: the test did not finish. Output was:"
            echo "$out" | tail -5
            exit 1 ;;
    esac
}

do_setup() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    [ -d "$bottles" ] || die "No CrossOver bottles found at $bottles"
    command -v python3 >/dev/null || die "python3 is needed. Run: xcode-select --install"

    local found=() f
    while IFS= read -r f; do found+=("$f"); done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "setup.exe" -not -ipath "*/windows/*" \
            -not -ipath "*/Program Files*/Common Files/*" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "Could not find the game's setup.exe in any bottle."

    local target
    if [ ${#found[@]} -eq 1 ]; then
        target="${found[0]}"
    else
        echo "Which one is your Ragnarok Online setup.exe?"
        local i=1
        for f in "${found[@]}"; do echo "  $i) $f"; i=$((i + 1)); done
        printf "Number: "
        read -r n
        case "$n" in ''|*[!0-9]*) die "Not a number." ;; esac
        [ "$n" -ge 1 ] && [ "$n" -le ${#found[@]} ] || die "Not in the list."
        target="${found[$((n - 1))]}"
    fi

    echo "Patching: $target"
    python3 patch_opensetup_rosetta.py "$target" || die "Patch failed. See DETAILS.md (OpenSetup)."
    echo "Done. Start the game; setup will open. Pick a resolution and click OK."
}

case "${CMD:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    check)     do_check ;;
    setup)     do_setup ;;
    *)         echo "Usage: bash install.sh [install|check|uninstall|setup] [-y]"; exit 1 ;;
esac
