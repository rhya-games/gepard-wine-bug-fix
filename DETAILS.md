# Details

Everything that is not needed for a normal install. For the simple steps, see
[README.md](README.md).

## Checksums

    c2cc2d3a25b9b74bd2269b209debfbaaaafcf28c40def18ada05993aab80d701  wow64win.dll.crossover-26.3.0
    5e829ee8b1338fa208c55d080ce6e0bbb827322e7b9883446c611708c180cae5  rawinput_overflow_probe.exe

Verify with `shasum -a 256 <file>`. `install.sh` checks the DLL itself before copying.
Build and license information is in [NOTICE](NOTICE).

## What each file is

| file | what it is |
|---|---|
| `NOTICE` | license and build information for the shipped Wine DLL |
| `Start Here.command` | double-click menu that runs `install.sh` for non-Terminal users |
| `install.sh` | `install`, `check`, `uninstall`, `setup`, plus the optional `window` and `keys`; asks before quitting CrossOver or stopping leftover processes (`-y` answers yes) |
| `wow64win.dll.crossover-26.3.0` | the fixed Wine file, prebuilt, **CrossOver 26.3.0 only** |
| `patch_opensetup_rosetta.py` | first-run setup.exe fix (used by `bash install.sh setup`) |
| `rawinput_overflow_probe.c` / `.exe` | detects the bug, and confirms the fix |
| `wow64win-rawinput-devicelist.patch` | the fix as a source patch, with the analysis in the header |
| `SKILL.md` | full diagnose, build, deploy, verify and rollback procedure |
| `SHARE-PROMPT.md` | the same as a self-contained prompt for any Claude |

## Doing it by hand (what install.sh does)

Quit CrossOver, then in Terminal, from the downloaded folder:

    CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
    V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3)
    [ -e "$CX/wow64win.dll.orig-$V" ] || cp -p "$CX/wow64win.dll" "$CX/wow64win.dll.orig-$V"
    cp wow64win.dll.crossover-26.3.0 "$CX/wow64win.dll"

To undo, run the first two lines again in a Terminal window, then:

    mv "$CX/wow64win.dll.orig-$V" "$CX/wow64win.dll"

The backup is named per CrossOver version, so an old backup is never restored over
a newer CrossOver. `CX` and `V` only exist in the Terminal window where you typed them.

## Optional: fitting the game window (how it works)

`bash install.sh window` is an optional extra. It edits `savedata/OptionInfo.lua` in the
game folder (found by searching the CrossOver bottles; it asks if there is more than one):

1. Asks macOS for the primary screen's usable area (`NSScreen.visibleFrame`: the screen
   minus the menu bar and the Dock) and the menu bar height.
2. Sets `ISFULLSCREENMODE = 0` (windowed), `WIDTH`/`OLD_WIDTH` to the usable width,
   `HEIGHT`/`OLD_HEIGHT` to the usable height minus a 28 px title bar,
   and `Window_XPos`/`Window_YPos` to the top-left of the usable area.
3. Makes a one-time backup (`OptionInfo.lua.before-window-fit.backup`); `window undo`
   restores it.

It refuses to run while the game is open, because the game rewrites this file when it exits.
Example on a 1728 x 1117 (points) MacBook screen with the Dock at the bottom: usable area
1728 x 984, so the game area is 1728 x 956 at (0, 33), and the measured window frame was
1728 x 984 at (0, 33). The 28 px title bar was measured on that one setup. Wine only hides
the menu bar when a window covers the whole screen, so this does not hide it; it just
removes the guesswork about size.

## Optional: Mac keyboard and swipe settings (how it works)

`bash install.sh keys on` writes these values to `HKCU\Software\Wine\Mac Driver` in
the chosen bottle (through `wine reg add`), and `keys off` deletes exactly those values:

