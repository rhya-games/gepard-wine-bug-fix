#!/bin/bash
# Smoke tests for install.sh. They run against a fake CrossOver and a fake game folder in a
# temporary directory, with a stand-in `wine`, so nothing on the real Mac is touched.
#
#   bash tests/smoke.sh
#
# macOS only (uses osascript, iconutil-free paths only). Exit code 0 = all passed.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
: > /dev/null
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }
check() { # name, condition result (0 = pass)
    if [ "$2" = 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi
}

# ---- fake CrossOver ----------------------------------------------------------------------
APP="$T/CrossOver.app"
DLLDIR="$APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
mkdir -p "$DLLDIR" "$APP/Contents/SharedSupport/CrossOver/bin"
echo stock > "$DLLDIR/wow64win.dll"
set_version() {
    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>26.3</string><key>CFBundleVersion</key><string>$1</string></dict></plist>
EOF
}
set_version 26.3.0.39832

# stand-in wine: logs calls, emulates `reg add/delete/query` and the probe's output
STORE="$T/reg.txt"; : > "$STORE"
cat > "$APP/Contents/SharedSupport/CrossOver/bin/wine" <<EOF
#!/bin/bash
args="\$*"
case "\$args" in
  *"reg add"*)    n=\$(echo "\$args" | sed 's/.*\/v \([^ ]*\) .*\/d \([^ ]*\).*/\1/'); v=\$(echo "\$args" | sed 's/.*\/d \([^ ]*\).*/\1/'); grep -v "^\$n=" "$STORE" > "$STORE.n"; echo "\$n=\$v" >> "$STORE.n"; mv "$STORE.n" "$STORE" ;;
  *"reg delete"*) n=\$(echo "\$args" | sed 's/.*\/v \([^ ]*\) .*/\1/'); grep -v "^\$n=" "$STORE" > "$STORE.n"; mv "$STORE.n" "$STORE" ;;
  *"reg query"*)  n=\$(echo "\$args" | sed 's/.*\/v \([^ ]*\).*/\1/'); l=\$(grep "^\$n=" "$STORE"); [ -n "\$l" ] && printf '    %s    REG_SZ    %s\r\n' "\${l%%=*}" "\${l#*=}" ;;
  *rawinput_overflow_probe*) echo "fill    : ret=2  count_out=240  capacity_in=240"; if [ "\$(cat "$T/affected" 2>/dev/null)" = yes ]; then echo "entries clobbered past the returned count : 238"; echo "AFFECTED=yes"; else echo "entries clobbered past the returned count : 0"; echo "AFFECTED=no"; fi ;;
esac
exit 0
EOF
chmod +x "$APP/Contents/SharedSupport/CrossOver/bin/wine"

# shim dir: CrossOver "not running", no real wscript/cxmenu side effects
SHIM="$T/shim"; mkdir -p "$SHIM"
printf '#!/bin/bash\nexit 1\n' > "$SHIM/pgrep"; chmod +x "$SHIM/pgrep"
printf '#!/bin/bash\necho "$*" >> "%s/open.log"\n' "$T" > "$SHIM/open"; chmod +x "$SHIM/open"

# stand-in processes: start NAME -> pid in $SP; stop kills it
start() { ( exec -a "$1" sleep 40 ) & SP=$!; disown "$SP" 2>/dev/null; sleep 1; }
stop() { kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null; }

# ---- fake home with a game folder ---------------------------------------------------------
H="$T/home"
BOT="$H/Library/Application Support/CrossOver/Bottles/b"
GAME="$BOT/drive_c/users/crossover/AppData/Local/Programs/Fake RO"
mkdir -p "$GAME/AI/USER_AI" "$GAME/savedata"
touch "$GAME/data.grf" "$GAME/uaRO.exe" "$GAME/setup.exe"
echo orig > "$GAME/AI/AI.lua"
printf 'CmdOnOffList["/hoai"] = 0\r\nCmdOnOffList["/merai"] = 0\r\nOptionInfoList["ISFULLSCREENMODE"] = 1\r\nOptionInfoList["WIDTH"] = 800\r\nOptionInfoList["HEIGHT"] = 600\r\nOptionInfoList["OLD_WIDTH"] = 800\r\nOptionInfoList["OLD_HEIGHT"] = 600\r\nOptionInfoList["Window_XPos"] = 5\r\nOptionInfoList["Window_YPos"] = 5\r\n' > "$GAME/savedata/OptionInfo.lua"
# a tiny stand-in for the AzzyAI release zip
mkdir -p "$T/azzy/AI/USER_AI"; echo x > "$T/azzy/AI/AI.lua"; echo x > "$T/azzy/AI/USER_AI/AI_main.lua"
( cd "$T/azzy" && /usr/bin/zip -qr "$T/azzy.zip" AI )

run() { ( cd "$ROOT" && CX_APP="$APP" HOME="$H" PATH="$SHIM:$PATH" AZZYAI_ZIP="$T/azzy.zip" bash install.sh "$@" </dev/null 2>&1 ); }
run_nohome() { ( cd "$ROOT" && CX_APP="$APP" HOME="$T/empty" PATH="$SHIM:$PATH" bash install.sh "$@" </dev/null 2>&1 ); }
mkdir -p "$T/empty"

