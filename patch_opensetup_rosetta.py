#!/usr/bin/env python3
"""Patch a Ragnarok Online OpenSetup (setup.exe) for Rosetta 2 + CrossOver.

Two problems, both hit on the FIRST launch of the game, because the client runs
OpenSetup when HKCU\\Software\\Gravity\\RagnarokOnline has no graphics settings
yet:

  1. OpenSetup uses two undocumented x87 encodings (DC D8 / DC D0).  Real x86
     CPUs accept them as aliases of FCOMP/FCOM ST(0); Rosetta 2 rejects them and
     the process dies with an illegal instruction.  Rewriting them to the
     documented D8 D8 / D8 D0 encodings is semantically identical.
  2. OpenSetup pulls in mss32.dll, which in a Gepard-protected install is hooked
     by the anti-cheat and is not meant to be loaded outside the game.  Renaming
     the import string to mss32.off makes OpenSetup skip it; OpenSetup does not
     need audio.  The game itself is untouched and still loads the real DLL.

The offsets below are for the uaRO "World of Your Dream" OpenSetup build with
the original SHA-256 recorded in ORIGINAL_SHA256.  The script refuses to touch
anything else -- see DETAILS.md and SKILL.md for how to locate the equivalent
bytes in a different build.

Usage:  patch_opensetup_rosetta.py [--check] /path/to/setup.exe

--check only reports and never writes: exit 0 = known build that still needs the patch,
1 = already patched, 2 = not a build this script knows.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import sys

ORIGINAL_SHA256 = "81b8a080a87ce15ac9158cf2aaf127a8f9408d6d84787d99eb188bc009932cf0"
KNOWN_INPUT_SHA256 = {
    ORIGINAL_SHA256,
    # Intermediate build with only the first x87 rewrite applied.
    "a8d0fdb96f8618a46fde8460e5a97d881e3410377a9290af516e8c9b76b1c9c5",
    # Both x87 rewrites applied, before the Miles isolation.
    "06f8a32fb0219a46a4a7d75fbb2b54af9c57baba5bb5b00dee11549534eede2b",
}
PATCHED_SHA256 = "427c3631fb52384902a8a994157c98d9c4399917e869c85d03d493e0ab83fb73"

# File offset, original bytes, Rosetta-safe equivalent, description.
PATCHES = (
    (0x21E39, bytes.fromhex("DC D8"), bytes.fromhex("D8 D8"), "FCOMP ST(0)"),
    (0x2C0CD, bytes.fromhex("DC D0"), bytes.fromhex("D8 D0"), "FCOM ST(0)"),
    (0x43C08, b"mss32.dll", b"mss32.off", "keep the Gepard-hooked Miles DLL out of OpenSetup"),
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def needs_patch(data: bytes) -> int:
    """0 = known build that needs the patch, 1 = already patched, 2 = unknown build."""
    if all(data[o : o + len(r)] == r for o, _, r, _ in PATCHES):
        return 1
    if sha256(data) in KNOWN_INPUT_SHA256:
        return 0
    return 2


def main() -> int:
    args = sys.argv[1:]
    check_only = "--check" in args
    args = [a for a in args if a != "--check"]
    if len(args) != 1:
        raise SystemExit(f"usage: {sys.argv[0]} [--check] /path/to/setup.exe")

    setup = Path(args[0])
    data = setup.read_bytes()
    current = sha256(data)
    if check_only:
        return needs_patch(data)

    for offset, original, replacement, _ in PATCHES:
        actual = data[offset : offset + len(original)]
        if actual not in (original, replacement):
            raise SystemExit(
                f"Refusing to patch {setup}: unexpected bytes at 0x{offset:X}: "
                f"{actual.hex(' ')} (expected {original.hex(' ')} or {replacement.hex(' ')}).\n"
                f"This is a different OpenSetup build (SHA-256 {current})."
            )

    if all(data[o : o + len(r)] == r for o, _, r, _ in PATCHES):
        print(f"Already patched: {setup}")
        print(f"SHA-256: {current}")
        return 0

    if current not in KNOWN_INPUT_SHA256:
        raise SystemExit(f"Refusing to patch unrecognised OpenSetup build: {current}")

    patched = bytearray(data)
    for offset, original, replacement, _ in PATCHES:
        if patched[offset : offset + len(original)] == original:
            patched[offset : offset + len(original)] = replacement

    # Every accepted input must end up byte-identical to the known patched build.
    result = sha256(bytes(patched))
    if result != PATCHED_SHA256:
        raise SystemExit(
            f"Refusing to write {setup}: the patched result ({result}) is not the expected "
            f"build ({PATCHED_SHA256}). Nothing was changed."
        )

    backup = setup.with_name(f"{setup.name}.original-{ORIGINAL_SHA256[:12]}.backup")
    if backup.exists():
        if sha256(backup.read_bytes()) != ORIGINAL_SHA256:
            raise SystemExit(f"Existing backup has an unexpected SHA-256: {backup}")
    else:
        shutil.copy2(setup, backup)

    for offset, original, replacement, description in PATCHES:
        if data[offset : offset + len(original)] == original:
            print(f"Patched 0x{offset:X}: {original.hex(' ')} -> {replacement.hex(' ')} ({description})")

    tmp = setup.with_name(f".{setup.name}.patching")
    tmp.write_bytes(patched)
    shutil.copystat(setup, tmp)
    os.replace(tmp, setup)

    print(f"Backup:  {backup}")
    print(f"Patched: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
