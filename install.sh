#!/bin/bash
# Installs / removes the Wine fix for "Gepard::T Code: 3::110::12" on CrossOver.
#
#   bash install.sh              install the fix
#   bash install.sh uninstall    put the original file back
#   bash install.sh setup        new installs only: patch the game's setup.exe
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

die() { echo; echo "STOP: $*"; exit 1; }

[ -n "$CX_APP" ] && [ -d "$CX_APP" ] || die "CrossOver.app not found in /Applications or ~/Applications."

DLL_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
DLL="$DLL_DIR/wow64win.dll"
VERSION=$(defaults read "$CX_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
BACKUP="$DLL.orig-$VERSION"

[ -f "$DLL" ] || die "Could not find $DLL"

crossover_running() { pgrep -f "CrossOver.app/Contents/MacOS" >/dev/null 2>&1; }

do_install() {
    [ "$VERSION" = "$SUPPORTED" ] || die "This fix is built for CrossOver $SUPPORTED only; you have ${VERSION:-unknown}.
Rebuild it for your version (see DETAILS.md), or check whether you still need it."
    [ -f "$DLL_SRC" ] || die "$DLL_SRC is missing. Run this from the downloaded folder."
    [ "$(shasum -a 256 "$DLL_SRC" | cut -d' ' -f1)" = "$DLL_SHA256" ] \
        || die "$DLL_SRC does not match the expected checksum. Re-download it."
    crossover_running && die "CrossOver is open. Quit it (CrossOver menu > Quit) and run this again."

    if cmp -s "$DLL_SRC" "$DLL"; then
        echo "Already installed. Nothing to do."
        return 0
    fi

    [ -e "$BACKUP" ] || cp -p "$DLL" "$BACKUP" || die "Could not back up the original file (permission?)."
    cp "$DLL_SRC" "$DLL" || die "Could not write to CrossOver.app (permission?)."
    cmp -s "$DLL_SRC" "$DLL" || die "Copy did not verify."

    echo "Installed the fix for CrossOver $VERSION."
    echo "Backup of the original: $BACKUP"
    echo "Now open CrossOver and start the game."
    echo "A CrossOver update will remove the fix; run this script again afterwards."
}

do_uninstall() {
    crossover_running && die "CrossOver is open. Quit it (CrossOver menu > Quit) and run this again."
    [ -e "$BACKUP" ] || die "No backup for CrossOver $VERSION ($BACKUP), so nothing to restore.
If CrossOver was updated since you installed the fix, the fix is already gone."
    cp -p "$BACKUP" "$DLL" || die "Could not restore the original file."
    echo "Original file restored. The fix is removed."
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

case "${1:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    setup)     do_setup ;;
    *)         echo "Usage: $0 [install|uninstall|setup]"; exit 1 ;;
esac
