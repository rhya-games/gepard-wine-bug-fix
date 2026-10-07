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

Build and run this probe inside the bottle (needs `brew install mingw-w64`):

```c
#include <windows.h>
#include <stdio.h>
int main(void){
    RAWINPUTDEVICELIST list[64]; UINT count=64,r;
    r=GetRawInputDeviceList(NULL,&count,sizeof(RAWINPUTDEVICELIST));
    printf("query : ret=%u count=%u\n",r,count);
    count=64;
    r=GetRawInputDeviceList(list,&count,sizeof(RAWINPUTDEVICELIST));
    printf("fill  : ret=%u count=%u\n",r,count);
    return 0;
}
```

```sh
i686-w64-mingw32-gcc -O1 -o probe.exe probe.c -luser32
cp probe.exe "$HOME/Library/Application Support/CrossOver/Bottles/<BOTTLE>/drive_c/"
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
    --bottle <BOTTLE> --no-gui --debugmsg -all --cx-app 'C:\probe.exe'
```

`fill : ret=2 count=64` — `ret` is the real device count while `count` stayed at
the input capacity. That mismatch is what the thunk wrongly relied on.

## Step 2 — build the fixed DLL

```sh
V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleShortVersionString)
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
replacement DLL is silently ignored. Simplest reliable option, with a backup:

```sh
CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleShortVersionString)
[ -e "$CX/wow64win.dll.orig-$V" ] || cp -p "$CX/wow64win.dll" "$CX/wow64win.dll.orig-$V"
cp /tmp/cxbuild/dlls/wow64win/x86_64-windows/wow64win.dll "$CX/wow64win.dll"
```

This edits a signed app bundle and will be reverted by CrossOver updates — keep
the `.orig-<version>` backup and re-apply after updating. If I refuse to touch the bundle, use a
per-bottle overlay instead: it must contain a real copy (not a symlink) of
`lib/wine/x86_64-unix/ntdll.so`, ad-hoc signed with `codesign --force --sign -`,
because that copy is what anchors the lookup; then point `BinPath`/`LibPath` in
`cxbottle.conf` at the overlay.

## Step 4 — verify, both gates

```sh
P=$(pgrep -f "<CLIENT>.exe" | head -1)
lsof -p "$P" | grep -o "[^ ]*wow64win.dll" | sort -u    # must be the path you deployed to
```

Then relaunch and compare with the pre-fix behaviour:

| | before | after |
|---|---|---|
| client process | dies ~12 s after launch | stays up |
| `c0000005` in a `+seh` trace | present | none |
| `err:seh:NtRaiseException` | present | none |

Finally I log in and load a map — that is where the watchdog check runs.

Rollback: `mv "$CX/wow64win.dll.orig-$V" "$CX/wow64win.dll"`.
