# Troubleshooting and notes

Back to the [README](../README.md).

## Asking for help: the doctor report

`bash install.sh doctor` (menu item 7 in `Start Here.command`) prints one summary of your setup and
copies it to the clipboard, so you can paste it where you ask for help. It changes nothing; it only
runs the bug probe, a small test program, in the game's bottle. It reports:

- the tools' version, macOS, chip and whether Rosetta is installed;
- the CrossOver version, whether it is open, and any leftover Wine processes;
- whether a ready-made fix exists for your CrossOver, whether it is installed, and whether a backup of the original exists;
- the game's bottle and folder name, and whether the game is running;
- the bug probe result and any graphics-setting warning (the same ones `check` gives);
- window size and mode, the `/hoai` and `/merai` switches, whether AzzyAI is installed, whether the
  `setup.exe` patch is applied, the Mac keyboard values, and which CrossOver launchers exist.

Your home folder and user name are removed from the text (paths show as `~` or `/Users/<user>`).
Bottle and game folder names are included, so look over it before you post it publicly.

## macOS says it cannot verify Start Here.command

Files downloaded from the internet are marked "quarantined", and macOS blocks unsigned
scripts like this one the first time. To allow it:

1. Open System Settings, then Privacy & Security.
2. Scroll down to the message about `Start Here.command` and click **Open Anyway**.
3. Double-click the file again and confirm (it may ask for your password or Touch ID).

If it is still blocked, use the Terminal steps in the README: running `bash install.sh`
from Terminal is not affected. This path was not tested on a real quarantined download, and
the exact wording on screen varies by macOS version.

## The game-installed check

Every `install.sh` command except `uninstall` first looks for the game in the CrossOver
bottles: a folder under a bottle's `drive_c` (outside `windows`) that holds both a `.grf` data
archive and an `.exe`. It does not look for one exe name, because that differs per server. If
none is found it stops with "install the game first". To skip the check (for example to install only the
DLL fix before the game exists), add `--skip-game-check`, as in
`bash install.sh --skip-game-check`.

## Keyboard tips

These come from running the game on a Mac under Whisky; macOS behaves the same under CrossOver.

**F1-F12 do the wrong thing.** On Apple keyboards macOS makes the top row control brightness,
volume and Mission Control. Pick one fix:

- *Move the skill bar (works everywhere).* In the game's own shortcut settings, shift the whole
  hotkey bar down one row: F1-F12 to `1`-`9`, `1`-`9` to `Q`-`O`, `Q`-`O` to `A`-`L`. Nothing then
  depends on the F-row.
- *Make the F-row normal.* On an Apple keyboard: System Settings, Keyboard, Keyboard Shortcuts,
  Function Keys, "Use F1, F2, etc. keys as standard function keys". Third-party keyboards (Keychron
  and similar) decide this in their own firmware, so no macOS setting changes it; use the move above.

**Menu shortcuts do nothing with Command.** The game's menu shortcuts are built for Windows' Alt+letter.
Wine also adds a hidden Edit menu that catches Command+A and Command+Z before the game sees them.
`bash install.sh keys on` makes Option act as Alt, so use Option+letter. Command+C and Command+V keep
working for copy and paste. Do not turn off Wine's Edit menu (`EditMenu`): that fixes A and Z but
breaks Command+V.
