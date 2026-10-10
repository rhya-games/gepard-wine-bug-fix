# True if this checkout has a ready-made fix for the installed CrossOver version.
prebuilt_available() { [ -n "$VERSION" ] && [ -n "$DLL_SHA256" ] && [ -f "$DLL_SRC" ]; }

do_install() {
    require_game
    if ! prebuilt_available; then
        echo "There is no ready-made fix for CrossOver ${VERSION:-(unknown version)} in this download yet."
        echo "Checking whether your version has the bug at all..."
        echo
        do_check
        return
    fi
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

# Looks for graphics settings known to cause the same error: the protection hooks Direct3D 9,
# and DXVK (or similar layers) are reported to trigger "3::110::12" even with the Wine fix.
# Prints a note and returns 1 if it finds one in the bottle's settings or registry.
check_graphics() {   # $1 = bottle dir
    local hits="" conf="$1/cxbottle.conf" reg="$1/user.reg" line
    if [ -f "$conf" ]; then
        line=$(awk '/^\[EnvironmentVariables\]/ {f=1; next} /^\[/ {f=0} f' "$conf" \
               | grep -iE 'dxvk|d3dmetal|dxmt|CX_GRAPHICS_BACKEND' | head -1)
        [ -n "$line" ] && hits="the bottle setting $line"
    fi
    if [ -z "$hits" ] && [ -f "$reg" ]; then
        line=$(awk '/^\[Software\\\\Wine\\\\DllOverrides\]/ {f=1; next} /^\[/ {f=0} f && tolower($0) ~ /^"d3d9"=.*native/' "$reg" | head -1)
        [ -n "$line" ] && hits="a native Direct3D 9 override ($line)"
    fi
    [ -n "$hits" ] || return 0
    echo
    echo "NOTE: this bottle uses $hits."
    echo "The game's protection hooks Direct3D 9, and DXVK or similar graphics layers are reported to"
    echo "cause this same error even with the fix. If you still see it, switch the bottle back to"
    echo "its default graphics setting."
    return 1
}

# Runs the bug probe inside bottle $1. Sets PROBE_OUT (its output) and PROBE_RESULT
# (yes = bug present, no = bug not present, unknown). Returns 1 if the probe could not be copied in.
run_probe() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local probe="$FIX_DIR/rawinput_overflow_probe.exe" dest="$bottles/$1/drive_c/rawinput_overflow_probe.exe"
    PROBE_OUT=""; PROBE_RESULT="unknown"
    [ -f "$probe" ] && cp "$probe" "$dest" 2>/dev/null || return 1
    PROBE_OUT=$("$CX_APP/Contents/SharedSupport/CrossOver/bin/wine" --bottle "$1" --no-gui \
        --debugmsg -all --cx-app 'C:\rawinput_overflow_probe.exe' 2>&1)
    rm -f "$dest"
    case "$PROBE_OUT" in *AFFECTED=no*) PROBE_RESULT=no ;; *AFFECTED=yes*) PROBE_RESULT=yes ;; esac
    return 0
}

do_check() {
    require_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    local probe="$FIX_DIR/rawinput_overflow_probe.exe"
    [ -f "$probe" ] || die "$probe is missing. Run this from the downloaded folder."
    [ -d "$bottles" ] || die "No CrossOver bottles found. Create one in CrossOver first."

    pick_bottle
    local bottle="$BOTTLE_NAME"

    local installed="no"
    cmp -s "$DLL_SRC" "$DLL" 2>/dev/null && installed="yes"

    echo "CrossOver version : ${VERSION:-unknown}"
    echo "Fix installed     : $installed"
    echo "Testing in bottle : $bottle (takes a few seconds)"

    local out bdir_check="$bottles/$bottle"
    run_probe "$bottle" || die "Could not copy the test program into the bottle."
    out="$PROBE_OUT"

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
            elif prebuilt_available; then
                echo "RESULT: the bug is present. Run:  bash install.sh"
            else
                echo "RESULT: the bug is present, but there is no ready-made fix for CrossOver"
                echo "$VERSION yet. Build one with: bash fix/build-dll.sh $VERSION (see docs/fix.md)."
            fi ;;
        *)
            echo "RESULT: the test did not finish. Output was:"
            echo "$out" | tail -5
            exit 1 ;;
    esac
    check_graphics "$bdir_check" || true
}
