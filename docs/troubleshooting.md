# Troubleshooting and notes

Back to the [README](../README.md).

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

