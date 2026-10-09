# Paste-able prompt

Self-contained version of the skill, for someone who does not have the skill
installed. They paste everything below the line into Claude Code (or any Claude
with shell access) on the affected Mac.

---

I run a 32-bit Ragnarok Online client (Gepard Shield 3.0) under CrossOver on
macOS. After I load a map I get a message box:

    title: GS 3.0 :: <build>
    text:  Gepard::T Code: 3::110::12

This has a known root cause and a known fix. Please apply and verify it. Do not
patch, disable or bypass the anti-cheat, and do not attach winedbg to the live
client (it reacts to that; macOS-level tools like lsof/vmmap/sample are fine).

## Root cause (already diagnosed — do not re-investigate)

The T-code is not the failure, it is the *detection*. In Wine's WoW64 layer,
`dlls/wow64win/user.c`, `wow64_NtUserGetRawInputDeviceList()` converts `*count`
entries back to the 32-bit layout. `*count` is the capacity the caller passed
in, not the number of devices found: `NtUserGetRawInputDeviceList()` in
`dlls/win32u/rawinput.c` returns the device count and leaves `*count` untouched
on the success path. So everything past the real device count is copied out of
the uninitialised `Wow64AllocateTemp()` block into the 32-bit caller's buffer.

Gepard asks for up to 240 devices while a Mac has 2. The ~238 garbage entries
(~1.9 KB) overwrite its own stack frame; its worker thread returns to a bogus
address and dies ~12 s after the client starts, before the login screen. When a
map loads, Gepard's watchdog polls that thread, sees `ExitStatus == 0` and
raises the T-code. Only 32-bit processes are affected. This is an upstream Wine
bug, not CrossOver-specific.

The failure reproduces identically on a completely stock runtime, so ignore any
advice about PEB/TEB placement, thread priority scales, `NtCreateThreadEx`
timing, or `ProcessDebugObjectHandle` / `ThreadIsTerminated` contracts — those
are all dead ends for this symptom.

## Step 0 — OpenSetup, only needed on a fresh install

Graphics settings live in `HKCU\Software\Gravity\RagnarokOnline`. If that key
has no settings, the first launch runs OpenSetup (`setup.exe`), and stock
OpenSetup dies under Rosetta 2 on two undocumented x87 encodings, plus it pulls
in the Gepard-hooked `mss32.dll`. If I am already past the graphics dialog, skip
this step.

Back up `setup.exe`, then apply these three byte patches:

    0x21E39:  DC D8       -> D8 D8        (FCOMP ST(0), documented encoding)
    0x2C0CD:  DC D0       -> D8 D0        (FCOM  ST(0), documented encoding)
    0x43C08:  "mss32.dll" -> "mss32.off"  (skip Miles in OpenSetup only)

Verify the bytes match before writing; if they do not, this is a different
OpenSetup build — find the real offsets from the illegal-instruction
`ExceptionAddress` under `--debugmsg "+seh"` instead of forcing it. Then confirm
OpenSetup stays alive with zero `c0000005` in a `+seh` log, set a resolution and
click OK.

## Step 1 — confirm the bug is present

Save this as `rio_probe.c`. It fills a 240-entry buffer with `0xCC`, calls
`GetRawInputDeviceList`, and counts the entries past the returned device count that
got overwritten — the bug itself, not a proxy for it. Needs `brew install mingw-w64`.

```c
/* Portable detector for the wow64_NtUserGetRawInputDeviceList() overflow.
 *
 * GetRawInputDeviceList(buf, &count, size) must fill exactly `ret` entries and
 * leave the rest of the caller's buffer untouched.  Wine's WoW64 thunk converts
 * `*count` entries instead -- the capacity the caller passed in -- so every
 * entry past the real device count is copied out of an uninitialised temp block
 * into the caller's buffer.
 *
 * Run as a 32-bit binary.  A clean runtime prints AFFECTED=no.
 */
#include <windows.h>
#include <stdio.h>

#define CAP 240   /* what Gepard asks for */

int main(void)
{
    RAWINPUTDEVICELIST buf[CAP];
    UINT count, ret, i, real, dirty = 0, first_dirty = 0;

    count = 0;
    ret = GetRawInputDeviceList(NULL, &count, sizeof(RAWINPUTDEVICELIST));
    printf("query   : ret=%d  devices=%u\n", (int)ret, count);
    real = count;

    memset(buf, 0xCC, sizeof(buf));
    count = CAP;
    ret = GetRawInputDeviceList(buf, &count, sizeof(RAWINPUTDEVICELIST));
    printf("fill    : ret=%d  count_out=%u  capacity_in=%u\n", (int)ret, count, CAP);

    if (ret == (UINT)-1) { printf("call failed, cannot judge\n"); return 2; }

    for (i = ret; i < CAP; i++)
    {
        if (buf[i].hDevice != (HANDLE)(ULONG_PTR)0xCCCCCCCC || buf[i].dwType != 0xCCCCCCCC)
        {
            if (!dirty) first_dirty = i;
            dirty++;
        }
    }

    printf("devices returned : %u\n", ret);
    printf("entries clobbered past the returned count : %u", dirty);
    if (dirty) printf("  (first at index %u)", first_dirty);
    printf("\n");

    if (dirty)
    {
        printf("sample of clobbered entries:\n");
        for (i = first_dirty; i < first_dirty + 4 && i < CAP; i++)
            printf("    [%3u] hDevice=%p dwType=%08x\n", i, buf[i].hDevice, (unsigned)buf[i].dwType);
    }

    printf("AFFECTED=%s\n", dirty ? "yes" : "no");
    return dirty ? 1 : 0;
}
```

