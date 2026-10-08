# Fix for "Gepard::T Code: 3::110::12" on macOS (CrossOver)

If Ragnarok Online shows this right after a map loads:

    GS 3.0 :: <build>
    Gepard::T Code: 3::110::12

it is a bug in Wine (the part of CrossOver that runs Windows programs). It is not
a Gepard bug and not a broken install, and this fix does not touch the anti-cheat.

**Works with CrossOver 26.3.0.** For other versions, see [DETAILS.md](DETAILS.md).

## How to install

**First, install the game in CrossOver.** Do everything below only after that. The scripts
stop with a message if they cannot find the game.

### Easiest: double-click

1. [Download the ZIP](https://github.com/rhya-games/gepard-wine-bug-fix/archive/refs/heads/main.zip)
   and unzip it (Safari does this for you).
2. Double-click `Start Here.command`. ([macOS blocked it?](DETAILS.md#macos-says-it-cannot-verify-start-herecommand))
3. Type `1` and press Return to install. Type `2` to check it worked.

### Or use Terminal

1. Download and unzip the ZIP above.
2. Open Terminal (press `Cmd + Space`, type `Terminal`, press Return), then paste this and
   press Return:

       cd ~/Downloads/gepard-wine-bug-fix-main

   That assumes the folder is in Downloads. If it is somewhere else, type `cd ` (with a
   space), drag the folder from Finder into the Terminal window, and press Return.
3. Run the installer. If CrossOver is open, it asks to quit it; type `y`.

       bash install.sh

   It should say "Installed the fix". If it says STOP, read the message.
4. Optional: check it worked. You want "the fix is installed and working".

       bash install.sh check

### New game install only

If the game's first launch shows a setup window that crashes, run this, then open the
game, pick a resolution and click OK. ([Why](DETAILS.md#new-installs-the-opensetup-patch))

    bash install.sh setup

### Then play

Open CrossOver, launch the game, log in and load a map. The error should be gone.

## How to uninstall

Open Terminal, go to the folder as in "Or use Terminal", and run:

    bash install.sh uninstall

This puts the original file back (it asks before quitting CrossOver if it is open).

## Optional extras (not needed for the fix)

Everything above is all you need to get rid of the error. The two extras below are
**optional**, you can skip them, and each can be undone. Both are also in the
double-click menu (item 5).

### Optional: fit the game window to your screen

Makes the game window exactly fill the usable screen area (below the menu bar, above the
Dock), so you do not have to guess a resolution. Quit the game first, then:

    bash install.sh window

It sets windowed mode and the right size and position in the game's settings file, and
keeps a backup. Undo with `bash install.sh window undo`; see the numbers without changing
anything with `bash install.sh window status`. It subtracts a 28-pixel title bar, which was
measured on one Mac, so on another screen it may be a few pixels off.

### Optional: Mac keyboard and swipe settings

These make the game feel more natural on a Mac, and you can turn them on and off any
time:

    bash install.sh keys on

- **Option works as Alt.** The game's menu shortcuts are Alt+letter, so on a Mac they are
  Option+letter.
- **Both Command keys stay normal Mac Command keys**, so Cmd+C / Cmd+V, the Mac screenshot
  keys (Cmd+Shift+3/4/5), Cmd+Tab and so on keep working.
- **Mac Control key stays Left Ctrl** (Wine already does this, so nothing to change).
- **Wine does not capture the display** in full screen. (This alone does not make swiping
  work; see "Known limitations" below.)

Then quit CrossOver completely and reopen it; the settings load when the bottle starts.
To go back to normal: `bash install.sh keys off`. To see what is set:
`bash install.sh keys status`. The double-click menu has the same options (item 5).

### Known limitations of the optional extras (not fixed)

These optional features did not work in testing, and we stopped investigating. Treat them as open failures:

- **Swiping to a separate Desktop in full screen does not work.** In full screen the game's
  window takes over every Desktop, and tabbing away with Cmd+Tab and back gives a black
  screen. Wine cannot open this game in its own full-screen Space, and macOS cannot remember
  a Desktop for it (details in [DETAILS.md](DETAILS.md)).
- **The right Command key was still reported as Ctrl in the game** even with the settings
  written (`RightCommandIsCtrl = N`) and the game restarted. We do not know why. Cmd+C and
  Cmd+V are expected to work through a hidden Edit menu, which may be what is converting them.
  The Mac screenshot keys (Cmd+Shift+3/4/5) were not confirmed working in the game.
- **What is known to work:** the main fix itself, and writing and reading back the settings
  above. If a Command, Option or screenshot key does something unexpected,
  `bash install.sh keys off` returns Wine to its defaults.
- **Best-effort workaround, untested:** play in windowed mode (not full screen) and drag
  the window to its own Desktop in Mission Control.

## If something goes wrong

- **"permission denied" when running `install.sh`:** use `bash install.sh` (with
  `bash` at the front), exactly as written above.
- **"No permission to change files inside CrossOver.app":** open System Settings,
  Privacy & Security, App Management, turn on Terminal, then quit and reopen Terminal.
- **"The program setup.exe has encountered a serious problem":** run
  `bash install.sh setup` ("New game install only"). It patches the `setup.exe` inside your bottle;
  patching a different copy does nothing.
- **CrossOver freezes or will not open after you force-quit it:** run
  `bash install.sh`. It finds leftover processes and offers to stop them.
- **The game still shows the 3::110 error:** run `bash install.sh check`. If it says
  the fix is working, make sure you started the game after installing, with CrossOver
  closed and reopened.

## After a CrossOver update

An update removes the fix. Run `bash install.sh` again. If it says the version is not
supported, run `bash install.sh check`: it tells you whether your version still has
the bug. If it does, see [DETAILS.md](DETAILS.md) for other versions.

## More

[DETAILS.md](DETAILS.md) has the technical cause, which versions are affected, the
checks, other CrossOver versions, and manual steps. Build and license information is in [NOTICE](NOTICE). Worth reporting upstream at
https://bugs.winehq.org/ so it reaches every wrapper.
