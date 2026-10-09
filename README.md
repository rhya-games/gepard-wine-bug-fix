# Fix for "Gepard::T Code: 3::110::12" on macOS (CrossOver)

If Ragnarok Online shows this right after a map loads:

    GS 3.0 :: <build>
    Gepard::T Code: 3::110::12

it is a bug in Wine (the part of CrossOver that runs Windows programs). It is not
a Gepard bug and not a broken install, and this fix does not touch the anti-cheat.

**Ready-made for CrossOver 26.3.0.** On another version the installer tells you whether you need
the fix and how to build one ([details](DETAILS.md#other-crossover-versions-or-other-wine-runtimes)).

## How to install

**First, install the game in CrossOver.** Do everything below only after that. The scripts
stop with a message if they cannot find the game.

### Easiest: double-click

1. [Download the ZIP](https://github.com/rhya-games/gepard-wine-bug-fix/archive/refs/heads/main.zip)
   and unzip it (Safari does this for you).
2. Double-click `Start Here.command`. ([macOS blocked it?](DETAILS.md#macos-says-it-cannot-verify-start-herecommand))
3. Type `1` to install the fix, or `2` to install it **with** the
   [optional extras](#optional-extras-not-needed-for-the-fix), then press Return. If it
   offers to fix the game's setup window, type `y`. It ends by checking that the fix works.

### Or use Terminal

1. Download and unzip the ZIP above.
2. Open Terminal (press `Cmd + Space`, type `Terminal`, press Return), then paste this and
   press Return:

       cd ~/Downloads/gepard-wine-bug-fix-main

   That assumes the folder is in Downloads. If it is somewhere else, type `cd ` (with a
   space), drag the folder from Finder into the Terminal window, and press Return.
3. Run the installer, either by itself or **with** the
   [optional extras](#optional-extras-not-needed-for-the-fix) (window size, Mac keyboard
   settings, AzzyAI which asks first, and launcher icons). Pick one:

       bash install.sh

       bash install.sh extras

   If CrossOver is open, it asks to quit it; type `y`. On a new install it also offers to
   fix the game's setup window ([why](DETAILS.md#new-installs-the-opensetup-patch)); type
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
under menu item 5.

**Fit the game window to your screen.** Quit the game, then run:

    bash install.sh window

Undo with `bash install.sh window undo`. ([How it works](DETAILS.md#optional-fitting-the-game-window-how-it-works))

**Mac keyboard settings.** Option works as Alt, and the Command keys stay normal Mac
Command keys. Turn on with:

    bash install.sh keys on

Turn off with `bash install.sh keys off`, then restart CrossOver.
([How it works](DETAILS.md#optional-mac-keyboard-settings-how-it-works))

**AzzyAI.** Installs the latest [AzzyAI](https://github.com/RagnaJDC/AzzyAI-Pre-Renewal)
(a homunculus and mercenary AI). It is third-party, for uaRO pre-renewal only, and asks
before it downloads anything. Your original AI folder is kept, and it switches AzzyAI on
for you, so there is nothing to type in the game.

    bash install.sh azzyai

Remove it with `bash install.sh azzyai undo`.
([How it works](DETAILS.md#optional-azzyai-how-it-works))

**CrossOver launcher icons.** Adds icons in your CrossOver bottle for the game (not the
patcher), its setup program and, if AzzyAI is installed, its settings tool:

    bash install.sh launchers

Remove them with `bash install.sh launchers remove`.
([How it works](DETAILS.md#optional-crossover-launcher-icons-how-it-works))

**Known limitation (not fixed):** Cmd+Tab does not work with full screen: tabbing
back gives a black screen. Use windowed mode.
([Details](DETAILS.md#known-failure-cmdtab-in-full-screen))

## If something goes wrong

- **"permission denied" when running `install.sh`:** use `bash install.sh` (with
  `bash` at the front), exactly as written above.
- **"No permission to change files inside CrossOver.app":** open System Settings,
  Privacy & Security, App Management, turn on Terminal, then quit and reopen Terminal.
- **"The program setup.exe has encountered a serious problem":** run
  `bash install.sh setup`. It patches the `setup.exe` inside your bottle (the installer offers
  this too); patching a different copy does nothing.
- **CrossOver freezes or will not open after you force-quit it:** run
  `bash install.sh`. It finds leftover processes and offers to stop them.
- **The game still shows the 3::110 error:** run `bash install.sh check`. If it says
  the fix is working, make sure you started the game after installing, with CrossOver
  closed and reopened.

## After a CrossOver update

An update removes the fix. Run `bash install.sh` again. If it says there is no ready-made
fix for your new version, it first tests whether that version still has the bug. If it does,
build one with `bash build-dll.sh <your CrossOver version>` (needs `brew install mingw-w64 bison` once) and run `bash install.sh` again
([details](DETAILS.md#other-crossover-versions-or-other-wine-runtimes)).

## More

[DETAILS.md](DETAILS.md) has the technical cause, which versions are affected, the
checks, other CrossOver versions, and manual steps. Build and license information is in [NOTICE](NOTICE).
