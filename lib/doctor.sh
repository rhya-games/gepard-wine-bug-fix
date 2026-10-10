# `doctor`: one summary of this Mac's setup, to paste when asking for help. It changes nothing
# (it only runs the bug probe in the game's bottle). Home folders and user names are removed from
# the output, and the report is copied to the clipboard.

yesno() { [ "$1" = 0 ] && echo yes || echo no; }

doctor_report() {
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" f

    echo "ro-crossover-tools report"
    echo "========================="
    local tools_id; tools_id=$(cat "$ROOT/install.sh" "$ROOT"/lib/*.sh 2>/dev/null | shasum -a 256 | cut -c1-8)
    echo "tools            : $tools_id$([ -d "$ROOT/.git" ] && echo " (git $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null))")"
    echo "profile          : $PROFILE_NAME"

    echo
    echo "System"
    echo "  macOS          : $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
    echo "  chip           : $(uname -m)"
    echo "  Rosetta        : $(arch -x86_64 /usr/bin/true >/dev/null 2>&1 && echo installed || echo "not installed")"

    echo
    echo "CrossOver"
    echo "  version        : $(defaults read "$CX_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null)"
    local where="/Applications"; [[ "$CX_APP" == "$HOME"/* ]] && where="~/Applications"
    echo "  location       : $where"
    echo "  app open       : $(crossover_running && echo yes || echo no)"
    local stale; stale=$(stale_pids | wc -l | tr -d ' ')
    echo "  leftover procs : $stale"

    echo
    echo "Wine fix"
    echo "  ready-made DLL for this version : $(prebuilt_available && echo yes || echo no)"
    echo "  installed DLL is the ready-made : $(cmp -s "$DLL_SRC" "$DLL" 2>/dev/null && echo yes || echo no)"
    echo "  original DLL backup present     : $([ -f "$BACKUP" ] && echo yes || echo no)"

    echo
    echo "Game"
    GAME_DIR=""
    while IFS= read -r f; do GAME_DIR=$(dirname "$f"); break; done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "$GAME_EXE" -not -ipath "*/windows/*" 2>/dev/null)
    if [ -z "$GAME_DIR" ]; then
        echo "  $GAME_EXE found : no (no game in any bottle)"
        return 0
    fi
    local rel="${GAME_DIR#"$bottles"/}" bottle gamename
    bottle="${rel%%/*}"; gamename=$(basename "$GAME_DIR"); BOTTLE_NAME="$bottle"
    echo "  bottle         : $bottle"
    echo "  game folder    : $gamename"
    echo "  game running   : $(game_running "$gamename" && echo yes || echo no)"

    echo
    echo "Bug probe (runs a small test program in the bottle)"
    if run_probe "$bottle"; then
        echo "  bug present    : $PROBE_RESULT"
    else
        echo "  bug present    : could not run the probe"
    fi
    local gfx; gfx=$(check_graphics "$bottles/$bottle" 2>&1 | grep "^NOTE" | head -1)
    echo "  graphics notes : ${gfx:-none}"

    echo
    echo "Game settings"
    local opt="$GAME_DIR/savedata/OptionInfo.lua"
    if [ -f "$opt" ]; then
        echo "  windowed       : $([ "$(lua_get "$opt" ISFULLSCREENMODE)" = 0 ] && echo yes || echo no)"
        echo "  window size    : $(lua_get "$opt" WIDTH) x $(lua_get "$opt" HEIGHT) at $(lua_get "$opt" Window_XPos),$(lua_get "$opt" Window_YPos)"
        local hoai merai
        hoai=$(sed -n 's/^CmdOnOffList\["\/hoai"\] *= *\([0-9]*\).*/\1/p' "$opt" | head -1)
        merai=$(sed -n 's/^CmdOnOffList\["\/merai"\] *= *\([0-9]*\).*/\1/p' "$opt" | head -1)
        echo "  /hoai /merai   : ${hoai:-?} ${merai:-?}"
    else
        echo "  OptionInfo.lua : not found (the game has not been started yet)"
    fi
    if [ -n "$AZZY_REPO" ]; then
        if [ -f "$GAME_DIR/AI/$AZZY_MARKER" ]; then echo "  AzzyAI         : installed ($(cut -f1 "$GAME_DIR/AI/$AZZY_MARKER"))"
        else echo "  AzzyAI         : not installed"; fi
    fi
    if [ -n "$SETUP_PATCH" ]; then
        local sf; sf=$(find "$GAME_DIR" -maxdepth 1 -iname "$SETUP_EXE" 2>/dev/null | head -1)
        if [ -z "$sf" ] || ! command -v python3 >/dev/null; then echo "  $SETUP_EXE patch : n/a"
        else
            python3 "$PROFILE_DIR/$SETUP_PATCH" --check "$sf" >/dev/null 2>&1
            case $? in 0) echo "  $SETUP_EXE patch : needed (not applied)" ;; 1) echo "  $SETUP_EXE patch : applied" ;; *) echo "  $SETUP_EXE patch : unknown build" ;; esac
        fi
    fi

    echo
    echo "Mac keyboard settings (Wine Mac Driver)"
    local pair name v
    for pair in $KEYS_ON; do
        name="${pair%%=*}"; v=$(keys_value "$name")
        printf "  %-30s %s\n" "$name" "${v:-default}"
    done

    echo
    echo "CrossOver launchers"
    local menu; menu=$(find "$bottles/$bottle/drive_c/users" -path "*/Start Menu/Programs/$gamename" -type d 2>/dev/null | head -1)
    if [ -n "$menu" ]; then ls "$menu" 2>/dev/null | sed 's/\.lnk$//; s/^/  /'; else echo "  none"; fi
}

do_doctor() {
    local report
    report=$(doctor_report 2>&1 | sed -e "s#$HOME#~#g" -e 's#/Users/[^/ ]*#/Users/<user>#g')
    echo "$report"
    if command -v pbcopy >/dev/null && printf '%s\n' "$report" | pbcopy 2>/dev/null; then
        echo
        echo "(This report is now on your clipboard. Paste it where you ask for help.)"
    fi
}
