#!/bin/bash
# Builds the fixed wow64win.dll for a CrossOver version from CodeWeavers' published sources.
#
#   bash fix/build-dll.sh 26.4.0
#
# Needs (once): Xcode command line tools (xcode-select --install), Rosetta on Apple Silicon
# (softwareupdate --install-rosetta), and two Homebrew tools: brew install mingw-w64 bison
# (macOS ships a bison that is too old for Wine).
# Downloads about 150 MB of sources and compiles Wine's build tools, so it takes a while.
#
# Result: wow64win.dll.crossover-<version> next to this script, plus its checksum line added to
# SHA256SUMS, so `bash install.sh` can use it straight away. Details: docs/fix.md
#
# Verified end to end for 26.3.0 (the result passed the bug probe). It picks an SDK the linker
# can read, and uses Homebrew's bison when the system one is too old.

set -eu
cd "$(dirname "$0")" || exit 1

die() { echo; echo "STOP: $*"; exit 1; }

V="${1:-}"
case "$V" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "Usage: bash fix/build-dll.sh <CrossOver version>, for example 26.3.0
Your installed version: $(defaults read /Applications/CrossOver.app/Contents/Info.plist CFBundleVersion 2>/dev/null | cut -d. -f1-3)" ;; esac

OUT="wow64win.dll.crossover-$V"
[ ! -e "$OUT" ] || die "$OUT already exists here. Delete it first if you want to rebuild it."

xcode-select -p >/dev/null 2>&1 || die "Xcode command line tools are missing. Run: xcode-select --install"
command -v x86_64-w64-mingw32-gcc >/dev/null || die "The mingw-w64 compiler is missing. Run: brew install mingw-w64 bison"
# Wine needs bison 3.0 or newer; macOS has 2.3. Prefer Homebrew's if the default is too old.
bison_major() { "$1" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1; }
if [ "$(bison_major bison || echo 0)" -lt 3 ] 2>/dev/null || [ -z "$(bison_major bison)" ]; then
    for b in /opt/homebrew/opt/bison/bin /usr/local/opt/bison/bin; do
        [ -x "$b/bison" ] && [ "$(bison_major "$b/bison")" -ge 3 ] 2>/dev/null && { export PATH="$b:$PATH"; break; }
    done
fi
[ "$(bison_major bison)" -ge 3 ] 2>/dev/null || die "bison 3.0 or newer is needed. Run: brew install bison"
ARCH=""
if [ "$(uname -m)" = "arm64" ]; then
    arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta is missing. Run: softwareupdate --install-rosetta"
    ARCH="arch -x86_64"
fi

# Use an SDK the (Rosetta) linker can read: a very new SDK can fail with "tapi error: malformed
# file". Try the default first, then older ones.
echo 'int main(void){return 0;}' > "${TMPDIR:-/tmp}/gwf-sdk-test.c"
SDK_OK=""
for sdk in "${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null)}" \
           /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
           /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
           /Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk; do
    [ -d "$sdk" ] || continue
    if SDKROOT="$sdk" $ARCH /usr/bin/clang -o "${TMPDIR:-/tmp}/gwf-sdk-test" "${TMPDIR:-/tmp}/gwf-sdk-test.c" >/dev/null 2>&1; then
        SDK_OK="$sdk"; break
    fi
done
rm -f "${TMPDIR:-/tmp}/gwf-sdk-test" "${TMPDIR:-/tmp}/gwf-sdk-test.c"
[ -n "$SDK_OK" ] || die "No macOS SDK that can build x86_64 programs was found. Update the Xcode command line tools."
export SDKROOT="$SDK_OK"
echo "Using SDK: $SDK_OK"

WORK="${BUILD_DIR:-$HOME/.cache/gepard-wine-fix/build-$V}"
TARBALL="$WORK/crossover-sources-$V.tar.gz"
SRC="$WORK/src"
mkdir -p "$WORK"

if [ ! -f "$TARBALL" ]; then
    echo "Downloading the CrossOver $V sources (about 150 MB)..."
    curl -fL --progress-bar -o "$TARBALL.part" \
        "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$V.tar.gz" \
        || { rm -f "$TARBALL.part"; die "Could not download the sources for CrossOver $V. Is the version number right?"; }
    mv "$TARBALL.part" "$TARBALL"
fi

if [ ! -f "$SRC/sources/wine/configure" ]; then
    echo "Unpacking..."
    rm -rf "$SRC" "$WORK/.fix-applied"; mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" || die "Could not unpack the sources."
fi
WINE="$SRC/sources/wine"
[ -f "$WINE/dlls/wow64win/user.c" ] || die "The sources do not look like Wine (no dlls/wow64win/user.c)."

# The one-line fix, found by function name (line numbers differ between versions).
rc=0
python3 - "$WINE/dlls/wow64win/user.c" <<'PYEOF' || rc=$?
import re, sys
path = sys.argv[1]
s = open(path).read()
i = s.find("wow64_NtUserGetRawInputDeviceList")
if i < 0:
    sys.exit("STOP: wow64_NtUserGetRawInputDeviceList was not found in these sources.")
region = s[i:i + 2500]
if re.search(r"for \(i = 0; i < ret; \+\+i\)", region) and not re.search(r"i < \*count", region):
    sys.exit(7)
m = re.search(r"for \(i = 0; i < \*count; \+\+i\)", region)
if not m:
    sys.exit("STOP: the loop to fix was not found. The code may have changed; see SKILL.md.")
start = i + m.start()
s = s[:start] + "for (i = 0; i < ret; ++i)" + s[start + len(m.group(0)):]
open(path, "w").write(s)
print("Applied the fix to dlls/wow64win/user.c")
PYEOF
if [ "$rc" -eq 0 ]; then
    touch "$WORK/.fix-applied"       # remember that WE made the change (so a re-run still builds)
elif [ "$rc" -eq 7 ] && [ ! -e "$WORK/.fix-applied" ]; then
    echo "These sources already have the fix, so there is nothing to build for CrossOver $V."
    exit 0
elif [ "$rc" -ne 7 ]; then
    exit "$rc"
fi

BUILD="$WORK/build"
mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -f Makefile ]; then
    echo "Configuring..."
    $ARCH "$WINE/configure" --enable-win64 --disable-tests --without-x --without-freetype \
        CC=/usr/bin/clang CXX=/usr/bin/clang++ >"$WORK/configure.log" 2>&1 \
        || die "configure failed. See $WORK/configure.log"
fi
echo "Building wow64win.dll (this can take a while)..."
$ARCH /usr/bin/make -j"$(sysctl -n hw.ncpu)" dlls/wow64win/x86_64-windows/wow64win.dll >"$WORK/make.log" 2>&1 \
    || die "The build failed. See $WORK/make.log"

BUILT="$BUILD/dlls/wow64win/x86_64-windows/wow64win.dll"
[ -f "$BUILT" ] || die "The build finished but $BUILT is missing."
cd - >/dev/null
cp "$BUILT" "$OUT"
SUM=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
grep -q " $OUT\$" SHA256SUMS 2>/dev/null || echo "$SUM  $OUT" >> SHA256SUMS

echo
echo "Built: $OUT"
echo "SHA-256: $SUM (added to SHA256SUMS)"
echo "Now run: bash install.sh"
