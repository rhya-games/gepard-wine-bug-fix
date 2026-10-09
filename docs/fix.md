# The Wine fix

The fix for "Gepard::T Code: 3::110::12" on CrossOver. It works for any Ragnarok Online client
that uses Gepard Shield 3.0; nothing here is specific to one server. Back to the [README](../README.md).

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
`fix/rawinput_overflow_probe`:

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
[`fix/SKILL.md`](../fix/SKILL.md) for the full procedure, or [`fix/SHARE-PROMPT.md`](../fix/SHARE-PROMPT.md) to hand the whole job to
Claude.

## Checking the fix (optional)

### Is the bug present on my runtime?

Run the probe (32-bit, so it goes through the WoW64 thunk) with your runtime's
own `wine`, for example in a CrossOver bottle. Set `BOTTLE` to your bottle name first (the folder name under `~/Library/Application Support/CrossOver/Bottles`).
Run it *before* installing the fix to see `yes`, and after to see `no`:

    cp fix/rawinput_overflow_probe.exe "$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE/drive_c/"
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
        --bottle $BOTTLE --no-gui --debugmsg -all --cx-app 'C:\rawinput_overflow_probe.exe'

    AFFECTED=yes   -> you need the fix (exit code 1)
    AFFECTED=no    -> runtime is clean, do not replace anything (exit code 0)

Any other Wine: `WINEPREFIX=/some/prefix /path/to/bin/wine fix/rawinput_overflow_probe.exe`.

To check a Wine or CrossOver source tree instead of running anything:

    grep -n -A22 "wow64_NtUserGetRawInputDeviceList" dlls/wow64win/user.c | grep "for (i"

`i < *count` is the bug, `i < ret` is fixed. Re-run the probe after every
CrossOver update: once it says `AFFECTED=no` you can drop the patched DLL.

`bash install.sh check` also looks at the bottle's graphics settings. The game's protection hooks
Direct3D 9, and DXVK (or similar layers) are reported to cause this same error even with the fix,
so it warns if the bottle's settings name DXVK, D3DMetal or DXMT, or the registry sets a native
`d3d9`. This is based on a Whisky install's notes and has not been confirmed on CrossOver.

### Is the fixed DLL actually loaded?

With the game running:

    lsof 2>/dev/null | grep -o "[^ ]*wow64win.dll" | sort -u

It should print the CrossOver path of the fixed file.

## Other CrossOver versions, or other Wine runtimes

`install.sh` uses the ready-made file named `wow64win.dll.crossover-<version>` for the CrossOver
you have, and checks it against `fix/SHA256SUMS` before copying it. Only 26.3.0 is included. On
another version it runs the check and tells you whether the bug is present. If it is, build the
file for your version:

    brew install mingw-w64 bison      # once, with Xcode command line tools and Rosetta
    bash fix/build-dll.sh 26.4.0          # your version, from "CrossOver > About"
    bash install.sh

`fix/build-dll.sh` downloads CodeWeavers' sources for that version (about 150 MB), applies the
one-line fix by function name (so it does not depend on line numbers), builds only
`wow64win.dll`, and adds its checksum to `fix/SHA256SUMS`. If the sources already have the fix, it
says so and builds nothing. It follows the manual steps in `fix/SKILL.md`. It was run end to end for
26.3.0: the freshly built file passed the bug probe (`AFFECTED=no`), though it is not
byte-identical to the one in this repo because a newer mingw compiler was used. It also picks an
SDK the linker can read (a very new default SDK failed on one Mac) and uses Homebrew's `bison`,
since the macOS one is too old. To add a version for everyone, commit the new file and its
`fix/SHA256SUMS` line.

For Sikarugir / Whisky / plain Wine, rebuild `wow64win.dll` from the matching sources and put it
next to that runtime's `ntdll.so`; the full procedure is in `fix/SKILL.md`, or hand `fix/SHARE-PROMPT.md`
to Claude.

## Doing it by hand (what install.sh does)

Quit CrossOver, then in Terminal, from the downloaded folder:

    CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
    V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3)
    [ -e "$CX/wow64win.dll.orig-$V" ] || cp -p "$CX/wow64win.dll" "$CX/wow64win.dll.orig-$V"
    cp fix/wow64win.dll.crossover-26.3.0 "$CX/wow64win.dll"

To undo, run the first two lines again in a Terminal window, then:

    mv "$CX/wow64win.dll.orig-$V" "$CX/wow64win.dll"

The backup is named per CrossOver version, so an old backup is never restored over
a newer CrossOver. `CX` and `V` only exist in the Terminal window where you typed them.
