---
name: gepard-crossover-rawinput-fix
description: Diagnose and fix "Gepard::T Code: 3::110::12" (and the same class of unexplained early crash) for 32-bit Windows games under CrossOver/Wine on macOS. The real cause is a WoW64 bug in wow64_NtUserGetRawInputDeviceList that fills the caller's buffer with uninitialised memory. Use when a Ragnarok Online client with Gepard Shield shows a T-code after loading a map, or when any 32-bit app dies a few seconds after start with a garbage EIP shortly after calling GetRawInputDeviceList.
---

# Gepard / CrossOver raw input WoW64 fix

## What this fixes

`dlls/wow64win/user.c`, `wow64_NtUserGetRawInputDeviceList()` converts `*count`
entries back to the 32-bit layout. `*count` is **the capacity the caller passed
in**, not the number of devices found — `NtUserGetRawInputDeviceList()` returns
the device count and leaves `*count` untouched on the success path
(`dlls/win32u/rawinput.c`). Everything past the real device count is therefore
copied out of the uninitialised `Wow64AllocateTemp()` block into the 32-bit
caller's buffer.

An app that asks for a large capacity gets its buffer filled with garbage far
beyond the devices that exist. Gepard Shield asks for up to 240 devices while a
typical Mac has 2; the ~238 garbage entries (about 1.9 KB) run past its buffer
and overwrite its own stack frame. Its worker thread returns to a bogus address
and dies about 12 seconds after the client starts — **before the login screen**.
Much later, when a map loads, Gepard's watchdog polls that thread, sees
`ExitStatus == 0` on a worker that must still be running, and aborts with
`Gepard::T Code: 3::110::12`.

Only 32-bit processes are affected, because only they go through the WoW64
thunk. This is an upstream Wine bug, not CrossOver-specific.

## Prerequisite: make OpenSetup work first

**Do this before anything else on a fresh install.** The client stores its
graphics settings in `HKCU\Software\Gravity\RagnarokOnline`. On a machine where
that key has no settings — i.e. every new install — the **first launch runs
OpenSetup (`setup.exe`) instead of the game**. If OpenSetup does not run, the
user never gets past it, and the raw input fix below is irrelevant because the
game never starts.

Under Rosetta 2 the stock OpenSetup dies immediately: it uses two undocumented
x87 encodings (`DC D8`, `DC D0`) that real x86 CPUs accept as aliases of
`FCOMP`/`FCOM ST(0)` but Rosetta rejects with an illegal instruction. It also
loads `mss32.dll`, which in a Gepard-protected install is hooked by the
anti-cheat and should not be loaded outside the game.

Run `patch_opensetup_rosetta.py` (shipped next to this file):

```sh
python3 patch_opensetup_rosetta.py \
  "$HOME/Library/Application Support/CrossOver/Bottles/<BOTTLE>/drive_c/users/crossover/AppData/Local/Programs/<GAME DIR>/setup.exe"
```

It is hash-guarded: it makes a `.backup` beside the file, refuses unknown builds,
and is safe to re-run (it reports "Already patched"). The three changes are
`0x21E39 DC D8 -> D8 D8`, `0x2C0CD DC D0 -> D8 D0`, and
`0x43C08 "mss32.dll" -> "mss32.off"`.

Verify OpenSetup actually runs — it must stay alive and log **zero** access
violations:

```sh
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
    --bottle <BOTTLE> --no-gui --cx-log /tmp/opensetup.log --debugmsg "+seh" \
    --workdir '<WINDOWS GAME DIR>' --cx-app '<WINDOWS GAME DIR>\setup.exe'
# after ~15 s, in another shell:
pgrep -f setup.exe                                  # must still be alive
grep -ac "c0000005" /tmp/opensetup.log              # must be 0
```

Then have the user set a resolution and click OK, so the registry key is
written and subsequent launches start the game.

