# Ragnarok Online tools for CrossOver (macOS)

Tools for playing Ragnarok Online on a Mac with [CrossOver](https://www.codeweavers.com/crossover):

- **The Gepard fix.** Cures `Gepard::T Code: 3::110::12`, which appears right after a map loads:

      GS 3.0 :: <build>
      Gepard::T Code: 3::110::12

  It is a bug in Wine (the part of CrossOver that runs Windows programs), not a Gepard bug and
  not a broken install. The fix is on the Wine side and does not touch the anti-cheat. It works for
  any Ragnarok Online client that uses Gepard Shield 3.0. Ready-made for CrossOver 26.3.0; on
  another version the installer tells you whether you need it and how to build one
  ([details](docs/fix.md#other-crossover-versions-or-other-wine-runtimes)).
- **Play.** Starts the game after clearing leftover Wine processes that can freeze CrossOver.
- **Backup.** Copies your save data (character settings, hotkeys) to a safe place, and does it
  automatically before the extras that change it.
- **Optional extras.** Window size that fits your screen, Mac keyboard settings, launcher icons in
  CrossOver, and, for the uaRO server, AzzyAI and a fix for the first-run setup window.

## How to install

**First, install the game in CrossOver.** Do everything below only after that. The scripts
stop with a message if they cannot find the game.

### Easiest: double-click

1. [Download the ZIP](https://github.com/rhya-games/ro-crossover-tools/archive/refs/heads/main.zip)
   and unzip it (Safari does this for you).
2. Double-click `Start Here.command`. ([macOS blocked it?](docs/troubleshooting.md#macos-says-it-cannot-verify-start-herecommand))
3. Type `1` to install the fix, or `2` to install it **with** the
   [optional extras](#optional-extras-not-needed-for-the-fix), then press Return. If it
   offers to fix the game's setup window, type `y`. It ends by checking that the fix works.

### Or use Terminal

1. Download and unzip the ZIP above.
2. Open Terminal (press `Cmd + Space`, type `Terminal`, press Return), then paste this and
   press Return:

       cd ~/Downloads/ro-crossover-tools-main

   That assumes the folder is in Downloads. If it is somewhere else, type `cd ` (with a
   space), drag the folder from Finder into the Terminal window, and press Return.
3. Run the installer, either by itself or **with** the
   [optional extras](#optional-extras-not-needed-for-the-fix). Pick one:

       bash install.sh

       bash install.sh extras

   If CrossOver is open, it asks to quit it; type `y`. On a new uaRO install it also offers to
   fix the game's setup window ([why](docs/uaro.md#new-installs-the-opensetup-patch)); type
   `y`. It ends by checking that the fix works; you want "the fix is installed and
   working". If it says STOP, read the message.

### Then play

Open CrossOver, launch the game, log in and load a map. The error should be gone.

To start the game without worrying about leftover processes from an earlier crash, use menu
item 3 in `Start Here.command`, or:

    bash install.sh play

## How to uninstall

Open Terminal, go to the folder as in "Or use Terminal", and run:

    bash install.sh uninstall

This puts the original file back (it asks before quitting CrossOver if it is open).

## Optional extras (not needed for the fix)

You can skip these. To install the fix and add them all at once, run `bash install.sh extras`
(double-click menu item 2). Running it again later adds them to an existing install. Remove
them with `bash install.sh extras undo`; the fix stays installed. Each one separately is
under menu item 4.

| extra | command | for | details |
|---|---|---|---|
| Fit the game window to your screen (quit the game first) | `bash install.sh window` (`window undo` to revert) | any game | [how it works](docs/extras.md#optional-fitting-the-game-window-how-it-works) |
| Mac keyboard settings: Option works as Alt, Command stays Command | `bash install.sh keys on` (`keys off` to revert) | any game | [how it works](docs/extras.md#optional-mac-keyboard-settings-how-it-works) |
| CrossOver launcher icons for the game, the patcher, setup and AzzyAI settings | `bash install.sh launchers` (`launchers remove` to revert) | any game | [how it works](docs/extras.md#optional-crossover-launcher-icons-how-it-works) |
| AzzyAI, the latest build (third-party; asks before downloading; keeps your original AI folder) | `bash install.sh azzyai` (`azzyai undo` to revert) | uaRO only | [how it works](docs/uaro.md#optional-azzyai-how-it-works) |

**Known limitation (not fixed):** Cmd+Tab does not work with full screen: tabbing back gives a
black screen. Use windowed mode. ([Details](docs/extras.md#known-failure-cmdtab-in-full-screen))

"For uaRO only" extras come from the uaRO profile. To use the tools with another server, see
[docs/uaro.md](docs/uaro.md#using-the-tools-with-another-server).

## If something goes wrong

- **"permission denied" when running `install.sh`:** use `bash install.sh` (with
  `bash` at the front), exactly as written above.
- **"No permission to change files inside CrossOver.app":** open System Settings,
  Privacy & Security, App Management, turn on Terminal, then quit and reopen Terminal.
- **"The program setup.exe has encountered a serious problem" (uaRO):** run
  `bash install.sh setup`. It patches the `setup.exe` inside your bottle (the installer offers
  this too); patching a different copy does nothing.
- **CrossOver freezes or will not open after you force-quit it:** run `bash install.sh play`, or
  `bash install.sh`. Both stop leftover processes automatically.
- **The game still shows the 3::110 error:** run `bash install.sh check`. If it says
  the fix is working, make sure you started the game after installing, with CrossOver
  closed and reopened.

- **You cannot find the game folder in Finder:** it is inside the hidden `~/Library` folder. Run
  `bash install.sh open` (menu item 5) to open it. Add `savedata` or `bottle` to open those instead.
- **You want a safety copy of your settings:** run `bash install.sh backup` (menu item 6). It copies
  your save data to `~/Documents/RO Backups`; `backup restore` puts the newest one back.
- **You need help:** run `bash install.sh doctor` (menu item 7). It prints and copies a short summary
  of your setup, with your user name removed, to paste where you ask.

More: [docs/troubleshooting.md](docs/troubleshooting.md).

## After a CrossOver update

An update removes the fix. Run `bash install.sh` again. If it says there is no ready-made
fix for your new version, it first tests whether that version still has the bug. If it does,
build one with `bash fix/build-dll.sh <your CrossOver version>` (needs `brew install mingw-w64 bison`
once) and run `bash install.sh` again
([details](docs/fix.md#other-crossover-versions-or-other-wine-runtimes)).

## More

- [docs/fix.md](docs/fix.md): the technical cause, affected versions, checks, building for other versions
- [docs/extras.md](docs/extras.md): how the window, keyboard and launcher extras work
- [docs/uaro.md](docs/uaro.md): uaRO-specific extras and using another server
- [docs/files.md](docs/files.md): what each file is, checksums
- [NOTICE](NOTICE): license and build information for the shipped Wine file
