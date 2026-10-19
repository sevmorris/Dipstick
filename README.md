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

Click the icon to open the panels. A panel with a warning or an error opens by
itself. Each fix is a button that shows the command it runs. The button opens a
terminal and runs the command in `~/mrk`, the same way the `f` key does in
`mrk-status`. Most fixes need a terminal: `make sync ARGS=-c` opens the picker,
and `sudo` asks for a password.

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
- **Fixes.** Dipstick writes the command into a `.command` file and opens it.
  That starts the command in the app that opens `.command` files (Terminal,
  unless another terminal has claimed them). The file deletes itself when it
  runs. Dipstick needs no Automation permission.
- **Updates.** Check for Updates… in the window's footer asks GitHub for a
  newer Dipstick. Dipstick also asks at launch and once a day without telling
  you, and when a newer version is out, the footer names it in place of the
  button. A version that needs a newer macOS than this Mac has is not offered.

Dipstick stores no settings of its own. AppKit keeps the menu bar icon's
position in Dipstick's defaults domain, `io.github.sevmorris.Dipstick`, as it
does for any menu bar item. Apart from that, Dipstick writes nothing but the
`.command` files. The update check is its one network request.

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

To see the window without opening the menu bar, write it to a PNG.
Dipstick runs one refresh, saves the image, and quits:

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