**If the offsets do not match** (a different server's build), do not force it.
Find the real ones: run OpenSetup with `--debugmsg "+seh"`, take the
`ExceptionAddress` of the illegal-instruction exception, subtract the module
base to get the RVA, convert RVA to file offset via the section table, and check
that the bytes there are `DC D8` or `DC D0`.

## Scope check

Confirm all of these before touching anything:

1. macOS, Apple Silicon or Intel, CrossOver (or plain Wine) using **new WoW64**
   for a 32-bit app.
2. The app dies, or a thread inside it dies, shortly after start — not at the
   moment the visible error appears.
3. `CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/wow64win.dll`
   exists (that is the file being fixed).

Get the exact version — the fix must be built against matching sources:

```sh
defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3
```

(The app may also live in `~/Applications/CrossOver.app`.)

## Affected versions

The thunk was introduced in **wine-7.12** and the bug is still in **master as of
August 2026** — verified by diffing the released tags: absent in 7.7…7.11,
present from 7.12 through 10.0 and master. Anything built on Wine ≥ 7.12 that
uses new WoW64 is affected, which in practice means all of CrossOver 22+,
Sikarugir/Kegworks engines, and current upstream Wine. Measured directly:

| runtime | result |
|---|---|
| Whisky Wine 7.7 | not affected (thunk does not exist yet) |
| CrossOver 26.3.0, stock | **affected** — 238 of 240 entries clobbered |
| Sikarugir engine, wine-10.0 | **affected** — 238 of 240 entries clobbered |
| CrossOver 26.3.0 + this fix | not affected |

## Confirm the bug is actually present

Do not apply the fix blind, and use this same probe afterwards as the success
test. `rawinput_overflow_probe.c` (shipped next to this file) fills a 240-entry
buffer with `0xCC`, calls `GetRawInputDeviceList`, and reports how many entries
past the returned device count got clobbered — which is the bug itself, not a
proxy for it.

```sh
i686-w64-mingw32-gcc -O1 -o /tmp/rio_probe.exe rawinput_overflow_probe.c -luser32
```

CrossOver bottle:

```sh
cp /tmp/rio_probe.exe "$HOME/Library/Application Support/CrossOver/Bottles/<BOTTLE>/drive_c/"
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
    --bottle <BOTTLE> --no-gui --debugmsg -all --cx-app 'C:\rio_probe.exe'
```

Any other Wine (Sikarugir engine, Whisky, plain Wine) — point it at the
runtime's own `bin/wine`:

```sh
env WINEPREFIX=/some/prefix WINEDEBUG=-all /path/to/wswine.bundle/bin/wine /tmp/rio_probe.exe
```

Broken runtime:

```
fill    : ret=2  count_out=240  capacity_in=240
entries clobbered past the returned count : 238  (first at index 2)
AFFECTED=yes
```

Fixed runtime prints `entries clobbered ... : 0` and `AFFECTED=no`. Note that
`count_out` stays at 240 either way — win32u genuinely does not update it, and
that is precisely what the thunk wrongly relied on.

If you can also trace the app, the signature to look for is an access violation
with a nonsense EIP within a millisecond of a `GetRawInputDeviceList` call:

```sh
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
    --bottle <BOTTLE> --no-gui --cx-log /tmp/trace.log --debugmsg "+relay,+seh" \
    --workdir '<WINDOWS DIR>' --cx-app '<WINDOWS EXE>' <args>
# then
grep -a "dispatch_exception code=c0000005" /tmp/trace.log
grep -a "err:seh" /tmp/trace.log
```

## Build the fixed wow64win.dll

If the person sharing the fix gave you a prebuilt `wow64win.dll`, skip to
Deploy — but only if it was built from the **same CrossOver version**. Otherwise
build it:

```sh
V=26.3.0        # first three fields of CFBundleVersion (CFBundleShortVersionString says just "26.3")
curl -o /tmp/crossover-sources-$V.tar.gz \
     "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$V.tar.gz"
mkdir -p /tmp/cxsrc && tar -xzf /tmp/crossover-sources-$V.tar.gz -C /tmp/cxsrc
# tree lands at /tmp/cxsrc/sources/wine
```

Requirements: Xcode command line tools, and `mingw-w64` (`brew install mingw-w64`)
which provides `x86_64-w64-mingw32-gcc` and `i686-w64-mingw32-gcc`.

Apply `wow64win-rawinput-devicelist.patch` (shipped next to this file), or make
the edit directly in `dlls/wow64win/user.c`, inside
`wow64_NtUserGetRawInputDeviceList()`:

```c
-        for (i = 0; i < *count; ++i)
+        for (i = 0; i < ret; ++i)
```

Configure and build **only** that one DLL:

```sh
mkdir -p /tmp/cxbuild && cd /tmp/cxbuild
arch -x86_64 /tmp/cxsrc/sources/wine/configure \
    --enable-win64 --disable-tests --without-x --without-freetype \
    CC=/usr/bin/clang CXX=/usr/bin/clang++
arch -x86_64 /usr/bin/make -j4 dlls/wow64win/x86_64-windows/wow64win.dll
```

`wow64win.dll` is a PE file — it needs **no** codesigning.

## Deploy

**Shortcut for CrossOver 26.3.0:** with CrossOver quit, `bash install.sh` does the
version check, versioned backup, install and verification (`bash install.sh
uninstall` reverts; `bash install.sh setup` runs the OpenSetup patch). The manual
steps below are for every other version and runtime.

For a non-CrossOver runtime (Sikarugir engine, Whisky, plain Wine) the DLL simply
goes into that runtime's own `lib/wine/x86_64-windows/`, next to its `ntdll.so`
— e.g. `<engine>/wswine.bundle/lib/wine/x86_64-windows/wow64win.dll`. Build it
from the matching Wine version, not from CrossOver sources.

For CrossOver, Wine resolves builtin PE modules **from the directory of the
`ntdll.so` that was actually loaded**, not from `WINEDLLPATH`. A directory containing only the
replacement DLL will be silently ignored. This is verified behaviour, so always
finish with the lsof check.

**Option A — replace it in CrossOver.app (simple, applies to every bottle).**

```sh
CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
V=$(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion | cut -d. -f1-3)
[ -e "$CX/wow64win.dll.orig-$V" ] || cp -p "$CX/wow64win.dll" "$CX/wow64win.dll.orig-$V"      # backup first
cp /tmp/cxbuild/dlls/wow64win/x86_64-windows/wow64win.dll "$CX/wow64win.dll"
```

Caveat to state plainly to the user: this edits the contents of a signed
application bundle. Keep the `.orig-<version>` backup, and expect it to be reverted by any
CrossOver update (re-apply afterwards).

**Option B — per-bottle overlay (leaves CrossOver.app untouched).**

Only worth it if the user insists on not touching the bundle. The overlay must
supply the `ntdll.so` that gets loaded, because that is what anchors the lookup:
copy (do **not** symlink) `lib/wine/x86_64-unix/ntdll.so` and `wine` into the
overlay, ad-hoc sign the copied `ntdll.so` (`codesign --force --sign - ntdll.so`),
symlink everything else, drop the patched `wow64win.dll` into the overlay's
`lib/wine/x86_64-windows/`, then point the bottle at it in `cxbottle.conf`:

```
"BinPath" = "<overlay>/lib/wine/x86_64-unix:${CX_ROOT}/bin"
"LibPath" = "<overlay>/lib:${CX_ROOT}/lib"
```

## Verify — all three gates must pass

**Gate 1 — the right file is loaded.** Launch the app, then:

```sh
P=$(pgrep -f "<APP>.exe" | head -1)
lsof -p "$P" | grep -o "[^ ]*wow64win.dll" | sort -u
```

It must print the path you deployed to. If it prints anything else, the deploy
did not take — fix that before continuing.

**Gate 2 — the bug is gone.** Re-run `rawinput_overflow_probe.exe`; it must now
print `AFFECTED=no`.

**Gate 3 — the crash is gone.** Compare against the failure you recorded in the
pre-check. For the uaRO client the difference is unambiguous:

| | before | after |
|---|---|---|
| client process | dies ~12 s after launch | stays up |
| `c0000005` in a `+seh` trace | present | none |
| `err:seh:NtRaiseException` | present | none |

Then have the user do the real end-to-end test (log in, load a map). The
watchdog check that produces the T-code only runs there.

## Rollback

Option A: `mv "$CX/wow64win.dll.orig-$V" "$CX/wow64win.dll"` (re-set `CX` and `V` first if this is a new shell), or `bash install.sh uninstall`.
Option B: restore the `wow64win.dll` symlink in the overlay, or revert the
`cxbottle.conf` backup.

## Do not

- Do not patch, disable or bypass the anti-cheat module, and do not suppress the
  message box. The goal is Wine compatibility; tampering with the protection is
  both out of scope and likely to get the account banned.
- Do not attach a Windows-level debugger (`winedbg`) to a live protected client
  — it reacts to that. macOS-level tools (`lsof`, `vmmap`, `sample`) are not
  visible to it.
- Do not chase PEB/TEB placement, thread priority scales, `NtCreateThreadEx`
  timing, or `ProcessDebugObjectHandle`/`ThreadIsTerminated` contracts. Those
  were investigated at length for this exact symptom and are all irrelevant —
  the failure reproduces identically on a completely stock runtime.

## Upstream

This is a genuine upstream Wine bug. Encourage reporting it at
https://bugs.winehq.org/ with the patch, so the fix reaches everyone instead of
being re-applied by hand after each CrossOver update.
