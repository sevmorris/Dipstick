# Dipstick

A menu bar app for [mrk](https://github.com/sevmorris/mrk), this Mac's setup
repository. Its menu bar window shows mrk's daily dashboard: what this Mac
holds that mrk has not recorded, what is behind, Time Machine, and the
installation. The panels are the ones `mrk-status` shows in a terminal.
Dipstick is a second way to read them. Its second window, mrk Settings, shows
mrk's lists in `config/`: app preferences, macOS defaults, login items and the
Dock. mrk Settings was Gearbox, an app of its own, until Dipstick took it in.

**The rule:** Dipstick runs mrk's own scripts through their check modes and
decision options, and never does their work itself. When it needs an interface
mrk lacks, the interface goes into mrk first, with its tests and its entry in
BIN-1 (`docs/bin/mrk-usage.html`).

## The menu bar window

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

Each fix is a button. Most show the command they run. Click one and confirm,
and the command runs in `~/mrk`, the same way the `f` key does in
`mrk-status`, in Dipstick's console (see [The console](#the-console)). When it
ends, Dipstick runs `mrk-status` again.

Some fixes have a pane in mrk Settings that does the same work. Their buttons
name the pane, and a click opens it. The pane shows what the fix would change,
and runs nothing until you ask:

| Fix | Pane |
|---|---|
| `make snapshot-prefs` | App Preferences |
| `make sync-login-items ARGS=-c` | Login Items |
| `make defaults`, `make trackpad` | macOS Defaults |
| `make dock` | Dock |

Three things draw a full-screen picker, which the console cannot show:
`make sync ARGS=-c`, `make brew` and the mrk-menu button. They open a terminal.

**Settings…** opens mrk Settings at the pane it showed last.

## mrk Settings

| Pane | What it reads | What it changes |
|---|---|---|
| App Preferences | `snapshot-prefs --check`, grouped by the apps of `config/app-prefs.tsv` | **Snapshot…** runs `make snapshot-prefs` in the console, where its secret scan can stop and ask |
| macOS Defaults | `defaults.sh --check [--with-trackpad]`, with each key's section and `when` from `config/defaults.tsv` and its description from `docs/defaults/descriptions.tsv` | Each key's switch turns it off with `defaults.sh --skip` and `--revert`, and on with `--unskip` and `--key`, for every domain of the setting. **Apply This Key** runs `--key` for a key that differs or is absent. **Apply All…** runs `make defaults` (or `make trackpad`) in the console, after a confirmation that names the restart of Finder, the Dock and SystemUIServer |
| Login Items | `config/login-items.txt` and `sync-login-items --check` | **Add**, **Ignore** and **Remove** run `sync-login-items --add`, `--ignore` and `--remove` |
| Dock | `config/dock.txt` and `dock-setup --check` | Reordering, adding and removing write `config/dock.txt`, the plain list `dock-setup` reads. **Apply…** runs `make dock` in the console, after a confirmation |

**A key that is off** is one that `config/defaults-skip.tsv` lists:
`make defaults` leaves it as it is, and `defaults.sh --check` calls it
`skipped`. Turning a key off puts back the value it had before mrk wrote it,
from its line in `~/.mrk/defaults-rollback.sh`. A key that mrk never changed on
this Mac stays as it is. Turning a key on writes mrk's value. Either way,
`defaults.sh` restarts Finder, the Dock and the menu bar when it changed a
key. The switch of a setting that mrk writes to two domains, as it writes the
trackpad keys, turns both.

Dipstick reads the `--check` lines by the contract that BIN-1 states for all
five check modes ([sevmorris/mrk#122](https://github.com/sevmorris/mrk/pull/122)):
fields split at each tab, each with `\t`, `\n` and `\\` undone by Unicode
scalar, and a line taken when it has at least the fields Dipstick knows,
because a later mrk can add more at the end. A line with a word that Dipstick
does not know is passed over. When a check prints lines and Dipstick reads none
of them, the pane says that this Dipstick is older than mrk's output. It does
not show an empty list.

Before a pane runs a script, Dipstick reads the checkout's
`scripts/mrk-contract`, which lists the options that each script takes. It
reads it once for each checkout, and again when the file changes. When a
script does not take an option that Dipstick passes, the pane runs nothing and
says that this mrk is older than Dipstick, with `make pull`, or, when the
contract is a later version than Dipstick reads, that this Dipstick is older.
A script that takes the option and exits 2 refuses the command line, and the
pane shows mrk's own reason. With an mrk from before `mrk-contract`, a script
that exits 2 and names an option Dipstick passes as unknown is an mrk older
than Dipstick. Any other refusal shows mrk's own reason.

**Dipstick never commits by itself.** The panes change files in the mrk
checkout: `config/dock.txt`; the login-items list, through
`sync-login-items`; and the skip list, through `defaults.sh`. Committing stays
with `mrk-push` and `pushall`, with their secret scan and gates, and the
Unrecorded panel shows what is waiting. Barkeep works the same way. After each
change, Dipstick runs `mrk-status` again.

While mrk Settings or the console is open, Dipstick has a Dock icon and a menu
bar: **Check for Updates…** and **mrk Settings…** (⌘,) in the Dipstick menu,
and **Refresh** (⌘R) in the View menu. When both windows close, only the menu
bar icon is left. Opening Dipstick from Finder or Spotlight while it runs opens
mrk Settings.

## The console

A command that changes the Mac or pushes runs in Dipstick's console: a window
with a phosphor screen like Magic Backup Machine's, over a terminal of
Dipstick's own. The fixes of the menu bar window and the commands of the panes
use the same console, one command at a time. Dipstick runs the command with zsh
in the checkout, with the login shell's environment and `MRK_ROOT`. You type in
the console to answer what the command asks, such as `mrk-push`'s commit
message, snapshot-prefs's secret scan or `sudo`'s password, and press Return.
⌃C or ⌘. stops the command: Stop sends ⌃C, then SIGTERM, then SIGKILL. When
the command exits, Dipstick reads the pane on screen again and runs
`mrk-status` again.

The terminal is a dumb one, 80 columns wide, and says so (`TERM=dumb`). It
shows text, a program's colours and weights, and a line that writes over
itself, as git's progress does. It has no full screen, and `PAGER` and
`GIT_PAGER` are `cat`.

While a command runs, the console's window does not close and Dipstick does not
quit, so a command cannot be cut off between a commit and its push. The fix
buttons that use the console wait, the panes wait under a banner that names
the command, and the menu bar window names it with a Show button.

The display button over the screen picks Phosphor Green, Phosphor Amber or
Plain. A phosphor has one colour, so a program's red and green show in it, and
bold glows brighter and dim fainter. Plain shows the colours.

## How it works

Dipstick does no checks of its own. It runs `mrk-status --json` and mrk's
check modes and shows the result, so the app and the terminal always agree.

- **When.** `mrk-status` runs at launch, every 30 minutes, when you open the
  menu and the last report is older than two minutes, when you click ↻, and
  after each command and pane change. A pane reads mrk when mrk Settings opens
  it, after each of its changes, and when you click its ↻.
- **Environment.** An app that starts at login gets a short PATH, with no
  Homebrew and no `~/bin`. Dipstick asks an interactive login zsh for its
  environment, so mrk's scripts run with the PATH that a new terminal window
  has. ↻ in the menu bar window asks the shell again.
- **Which checkout.** `$MRK_ROOT` as the login shell sets it, or `~/mrk`.
- **Which mrk-status.** The first one found:
  `$DIPSTICK_MRK_STATUS`, then `$MRK_ROOT/bin/mrk-status`, then
  `~/bin/mrk-status`, then `~/mrk/bin/mrk-status`.
- **Fixes in a terminal.** For the full-screen fixes, Dipstick writes the
  command into a `.command` file and opens it. That starts the command in the
  app that opens `.command` files (Terminal, unless another terminal has
  claimed them). The file deletes itself when it runs. A full-screen fix is
  one that starts `mrk-menu`, `mrk-picker` or `gum`, or one whose Make target
  the checkout's `scripts/mrk-contract` lists under `terminal`. For an mrk
  with no such list, the targets are `sync`, `sync-login-items` and `brew`.
- **Updates.** Check for Updates… asks GitHub for a newer Dipstick. Dipstick
  also asks at launch and once a day without telling you, and when a newer
  version is out, the menu bar window's footer and mrk Settings' sidebar name
  it. A version that needs a newer macOS than this Mac has is not offered.

### Privacy

Dipstick runs mrk's scripts and the console's commands as its own children, so
macOS asks about Dipstick, not Terminal.

- **Automation.** `sync-login-items` reads the login items from System Events,
  and `make update` removes the login items mrk keeps off through System
  Events. The first time, macOS asks whether Dipstick may control System
  Events. If you decline, the Login Items pane says how to give access in
  System Settings → Privacy & Security → Automation.
- **Full Disk Access.** Mail keeps its settings in a container that macOS lets
  an app read only with Full Disk Access. TextEdit and Passwords keep theirs
  where an app also needs permission to get the data of other apps. Without
  those permissions, `defaults.sh --check` cannot read those keys, and reports
  them as `noaccess` ([sevmorris/mrk#131](https://github.com/sevmorris/mrk/pull/131)).
  The Defaults pane shows each with a lock and **Open Full Disk Access…**.
  macOS has no prompt for this permission: turn Dipstick on in System Settings
  → Privacy & Security → Full Disk Access, and let macOS quit and reopen it.
- **App Management.** `brew upgrade` replaces apps in /Applications, which can
  need App Management for Dipstick.

### What Dipstick stores

Dipstick keeps four values in its defaults domain, `io.github.sevmorris.Dipstick`:
the console's screen (`consoleStyle`), the pane mrk Settings shows
(`selectedPane`), and the Defaults pane's trackpad switch and filter
(`defaultsWithTrackpad`, `defaultsFilter`). AppKit keeps the menu bar icon's
position in the same domain, as it does for any menu bar item. The windows
remember no frame. Apart from that, Dipstick writes the `.command` files and
`config/dock.txt`. The update check is its one network request.

## Install

Download the DMG from the
[latest release](https://github.com/sevmorris/Dipstick/releases/latest), open
it, and drag Dipstick to Applications. It is signed with a Developer ID and
notarized by Apple. To start it at login, add it in System Settings → General →
Login Items. mrk's Phase 3 does both.

## Requirements

- macOS 15 or later, on Apple silicon.
- mrk, with an `mrk-status` that has `--json`: mrk from 2026-10-18 on
  ([sevmorris/mrk#104](https://github.com/sevmorris/mrk/pull/104)). With an
  older mrk, Dipstick says so and offers `make pull`.
- For all of mrk Settings, mrk from 2026-10-23 on
  ([sevmorris/mrk#131](https://github.com/sevmorris/mrk/pull/131)). Against an
  older mrk, a pane says what it cannot read and to run `make pull`, and the
  other panes still work.
- For the files that App Preferences shows as **not read**, and a login item
  whose name starts with a dash, mrk from 2026-10-28 on
  ([sevmorris/mrk#135](https://github.com/sevmorris/mrk/pull/135)).
- For a pane to tell an option mrk lacks from a value mrk refuses before it
  runs anything, mrk from 2026-10-29 on, with `scripts/mrk-contract`
  ([sevmorris/mrk#140](https://github.com/sevmorris/mrk/pull/140)). An older mrk works as before.

## Build, test, look

```bash
./build.sh            # builds build/Dipstick.app, signed ad hoc
open build/Dipstick.app
swift test            # the tests
```

No test runs a real mrk command, touches real defaults or asks GitHub. The
scripts and `mrk-status` are stubs in a temporary folder. The console's tests
run zsh and make on a pseudo-terminal against a stub Makefile there. The app's
settings go through `UserDefaults.app`, a scratch suite under tests, named by a
path in the temporary folder.

To try a different mrk-status or checkout, run the binary inside the bundle
with the variables set:

```bash
MRK_ROOT=/path/to/mrk DIPSTICK_MRK_STATUS=/path/to/mrk-status build/Dipstick.app/Contents/MacOS/Dipstick
```

To draw every window into PNGs, use `--snapshot` with a folder:

```bash
build/Dipstick.app/Contents/MacOS/Dipstick --snapshot /tmp/dipstick-shots
```

Dipstick runs one refresh, opens the window under its icon as a click does,
and saves it as `1-status.png`. Then it opens mrk Settings, loads each pane
against the real checkout, and saves `2-preferences.png` to `5-dock.png`. Last,
it runs `make help` in the console, which lists mrk's Make targets and changes
nothing, saves `6-console.png`, and quits. It runs only the read-only check
modes. The images are of the windows themselves, and Dipstick prints their
sizes in points. The console's screen is Phosphor Green, whatever
`consoleStyle` says, and Dipstick puts back any key the run wrote in its
defaults domain, which `snapshot-prefs` exports with every
`io.github.sevmorris.*` domain.

An ad hoc signature changes with every build, and macOS keys the Automation
permission to it, so a rebuilt Dipstick asks again.

The icon is drawn by `tools/icon/make-appicon.py`, which writes
`assets/AppIcon.icns`. `build.sh` and `release.sh` both build the bundle with
`scripts/assemble-app.sh`, so a local build and a release differ only in their
signature.

## Release

```bash
caffeinate -dis ./release.sh 0.4
```

`release.sh` runs the tests, builds, signs with the Developer ID, notarizes,
and publishes the DMG as a GitHub release. It releases from `main` only. It
needs `release-notes/v<version>.md`, with the same prose as that version's entry
in [CHANGELOG.md](CHANGELOG.md), the `notarytool` keychain profile, and a
`python3` with `dmgbuild`. Its preflight checks each one before it builds
anything.

The release is signed with the hardened runtime, which refuses Apple events
from an app without the `com.apple.security.automation.apple-events`
entitlement, and does not ask. `Dipstick.entitlements` has it, for the Login
Items pane and `make update`. `release.sh` stops when the signature lacks the
entitlement, or the bundle lacks `NSAppleEventsUsageDescription`. An ad hoc
build from `build.sh` has no hardened runtime, so it cannot show this fault.

`tools/dmg/` and `scripts/check-shared.sh` are shared verbatim with the sibling
apps, and `Sources/Dipstick/MrkText.swift` and `ShellEnvironment.swift` with
Barkeep, and `release.sh` stops when they differ. Change them in every
repository at once.

## License

MIT — Seven Morris
