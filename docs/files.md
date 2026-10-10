# What each file is

Back to the [README](../README.md).

| path | what it is |
|---|---|
| `install.sh` | the one command: `install`, `check`, `uninstall`, `setup`, `play`, `open`, `backup`, `doctor`, `extras`, `window`, `keys`, `azzyai`, `launchers` (asks before quitting CrossOver; always stops leftover bottle processes; `-y` answers yes) |
| `Start Here.command` | double-click menu that runs `install.sh` |
| `lib/` | the shell code behind `install.sh`: `core.sh` (helpers), `fix.sh`, `extras.sh`, `game.sh`, `uaro.sh`, `backup.sh`, `doctor.sh` |
| `profiles/uaro/` | uaRO settings (`profile.conf`) and its `setup.exe` patcher |
| `fix/` | the Wine fix: ready-made DLLs, `SHA256SUMS`, `build-dll.sh`, the source patch, the bug probe, and the AI-facing `SKILL.md` and `SHARE-PROMPT.md` |
| `tests/smoke.sh` | smoke tests against a fake CrossOver (`bash tests/smoke.sh`) |
| `docs/` | these pages |
| `NOTICE` | license and build information for the shipped Wine DLL; third-party notes |

## Checksums

    c2cc2d3a25b9b74bd2269b209debfbaaaafcf28c40def18ada05993aab80d701  wow64win.dll.crossover-26.3.0
    5e829ee8b1338fa208c55d080ce6e0bbb827322e7b9883446c611708c180cae5  rawinput_overflow_probe.exe

Verify with `shasum -a 256 <file>`. `install.sh` checks the DLL itself before copying.
Build and license information is in [NOTICE](NOTICE).

## Notes

`wow64win.dll` is a PE file — no codesigning needed. The prebuilt one matches
**CrossOver 26.3.0 only**; for any other version or runtime, rebuild from the
matching Wine sources. Wine is LGPL; the patch is included so the binary can be
reproduced.

Nothing here touches, patches or bypasses the anti-cheat itself — the fix is
entirely on the Wine side.
