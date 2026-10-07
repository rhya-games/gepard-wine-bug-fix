# Fix for "Gepard::T Code: 3::110::12" on macOS (CrossOver)

If Ragnarok Online shows this right after a map loads:

    GS 3.0 :: <build>
    Gepard::T Code: 3::110::12

it is a bug in Wine (the part of CrossOver that runs Windows programs). It is not
a Gepard bug and not a broken install, and this fix does not touch the anti-cheat.

**Works with CrossOver 26.3.0.** For other versions, see [DETAILS.md](DETAILS.md).

## How to install

You will copy and paste a few commands into the **Terminal** app.

**1. Download this folder.** On the GitHub page for this project, click the green
**Code** button, then **Download ZIP**. Your browser saves it to your Downloads
folder (Safari unzips it automatically; otherwise double-click the ZIP). You get a
folder named something like `gepard-wine-bug-fix-main`.

**2. Open Terminal and go to that folder.** Open Terminal with Spotlight: press
`Cmd + Space`, type `Terminal`, press Return. Then type `cd ` (with a space after
it), drag the folder from Finder into the Terminal window, and press Return.

**3. Quit CrossOver** (CrossOver menu, then Quit).

**4. Run the installer.** Copy this line, paste it into Terminal, press Return:

    bash install.sh

It should say "Installed the fix". If it says STOP, read the message; it tells you
what to do.

**5. New game install only.** If you have never reached the game's login screen
(the first launch shows a graphics setup window that crashes), also run:

    bash install.sh setup

Then open the game, pick a resolution in the setup window and click OK.

**6. Open CrossOver and play.** Log in and load a map. The error should be gone.

## How to uninstall

Quit CrossOver, open Terminal, go to this folder the same way as in step 2, and run:

    bash install.sh uninstall

This puts the original file back.

## After a CrossOver update

An update removes the fix. Run `bash install.sh` again. If it says the version is not
supported, see [DETAILS.md](DETAILS.md): the bug may already be fixed in your
version, and there is a one-minute check for that.

## More

[DETAILS.md](DETAILS.md) has the technical cause, which versions are affected, the
checks, other CrossOver versions, and manual steps. Worth reporting upstream at
https://bugs.winehq.org/ so it reaches every wrapper.
