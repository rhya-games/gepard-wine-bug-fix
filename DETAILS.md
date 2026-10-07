# Details

Everything that is not needed for a normal install. For the simple steps, see
[README.md](README.md).

## What each file is

| file | what it is |
|---|---|
| `install.sh` | `install`, `check`, `uninstall`, `setup`; asks before quitting CrossOver or stopping leftover processes (`-y` answers yes) |
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

Graphics settings live in `HKCU\Software\Gravity\RagnarokOnline`. With no
settings there, the first launch runs OpenSetup (`setup.exe`) — and stock
OpenSetup dies instantly under Rosetta 2 on two undocumented x87 encodings
(`DC D8`, `DC D0`, aliases of `FCOMP`/`FCOM ST(0)` that real x86 accepts), and it
also pulls in the Gepard-hooked `mss32.dll`. `patch_opensetup_rosetta.py` fixes
all three, hash-guarded, with a backup.

## Notes

`wow64win.dll` is a PE file — no codesigning needed. The prebuilt one matches
**CrossOver 26.3.0 only**; for any other version or runtime, rebuild from the
matching Wine sources. Wine is LGPL; the patch is included so the binary can be
reproduced.

Nothing here touches, patches or bypasses the anti-cheat itself — the fix is
entirely on the Wine side.

Worth reporting upstream at https://bugs.winehq.org/ so it reaches every wrapper.