```sh
i686-w64-mingw32-gcc -O1 -o /tmp/rio_probe.exe rio_probe.c -luser32
```

CrossOver bottle:

```sh
cp /tmp/rio_probe.exe "$HOME/Library/Application Support/CrossOver/Bottles/<BOTTLE>/drive_c/"
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
    --bottle <BOTTLE> --no-gui --debugmsg -all --cx-app 'C:\rio_probe.exe'
```

Any other Wine (Sikarugir engine, Whisky, plain Wine) — use that runtime's own `bin/wine`:

```sh
env WINEPREFIX=/some/prefix WINEDEBUG=-all /path/to/wswine.bundle/bin/wine /tmp/rio_probe.exe
```

Broken runtime:

```
fill    : ret=2  count_out=240  capacity_in=240
entries clobbered past the returned count : 238  (first at index 2)
AFFECTED=yes
```

A fixed runtime prints `entries clobbered ... : 0` and `AFFECTED=no`. `count_out`
stays at 240 either way — win32u genuinely does not update it, and that is exactly
what the thunk wrongly relied on. If it says `AFFECTED=no`, stop: nothing to fix.

## Step 2 — build the fixed DLL

(Shortcut: if this checkout contains `fix/wow64win.dll.crossover-26.3.0` and `install.sh`
and CrossOver is exactly 26.3.0, run `bash install.sh` with CrossOver quit, then skip to
Step 4. Otherwise build from matching sources as below.)

```sh
V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3)
curl -o /tmp/cx-src.tar.gz "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$V.tar.gz"
mkdir -p /tmp/cxsrc && tar -xzf /tmp/cx-src.tar.gz -C /tmp/cxsrc
```

In `/tmp/cxsrc/sources/wine/dlls/wow64win/user.c`, inside
`wow64_NtUserGetRawInputDeviceList()`:

```c
-        for (i = 0; i < *count; ++i)
+        for (i = 0; i < ret; ++i)
```

```sh
mkdir -p /tmp/cxbuild && cd /tmp/cxbuild
arch -x86_64 /tmp/cxsrc/sources/wine/configure --enable-win64 --disable-tests \
    --without-x --without-freetype CC=/usr/bin/clang CXX=/usr/bin/clang++
arch -x86_64 /usr/bin/make -j4 dlls/wow64win/x86_64-windows/wow64win.dll
```

`wow64win.dll` is a PE file and needs no codesigning.

## Step 3 — deploy

Wine resolves builtin PE modules from the directory of the `ntdll.so` that was
actually loaded, **not** from `WINEDLLPATH` — a directory holding only the
replacement DLL is silently ignored. For a non-CrossOver runtime (Sikarugir, Whisky,
plain Wine), put a DLL built from that runtime's matching Wine version into its own
`lib/wine/x86_64-windows/`, next to its `ntdll.so`. For CrossOver, the simplest
reliable option, with a backup:

```sh
CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3)
[ -e "$CX/wow64win.dll.orig-$V" ] || cp -p "$CX/wow64win.dll" "$CX/wow64win.dll.orig-$V"
cp /tmp/cxbuild/dlls/wow64win/x86_64-windows/wow64win.dll "$CX/wow64win.dll"
```

This edits a signed app bundle and will be reverted by CrossOver updates — keep
the `.orig-<version>` backup and re-apply after updating. If I refuse to touch the bundle, use a
per-bottle overlay instead: it must contain a real copy (not a symlink) of
`lib/wine/x86_64-unix/ntdll.so`, ad-hoc signed with `codesign --force --sign -`,
because that copy is what anchors the lookup; then point `BinPath`/`LibPath` in
`cxbottle.conf` at the overlay.

## Step 4 — verify, all three gates must pass

**Gate 1 — the right file is loaded.** With the client running:

```sh
P=$(pgrep -f "<CLIENT>.exe" | head -1)
lsof -p "$P" | grep -o "[^ ]*wow64win.dll" | sort -u    # must be the path you deployed to
```

**Gate 2 — the bug is gone.** Re-run the probe; it must print `AFFECTED=no`.

**Gate 3 — the crash is gone.** Relaunch and compare with the pre-fix behaviour:

| | before | after |
|---|---|---|
| client process | dies ~12 s after launch | stays up |
| `c0000005` in a `+seh` trace | present | none |
| `err:seh:NtRaiseException` | present | none |

Finally I log in and load a map — that is where the watchdog check runs.

Rollback: `mv "$CX/wow64win.dll.orig-$V" "$CX/wow64win.dll"` (re-set `CX` and `V` first
if this is a new shell).