echo "install / uninstall"
out=$(run_nohome); check "refuses when no game is installed" "$([[ $out == *"does not seem to be installed"* ]] && echo 0 || echo 1)"
PREBUILT="$ROOT/fix/wow64win.dll.crossover-26.3.0"; [ -f "$PREBUILT" ] || PREBUILT="$ROOT/wow64win.dll.crossover-26.3.0"
out=$(run -y); check "installs the ready-made DLL" "$(cmp -s "$PREBUILT" "$DLLDIR/wow64win.dll" && echo 0 || echo 1)" "$out"
check "keeps a versioned backup" "$([ -f "$DLLDIR/wow64win.dll.orig-26.3.0" ] && echo 0 || echo 1)"
out=$(run); check "second run says already installed" "$([[ $out == *"already installed"* ]] && echo 0 || echo 1)"
check "ends with the automatic check" "$([[ $out == *"RESULT"* ]] && echo 0 || echo 1)" "$out"
out=$(run uninstall); check "uninstall restores the original" "$([ "$(cat "$DLLDIR/wow64win.dll")" = stock ] && echo 0 || echo 1)" "$out"
set_version 27.0.0.1; echo yes > "$T/affected"; out=$(run); check "unknown version points to build-dll.sh" "$([[ $out == *"build-dll.sh 27.0.0"* ]] && echo 0 || echo 1)" "$out"
set_version 26.3.0.39832; echo no > "$T/affected"

echo "leftover processes"
start 'C:\windows\system32\leftover.exe'
out=$(run -y); check "stops leftover bottle processes" "$([[ $out == *"Stopping leftover"* ]] && echo 0 || echo 1)"
echo stock > "$DLLDIR/wow64win.dll"; run uninstall >/dev/null

echo "keyboard settings"
run keys on >/dev/null; out=$(run keys status)
check "keys on writes the values" "$([[ $out == *"LeftOptionIsAlt"*"Y"* && $out == *"LeftCommandIsCtrl"*"N"* ]] && echo 0 || echo 1)" "$out"
run keys off >/dev/null; out=$(run keys status)
check "keys off removes them" "$([[ $out == *"not set"* ]] && echo 0 || echo 1)" "$out"

echo "window fit"
out=$(run window); check "window fit succeeds" "$([[ $out == *"Window fitted"* ]] && echo 0 || echo 1)" "$out"
check "windowed mode set" "$(grep -q 'ISFULLSCREENMODE"\] = 0' "$GAME/savedata/OptionInfo.lua" && echo 0 || echo 1)"
out=$(run window undo); check "window undo restores" "$(grep -q 'WIDTH"\] = 800' "$GAME/savedata/OptionInfo.lua" && echo 0 || echo 1)" "$out"
start 'C:\users\crossover\AppData\Local\Programs\Fake RO\x.exe'
out=$(run window); check "window fit refuses while the game runs" "$([[ $out == *"game is running"* ]] && echo 0 || echo 1)" "$out"
stop

echo "AzzyAI"
out=$(run -y azzyai); check "azzyai installs from a local zip" "$([ -f "$GAME/AI/.azzyai-release" ] && echo 0 || echo 1)" "$out"
check "original AI folder kept" "$([ -d "$GAME/AI-BEFORE-AZZYAI" ] && echo 0 || echo 1)"
check "/hoai and /merai switched on" "$([ "$(grep -c '= 1' "$GAME/savedata/OptionInfo.lua")" -ge 2 ] && echo 0 || echo 1)"
out=$(run azzyai undo); check "azzyai undo restores the original" "$([ "$(cat "$GAME/AI/AI.lua")" = orig ] && echo 0 || echo 1)" "$out"

echo "play"
out=$(PLAY_DRY_RUN=1 run play); check "play dry run works" "$([[ $out == *"dry run"* || $out == *"Starting"* ]] && echo 0 || echo 1)" "$out"
start 'C:\users\crossover\AppData\Local\Programs\Fake RO\x.exe'
out=$(run play); check "play notices the game is running" "$([[ $out == *"already running"* ]] && echo 0 || echo 1)" "$out"
stop

echo "graphics warning"
mkdir -p "$T/gfx"; printf '[EnvironmentVariables]\n"CX_GRAPHICS_BACKEND" = "dxvk"\n' > "$T/gfx/cxbottle.conf"
fn=$(sed -n '/^check_graphics() {/,/^}/p' "$ROOT"/install.sh "$ROOT"/lib/*.sh 2>/dev/null)
out=$( eval "$fn"; check_graphics "$T/gfx" ); check "detects a DXVK setting" "$([[ $out == *"NOTE"* ]] && echo 0 || echo 1)"
rm "$T/gfx/cxbottle.conf"; out=$( eval "$fn"; check_graphics "$T/gfx" ); check "quiet when settings are default" "$([ -z "$out" ] && echo 0 || echo 1)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" = 0 ]
