# Dipstick

A menu bar app that shows [mrk](https://github.com/sevmorris/mrk)'s daily
dashboard. It shows what this Mac holds that mrk has not recorded, what is
behind, Time Machine, and the installation. The panels are the ones `mrk-status`
shows in a terminal. Dipstick is a second way to read them.

The icon shows the worst result:

| Icon | Meaning |
|---|---|
| ✓ circle | Every check passes |
| ⚠ triangle | At least one warning |
| ✗ octagon | At least one error |
| ? circle | `mrk-status` did not run, or gave no report |

Click the icon to open the window. Under the verdict, the window lists each
warning and error, under the name of its panel, with its detail lines and its
fix. Below that are the four panels, closed. Click a panel to see all its
lines. When the list is taller than the window can be, it scrolls.

Each fix is a button that shows the command it runs. Click it and confirm,
and the command runs in `~/mrk`, the same way the `f` key does in
`mrk-status`, in Dipstick's console: a window with a phosphor screen and a
terminal of Dipstick's own. You type in the console to answer what the command
asks, such as `mrk-push`'s commit message or `sudo`'s password. ⌃C or ⌘. stops
the command. When it ends, Dipstick runs `mrk-status` again.

Three fixes draw a full-screen picker, which the console cannot show:
`make sync ARGS=-c`, `make sync-login-items ARGS=-c` and `make brew`. They open
a terminal instead, and so does the mrk-menu button.

## Install

Download the DMG from the
[latest release](https://github.com/sevmorris/Dipstick/releases/latest), open
it, and drag Dipstick to Applications. It is signed with a Developer ID and
notarized by Apple. To start it at login, add it in System Settings → General →
Login Items.

## How it works

Dipstick does no checks of its own. It runs `mrk-status --json` and shows the
result, so the dashboard and the menu bar always agree.

- **When.** At launch, every 30 minutes, when you open the menu and the last
  report is older than two minutes, and when you click ↻.
- **Environment.** An app that starts at login gets a short PATH, with no
  Homebrew and no `~/bin`. Dipstick asks an interactive login zsh for its
  environment, so `mrk-status` runs with the PATH that a new terminal window
  has. ↻ asks the shell again.
- **Which mrk-status.** The first one found:
  `$DIPSTICK_MRK_STATUS`, then `$MRK_ROOT/bin/mrk-status`, then
  `~/bin/mrk-status`, then `~/mrk/bin/mrk-status`.
- **Fixes.** The console runs the command with zsh in the checkout, on a
  pseudo-terminal of its own, with the login shell's environment and
  `MRK_ROOT`. It is a dumb terminal (`TERM=dumb`, 80 columns): it shows colour,
  progress counters that write over their line, and what you type, and
  `PAGER` and `GIT_PAGER` are `cat`. The console takes one fix at a time. While
  a fix runs, its window does not close and Dipstick does not quit, so a fix
  cannot be cut off between a commit and its push. If the window goes behind
  another app's, the menu under the icon names the fix, with a Show button.
  The screen can be Phosphor Green, Phosphor Amber or Plain. The button at
  the top right of the console sets it.
- **Fixes in a terminal.** For the full-screen fixes, Dipstick writes the
  command into a `.command` file and opens it. That starts the command in the
  app that opens `.command` files (Terminal, unless another terminal has
  claimed them). The file deletes itself when it runs.
- **Privacy.** A fix in the console runs as Dipstick's child, so macOS asks
  about Dipstick, not Terminal. `make update` asks System Events to remove the
  login items mrk keeps off, so the first time it runs, macOS asks whether
  Dipstick may control System Events. `brew upgrade` replaces apps in
  /Applications, which may need App Management for Dipstick in System
  Settings → Privacy & Security. `make snapshot-prefs` and `make defaults` may
  need access to other apps' data, as they do in Gearbox.
- **Updates.** Check for Updates… in the window's footer asks GitHub for a
  newer Dipstick. Dipstick also asks at launch and once a day without telling
  you, and when a newer version is out, the footer names it in place of the
  button. A version that needs a newer macOS than this Mac has is not offered.

Dipstick stores one setting: the console's screen, as `consoleStyle` in its
defaults domain, `io.github.sevmorris.Dipstick`. AppKit keeps the menu bar
icon's position in the same domain, as it does for any menu bar item. Apart
from that, Dipstick writes nothing but the `.command` files. The update check
is its one network request.

## Requirements

- macOS 15 or later, on Apple silicon.
- mrk, with an `mrk-status` that has `--json`: mrk from 2026-10-18 on
  ([sevmorris/mrk#104](https://github.com/sevmorris/mrk/pull/104)). With an
  older mrk, Dipstick says so and offers `make pull`.

## Build

```bash
./build.sh            # builds build/Dipstick.app, signed ad hoc
open build/Dipstick.app
swift test            # the tests
```

To try a different mrk-status, run the binary inside the bundle with
the variable set:

```bash
DIPSTICK_MRK_STATUS=/path/to/mrk-status build/Dipstick.app/Contents/MacOS/Dipstick
```

To write the window to a PNG, use `--snapshot`. Dipstick runs one refresh,
opens the window under its icon as a click does, and saves the image. Then it
runs `make help` in the console, which lists mrk's Make targets and changes
nothing, saves the console's window beside the first image with `-console`
added to its name, and quits. The images are of the windows themselves, and
Dipstick prints their sizes in points. The console's screen is Phosphor
Green, whatever `consoleStyle` says, and Dipstick puts back any key the run
wrote in its defaults domain:

```bash
build/Dipstick.app/Contents/MacOS/Dipstick --snapshot ~/Desktop/dipstick.png
```

The icon is drawn by `tools/icon/make-appicon.py`, which writes
`assets/AppIcon.icns`. `build.sh` and `release.sh` both build the bundle with
`scripts/assemble-app.sh`, so a local build and a release differ only in their
signature.

## Release

```bash
caffeinate -dis ./release.sh 0.2
```

`release.sh` runs the tests, builds, signs with the Developer ID, notarizes,
and publishes the DMG as a GitHub release. It releases from `main` only. It
needs `release-notes/v<version>.md`, with the same prose as that version's entry
in [CHANGELOG.md](CHANGELOG.md), the `notarytool` keychain profile, and a
`python3` with `dmgbuild`. Its preflight checks each one before it builds
anything.

`tools/dmg/` and `scripts/check-shared.sh` are shared verbatim with the sibling
apps, and `release.sh` stops when they differ. Change them in every repository
at once.

## License

MIT — Seven Morris