| value | set to | what Wine's Mac driver does |
|---|---|---|
| `LeftCommandIsCtrl` | `N` | left Command stays a Mac Command key (default: Wine sends Alt to the game) |
| `RightCommandIsCtrl` | `N` | right Command stays a Mac Command key, so Mac shortcuts such as the screenshot keys keep working |
| `LeftOptionIsAlt` | `Y` | left Option sends Alt (default: sends nothing) |
| `RightOptionIsAlt` | `Y` | right Option sends Alt (default: sends nothing) |
| `CaptureDisplaysForFullscreen` | `N` | do not capture the display for full screen (this is Wine's default, written explicitly) |

Why Command is left alone: Wine already sends a bare Command key to the game as Alt
(`kVK_Command` maps to `VK_LMENU` in `keyboard.c`), and the game's menu shortcuts are
Alt+letter, so Option is made Alt as well. Wine and CrossOver also add a hidden Edit menu
(`EditMenu` option) so Cmd+C and Cmd+V still paste as Ctrl+C / Ctrl+V. Mapping Command to
Ctrl (`LeftCommandIsCtrl` / `RightCommandIsCtrl`) only changes how an already-delivered
Command press is translated and gets in the way of Mac shortcuts, so this bundle sets
those to `N`. The Mac Control key already maps to Left/Right Ctrl by default.

The value names
were checked against Wine's `dlls/winemac.drv/macdrv_main.c` and the default key table in
`keyboard.c`; swipe gestures depend on macOS. Wine can only open a window in a native full-screen Space
when it is titled and resizable (`adjustFullScreenBehavior:` in `cocoa_window.m`), which the
game window and Wine virtual desktops (`WS_POPUP`) are not, and under CrossOver each game
run is a separate temporary macOS app (`.../winetemp-*/uaRO.exe`, no bundle id), so the
Dock "Assign To" setting cannot persist. See "Known failures" below. The driver reads the values when
the bottle starts, so CrossOver must be restarted. `keys off` restores Wine's defaults,
not any custom values you had set for these names beforehand.

## Known failures: full-screen swipe and the right Command key

Recorded so nobody repeats the work. Not fixed.

- **Full screen takes over all Desktops.** In full screen the game window is a floating
  window (CoreGraphics window layer 3) owned by its own temporary macOS app
  (`.../winetemp-*/uaRO.exe`); in windowed mode it was a normal layer-0 window. Wine raises
  fullscreen and topmost windows to higher levels (`minimumLevelForActive:` in
  `cocoa_window.m`), and native full-screen Spaces are only offered to titled, resizable
  windows (`adjustFullScreenBehavior:`). No registry value in Wine's Mac driver changes
  this; CrossOver's `winemac.so` has the same option set as upstream plus `EditMenu`.
  Cmd+Tab back into the full-screen game gives a black screen (exclusive-fullscreen behaviour).
- **Right Command still behaves as Ctrl.** With `LeftCommandIsCtrl=N` and `RightCommandIsCtrl=N`
  confirmed in the bottle's `user.reg` and the game started afterwards, the game still saw
  Ctrl from the right Command key. Unresolved. A likely cause is the hidden Edit menu
  (`EditMenu`, on by default) turning Command+key presses into Ctrl+key; testing with
  `EditMenu=N` was not done. The Mac screenshot keys were not confirmed working in the game.

## Other CrossOver versions, or other Wine runtimes

The prebuilt file matches **CrossOver 26.3.0 only**. For any other version, or for
Sikarugir / Whisky / plain Wine, rebuild `wow64win.dll` from the matching sources
with the one-line fix and put it next to that runtime's `ntdll.so`. The full
procedure is in `SKILL.md`, or hand `SHARE-PROMPT.md` to Claude.

## Checking things (optional)

### Is the bug present on my runtime?

Run the probe (32-bit, so it goes through the WoW64 thunk) with your runtime's
own `wine`, for example in a CrossOver bottle. Set `BOTTLE` to your bottle name first (the folder name under `~/Library/Application Support/CrossOver/Bottles`).
Run it *before* installing the fix to see `yes`, and after to see `no`:

    cp rawinput_overflow_probe.exe "$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/drive_c/"
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
        --bottle $BOTTLE --no-gui --debugmsg -all --cx-app 'C:\rawinput_overflow_probe.exe'

    AFFECTED=yes   -> you need the fix (exit code 1)
    AFFECTED=no    -> runtime is clean, do not replace anything (exit code 0)

Any other Wine: `WINEPREFIX=/some/prefix /path/to/bin/wine rawinput_overflow_probe.exe`.

To check a Wine or CrossOver source tree instead of running anything:

    grep -n -A22 "wow64_NtUserGetRawInputDeviceList" dlls/wow64win/user.c | grep "for (i"

`i < *count` is the bug, `i < ret` is fixed. Re-run the probe after every
CrossOver update: once it says `AFFECTED=no` you can drop the patched DLL.

### Is the fixed DLL actually loaded?

With the game running:

    lsof 2>/dev/null | grep -o "[^ ]*wow64win.dll" | sort -u

It should print the CrossOver path from step 1.

## Cause

`wow64_NtUserGetRawInputDeviceList()` in `dlls/wow64win/user.c` converts `*count`
entries back to the 32-bit layout. `*count` is the *capacity the caller passed
in*, not the number of devices found — `NtUserGetRawInputDeviceList()` in
`dlls/win32u/rawinput.c` returns the device count and leaves `*count` untouched
on the success path. Everything past the real device count is copied out of an
uninitialised `Wow64AllocateTemp()` block straight into the 32-bit caller's
buffer.

Gepard asks for up to 240 devices; a typical Mac has 2. The 238 garbage entries
(~1.9 KB) overwrite Gepard's own stack frame, its worker thread returns to a
bogus address and dies about 12 seconds after the client starts — before the
login screen. When a map loads, Gepard's watchdog polls that thread, sees
`ExitStatus == 0` on a worker that must still be running, and raises the T-code.

Only 32-bit processes are affected, because only they go through the WoW64 thunk.

## Affected versions

The thunk appeared in **wine-7.12** and the bug is still in **master (Aug 2026)**:
absent in 7.7–7.11, present 7.12 → 10.0 → master. Measured directly with
`rawinput_overflow_probe`:

    Whisky Wine 7.7 .............. not affected (thunk does not exist yet)
    CrossOver 26.3.0 stock ....... AFFECTED - 238 of 240 entries clobbered
    Sikarugir engine wine-10.0 ... AFFECTED - 238 of 240 entries clobbered
    CrossOver 26.3.0 + this fix .. not affected

## Fix

One line, in `wow64_NtUserGetRawInputDeviceList()`:

```c
-        for (i = 0; i < *count; ++i)
+        for (i = 0; i < ret; ++i)
```

Rebuild `wow64win.dll` and drop it next to the runtime's `ntdll.so`. See
`SKILL.md` for the full procedure, or `SHARE-PROMPT.md` to hand the whole job to
Claude.

## New installs: the OpenSetup patch

This is separate from the main fix above. The main fix is a change inside Wine; this
one only edits the game's own setup program (`setup.exe`), and nothing else.

On a new install the graphics settings key (`HKCU\Software\Gravity\RagnarokOnline`)
is empty, so the first launch runs OpenSetup (`setup.exe`) instead of the game. Stock
OpenSetup dies instantly under Rosetta 2 on two undocumented x87 encodings (`DC D8`,
`DC D0`, aliases of `FCOMP`/`FCOM ST(0)` that real x86 accepts), and it also loads
`mss32.dll` (the Miles audio library, which the protection hooks in the game).
`patch_opensetup_rosetta.py` fixes all three:

| offset | change | why |
|---|---|---|
| `0x21E39` | `DC D8` to `D8 D8` | documented encoding of `FCOMP ST(0)` |
| `0x2C0CD` | `DC D0` to `D8 D0` | documented encoding of `FCOM ST(0)` |
| `0x43C08` | `mss32.dll` to `mss32.off` | setup does not need audio, so it skips that library |

What it does and does not do:
- It edits only `setup.exe`. It does not touch the game executable, the game's copy of
  `mss32.dll`, or any anti-cheat file; the game still loads everything normally.
- It only accepts the one known `setup.exe` build (checked by SHA-256 and by the bytes at
  those offsets), makes a backup next to the file, and refuses to write anything that
  would not end up byte-identical to the known patched build.
- It is a convenience for running the setup window under macOS. If you are not
  comfortable modifying a file from the game's installer, skip it and set your graphics
  options another way. Check your server's rules if in doubt.
- For a different build, find the real offsets: run `setup.exe` with `--debugmsg "+seh"`,
  take the `ExceptionAddress` of the illegal-instruction exception, subtract the module
  base for the RVA, convert it to a file offset with the section table, and check that the
  bytes there are `DC D8` or `DC D0`.

## Notes

`wow64win.dll` is a PE file — no codesigning needed. The prebuilt one matches
**CrossOver 26.3.0 only**; for any other version or runtime, rebuild from the
matching Wine sources. Wine is LGPL; the patch is included so the binary can be
reproduced.

Nothing here touches, patches or bypasses the anti-cheat itself — the fix is
entirely on the Wine side.

Worth reporting upstream at https://bugs.winehq.org/ so it reaches every wrapper.
