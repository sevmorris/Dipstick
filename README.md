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

Dipstick keeps no settings and writes nothing but the `.command` files.

## Requirements

- macOS 15 or later.
- mrk, with an `mrk-status` that has `--json`
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

There are no releases yet, and no `release.sh`.

## License

MIT — Seven Morris
