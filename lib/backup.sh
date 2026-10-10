# Save-data backups. The game's savedata/ folder (character settings, hotkeys, option files) cannot
# be downloaded again, so this copies it to ~/Documents/RO Backups/<game folder>/ with a timestamp.
# Keeps the newest 10 per game. Used by `backup`, and automatically before the window fit and the
# AzzyAI install (both edit files in savedata/).

BACKUP_KEEP=10

backup_root() { echo "${RO_BACKUP_DIR:-$HOME/Documents/RO Backups}"; }

# Makes a backup of $1 (game folder). Prints the new backup's path. Returns 1 if there is no savedata.
make_backup() {
    local game="$1" label="${2:-savedata}" root dest
    [ -d "$game/savedata" ] || return 1
    root="$(backup_root)/$(basename "$game")"
    dest="$root/$label-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$root" || return 1
    ditto "$game/savedata" "$dest" || return 1
    # keep only the newest BACKUP_KEEP (everything in this folder was made by this tool)
    local old
    old=$(ls -dt "$root"/* 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)))
    [ -n "$old" ] && echo "$old" | while IFS= read -r d; do rm -rf "$d"; done
    echo "$dest"
}

# Quiet one-line backup before a change that edits savedata/. Never stops the caller.
auto_backup() {
    local dest; dest=$(make_backup "$1" "before-change" 2>/dev/null) || return 0
    echo "Backed up your save data first: ${dest/#$HOME/~}"
    return 0
}

do_backup() {
    require_game
    pick_game
    local action="${ARG1:-create}" gamename root
    gamename=$(basename "$GAME_DIR"); root="$(backup_root)/$gamename"

    case "$action" in
        create)
            local dest; dest=$(make_backup "$GAME_DIR") \
                || die "There is no savedata folder yet. Start the game once, then try again."
            echo "Backed up to: ${dest/#$HOME/~}"
            echo "($(du -sh "$dest" | cut -f1) copied; the newest $BACKUP_KEEP are kept.)"
            ;;
        list)
            if ! ls -d "$root"/* >/dev/null 2>&1; then echo "No backups yet. Make one with: bash install.sh backup"; return 0; fi
            echo "Backups in ${root/#$HOME/~}:"
            ls -dt "$root"/* | while IFS= read -r d; do
                printf "  %s  (%s)\n" "$(basename "$d")" "$(du -sh "$d" | cut -f1)"
            done
            ;;
        restore)
            game_running "$gamename" && die "The game is running. Quit it completely first."
            local latest; latest=$(ls -dt "$root"/savedata-* 2>/dev/null | head -1)
            [ -n "$latest" ] || latest=$(ls -dt "$root"/before-change-* 2>/dev/null | head -1)
            [ -n "$latest" ] || die "There is no backup to restore. Make one with: bash install.sh backup"
            echo "Restore the newest backup ($(basename "$latest")) over your save data?"
            ask "Your current save data is backed up first. Restore it?" || { echo "Not restored."; return 0; }
            # stage the backup first: making the safety copy can prune the oldest backups
            local stage; stage=$(mktemp -d) || die "Could not create a temporary folder."
            ditto "$latest" "$stage/restore" || { rm -rf "$stage"; die "Could not read the backup."; }
            local safety; safety=$(make_backup "$GAME_DIR" "before-restore") || safety=""
            [ -n "$safety" ] && echo "Your current save data is kept in: ${safety/#$HOME/~}"
            ditto "$stage/restore" "$GAME_DIR/savedata" || { rm -rf "$stage"; die "Could not restore the backup."; }
            rm -rf "$stage"
            echo "Restored $(basename "$latest")."
            ;;
        *) die "Usage: bash install.sh backup [list|restore]" ;;
    esac
}
