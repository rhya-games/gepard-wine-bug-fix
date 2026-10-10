# Optional extras that work for any game

(The save-data backup, last on this page, is not optional: it runs by itself before the extras that
change your files.)

None of these are needed for the fix, and each can be undone. They are all run by
`bash install.sh extras` (together with the extras in [uaRO](uaro.md)). Back to the [README](../README.md).

## Optional: fitting the game window (how it works)

`bash install.sh window` is an optional extra. It edits `savedata/OptionInfo.lua` in the
game folder (found by searching the CrossOver bottles; it asks if there is more than one):

1. Asks macOS for the primary screen's usable area (`NSScreen.visibleFrame`: the screen
   minus the menu bar and the Dock) and the menu bar height.
2. Sets `ISFULLSCREENMODE = 0` (windowed), `WIDTH`/`OLD_WIDTH` to the usable width,
   `HEIGHT`/`OLD_HEIGHT` to the usable height minus a 28 px title bar,
   and `Window_XPos`/`Window_YPos` to the top-left of the usable area.
3. Makes a one-time backup (`OptionInfo.lua.before-window-fit.backup`); `window undo`
   restores it.

It refuses to run while the game is open, because the game rewrites this file when it exits.
Example on a 1728 x 1117 (points) MacBook screen with the Dock at the bottom: usable area
1728 x 984, so the game area is 1728 x 956 at (0, 33), and the measured window frame was
1728 x 984 at (0, 33). The 28 px title bar was measured on that one setup. Wine only hides
the menu bar when a window covers the whole screen, so this does not hide it; it just
removes the guesswork about size.

## Optional: Mac keyboard settings (how it works)

`bash install.sh keys on` writes these values to `HKCU\Software\Wine\Mac Driver` in
the chosen bottle (through `wine reg add`), and `keys off` deletes exactly those values:

| value | set to | what Wine's Mac driver does |
|---|---|---|
| `LeftCommandIsCtrl` | `N` | left Command stays a Mac Command key (default: Wine sends Alt to the game) |
| `RightCommandIsCtrl` | `N` | right Command stays a Mac Command key, so Mac shortcuts such as the screenshot keys keep working |
| `LeftOptionIsAlt` | `Y` | left Option sends Alt (default: sends nothing) |
| `RightOptionIsAlt` | `Y` | right Option sends Alt (default: sends nothing) |
| `CaptureDisplaysForFullscreen` | `N` | do not capture the display for full screen (this is Wine's default, written explicitly) |

Why Command is left alone: Wine already sends a bare Command key to the game as Alt
(`kVK_Command` maps to `VK_LMENU` in `keyboard.c`), and the game's menu shortcuts are
Alt+letter, so Option is made Alt as well. Wine and CrossOver also add a hidden Edit menu
(`EditMenu` option) so Cmd+C and Cmd+V still paste as Ctrl+C / Ctrl+V. Mapping Command to
Ctrl (`LeftCommandIsCtrl` / `RightCommandIsCtrl`) only changes how an already-delivered
Command press is translated and gets in the way of Mac shortcuts, so this bundle sets
those to `N`. The Mac Control key already maps to Left/Right Ctrl by default.

The value names were checked against Wine's `dlls/winemac.drv/macdrv_main.c` and the
default key table in `keyboard.c`. The driver reads the values when the bottle starts, so
CrossOver must be restarted. For full screen, see "Known failure" below. `keys off` restores Wine's defaults,
not any custom values you had set for these names beforehand.

## Optional: CrossOver launcher icons (how it works)

`bash install.sh launchers` (also run by `extras`) adds entries to the bottle's program list in
CrossOver, next to the patcher's own entry:

| icon | program | notes |
|---|---|---|
| UaRO Game | `uaRO.exe` | the game itself, not the patcher; started without arguments |
| UaRO Setup | `setup.exe` | the graphics and sound setup |
| AzzyAI Config | `AI\USER_AI\AzzyAiConfigPreRe.exe` | only if AzzyAI is installed |

It writes a short VBScript and runs it with Wine's `wscript.exe` to create Windows `.lnk`
shortcuts in the bottle's Start Menu folder for the game (`...\Start Menu\Programs\<game
folder>\`), then runs `cxmenu --sync` so CrossOver registers them and extracts each program's
icon. Wine's script engine has no `WshShell.SpecialFolders`, so the Start Menu path is built from
the bottle's user folder instead. Entries whose program does not exist yet are skipped, and
re-running it refreshes them (for example after installing AzzyAI). `launchers remove` deletes
just these three shortcuts and syncs again. Reopen CrossOver if it was open.

Icons: the game's own `uaRO.exe` icon is only 32 pixels (blurry when scaled up) and CrossOver
left the patcher's launcher app with its generic icon. So `launchers` also builds a sharper icon
from the game's `icnbig.ico` (48 pixels, upscaled with `sips`, packed with `iconutil`), adds
48 to 512 pixel versions to the bottle's icon cache (`windata/cxmenu/icons/hicolor`) for the
Game and Patcher entries, and replaces `CrossOverHelper.icns` inside those two apps in
`~/Applications/CrossOver/<game folder>/`. The source is only 48 pixels, so it is smooth, not
detailed. If CrossOver rebuilds those apps and the old icon returns, run `launchers` again.

## Known failure: Cmd+Tab in full screen

Recorded so nobody repeats the work. Not fixed.

- **Cmd+Tab (Alt+Tab) does not work with full screen.** Tabbing away from the game and back
  gives a black screen, and the full-screen window takes over all Desktops, so you cannot
  swipe to another one either. In full screen the game window is a floating
  window (CoreGraphics window layer 3) owned by its own temporary macOS app
  (`.../winetemp-*/uaRO.exe`); in windowed mode it was a normal layer-0 window. Wine raises
  fullscreen and topmost windows to higher levels (`minimumLevelForActive:` in
  `cocoa_window.m`), and native full-screen Spaces are only offered to titled, resizable
  windows (`adjustFullScreenBehavior:`). No registry value in Wine's Mac driver changes
  this; CrossOver's `winemac.so` has the same option set as upstream plus `EditMenu`.
  Under CrossOver each game run is also a separate temporary macOS app with no bundle id,
  so the Dock "Assign To" setting cannot persist. The black screen matches exclusive
  full-screen behaviour.
- **Keys:** if a Command, Option or screenshot key does something unexpected,
  `bash install.sh keys off` returns Wine to its defaults.
- **Untested workaround:** play in windowed mode (not full screen) and drag the window to its
  own Desktop in Mission Control.

## Save-data backup (how it works)

`bash install.sh backup` copies the game's `savedata/` folder (character settings, hotkeys and the
option files; it cannot be downloaded again) to
`~/Documents/RO Backups/<game folder>/savedata-<date>-<time>`. Set `RO_BACKUP_DIR` to use another
place. The newest 10 are kept for each game; older ones are deleted.

- `bash install.sh backup list` shows what you have.
- `bash install.sh backup restore` puts back the newest manual backup. It asks first, refuses while
  the game is running, and keeps a `before-restore-...` copy of what it replaced. Files that were
  added after the backup are left in place, because it copies over the top.
- Before the window fit and before installing AzzyAI, a `before-change-...` copy is made
  automatically and printed as one line.
