# Features that exist only for some games (set up in the profile): the setup.exe fix and AzzyAI.
AZZY_MARKER=".azzyai-release"

# If the game's setup.exe is the known build that crashes on Macs, offer to fix it.
maybe_patch_setup() {
    [ -n "$SETUP_PATCH" ] && command -v python3 >/dev/null || return 0
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles" f
    local todo=()
    while IFS= read -r f; do
        python3 "$PROFILE_DIR/$SETUP_PATCH" --check "$f" >/dev/null 2>&1 && todo+=("$f")
    done < <(find "$bottles" -ipath "*/drive_c/*" -iname "$SETUP_EXE" -not -ipath "*/windows/*" \
                 -not -ipath "*/Program Files*/Common Files/*" 2>/dev/null)
    [ ${#todo[@]} -gt 0 ] || return 0

    echo
    echo "The game's setup window (setup.exe) crashes on Macs unless it is fixed:"
    for f in "${todo[@]}"; do
        echo "  $f"
        if ask "Fix it now?"; then
            python3 "$PROFILE_DIR/$SETUP_PATCH" "$f" >/dev/null && echo "  Fixed (backup kept next to it)." \
                || echo "  Could not fix it. Run: bash install.sh setup"
        else
            echo "  Skipped. You can fix it later with: bash install.sh setup"
        fi
    done
}

do_setup() {
    [ -n "$SETUP_PATCH" ] || die "The $PROFILE_NAME profile has no setup.exe fix."
    require_game
    local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
    [ -d "$bottles" ] || die "No CrossOver bottles found at $bottles"
    command -v python3 >/dev/null || die "python3 is needed. Run: xcode-select --install"

    local found=() f
    while IFS= read -r f; do found+=("$f"); done < <(
        find "$bottles" -ipath "*/drive_c/*" -iname "$SETUP_EXE" -not -ipath "*/windows/*" \
            -not -ipath "*/Program Files*/Common Files/*" 2>/dev/null)
    [ ${#found[@]} -gt 0 ] || die "Could not find the game's setup.exe in any bottle."

    local target
    pick_one "Which one is your Ragnarok Online setup.exe?" "${found[@]}"
    target="$PICKED"

    echo "Patching: $target"
    python3 "$PROFILE_DIR/$SETUP_PATCH" "$target" || die "Patch failed. See docs/uaro.md."
    echo "Done. Start the game; setup will open. Pick a resolution and click OK."
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

do_azzyai() {
    [ -n "$AZZY_REPO" ] || die "The $PROFILE_NAME profile has no AzzyAI build."
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

    auto_backup "$game"
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
