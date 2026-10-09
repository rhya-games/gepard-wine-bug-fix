# uaRO-specific extras

These depend on the uaRO client and are set up in `profiles/uaro/profile.conf`. The Wine fix does not
need them. Back to the [README](../README.md).

## New installs: the OpenSetup patch

This is separate from the main fix above. The main fix is a change inside Wine; this
one only edits the game's own setup program (`setup.exe`), and nothing else.

On a new install the graphics settings key (`HKCU\Software\Gravity\RagnarokOnline`)
is empty, so the first launch runs OpenSetup (`setup.exe`) instead of the game. Stock
OpenSetup dies instantly under Rosetta 2 on two undocumented x87 encodings (`DC D8`,
`DC D0`, aliases of `FCOMP`/`FCOM ST(0)` that real x86 accepts), and it also loads
`mss32.dll` (the Miles audio library, which the protection hooks in the game).
`profiles/uaro/patch_opensetup_rosetta.py` fixes all three:

| offset | change | why |
|---|---|---|
| `0x21E39` | `DC D8` to `D8 D8` | documented encoding of `FCOMP ST(0)` |
| `0x2C0CD` | `DC D0` to `D8 D0` | documented encoding of `FCOM ST(0)` |
| `0x43C08` | `mss32.dll` to `mss32.off` | setup does not need audio, so it skips that library |

`bash install.sh` offers this automatically, but only when it finds the known unpatched
`setup.exe` in a bottle (it checks with `patch_opensetup_rosetta.py --check`), so it is
skipped on installs that do not need it. Run `bash install.sh setup` by hand if you skipped
it, and again if you reinstall the game or make a new bottle, because the patch applies to
the `setup.exe` file in the bottle, not to the bottle itself.

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

## Optional: AzzyAI (how it works)

`bash install.sh azzyai` (also run by `extras`, which asks first) installs the latest release
of [RagnaJDC/AzzyAI-Pre-Renewal](https://github.com/RagnaJDC/AzzyAI-Pre-Renewal), a
uaRO-specific build of Dr. Azzy's AzzyAI. Its README says it is for uaRO pre-renewal only and
errors on other servers, so the command needs `uaRO.exe` in the game folder. It is third-party
software that this repository does not ship (it has no license on GitHub); it is downloaded
when you run the command, after you confirm. Check your server's rules about AI scripts.

1. Reads the repository's releases from the GitHub API and takes the first `.zip` asset
   (currently `uaRO.AzzyAI.Beta.0.90.zip`, about 40 MB).
2. Downloads it to a temporary folder, tests the zip, unpacks it and checks that it has
   `AI/AI.lua` and `AI/USER_AI`.
3. Moves the game's current `AI` folder to `AI-BEFORE-AZZYAI` (a numbered copy if that
   already exists) and puts the new `AI` folder in its place, with a small marker file
   (`AI/.azzyai-release`) recording the version.
4. Running it again does nothing if the installed release is already the latest. If a newer
   release exists, the old AzzyAI folder, with your settings, is kept as `AI-AZZYAI-OLD`.

`bash install.sh azzyai undo` restores the original folder and keeps the AzzyAI files in
`AI-AZZYAI-REMOVED`; `bash install.sh azzyai status` shows what is installed. It refuses to run
while the game is open.

The in-game switches `/hoai` (homunculus) and `/merai` (mercenary) are saved in
`savedata/OptionInfo.lua` as `CmdOnOffList["/hoai"]` and `["/merai"]`, so the command sets both
to `1` (and `undo` sets them back to `0`), keeping a one-time backup
(`OptionInfo.lua.before-azzyai.backup`). If that file does not exist yet, start the game once
and run the command again, or type the two commands in the game. This matches a working
install where both were `1`; it was not confirmed in the game here. If `AAIStartM.txt` or
`AAIStartH.txt` appears in the game folder, AzzyAI is running.

Change AzzyAI's settings with `AI\USER_AI\AzzyAiConfigPreRe.exe` from the game folder. This build
ships with its own settings (for example `StickyStandby = 1`); this
repository does not change them. For testing without GitHub, set `AZZYAI_ZIP=/path/to/file.zip`.

## Using the tools with another server

Everything the tools assume about one game lives in a profile: the exe name, setup and patcher
programs, the launcher names, and which game-specific features exist. To support another Ragnarok
Online server, copy `profiles/uaro/` to `profiles/<name>/`, edit `profile.conf` (leave
`SETUP_PATCH` and `AZZY_REPO` empty if they do not apply), and run the tools with
`PROFILE=<name>`, for example `PROFILE=myserver bash install.sh play`. The Wine fix itself does
not use the profile.
