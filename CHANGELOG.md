# Changelog

All notable changes to Dipstick are documented here. Every released version has a matching `v*` git tag. `release.sh` keeps the five most recent GitHub release pages, so an older version is reachable by its tag after its page is pruned.

Write a version's entry before releasing it, and put the same prose in `release-notes/v<version>.md`: `release.sh` publishes that file as the release's notes, and stops before building anything when it is absent.

## [0.4] — 2026-10-24

**Added**
- **mrk Settings: Gearbox's four panes, in Dipstick.** A second window shows mrk's lists in `config/`: App Preferences (`snapshot-prefs --check`), macOS Defaults (`defaults.sh --check`, with a switch for each key), Login Items (`sync-login-items --check`, with Add, Ignore and Remove) and Dock (`config/dock.txt` and `dock-setup --check`). They are Gearbox's panes as Gearbox 0.5 had them, and they read mrk by the same `--check` line contract. **Settings…** in the menu bar window opens it, and so does opening Dipstick from Finder or Spotlight while it runs. Dipstick still never commits by itself: the Unrecorded panel then offers `mrk-push`.
- **A fix that a pane makes opens the pane.** `make snapshot-prefs` opens App Preferences, `make sync-login-items ARGS=-c` opens Login Items, and `make defaults` and `make trackpad` open macOS Defaults. The pane shows what the fix would change, and runs nothing until you ask. `make sync-login-items ARGS=-c` no longer opens a terminal for `gum`.
- **A Dock icon and a menu bar while a window is open.** While mrk Settings or the console is open, Dipstick is in the Dock and in ⌘-Tab, with **Check for Updates…**, **mrk Settings…** (⌘,) and **Refresh** (⌘R) in its menus. When both windows close, only the menu bar icon is left.

**Changed**
- **One console for the menu bar window and the panes.** A pane's Snapshot…, Apply All… and Apply… run in the console window that the fixes use, one command at a time. While a command runs, the panes wait under a banner that names it, and the fixes that use the console wait for a pane's switch or decision. When the command exits, Dipstick reads the pane on screen again and runs `mrk-status` again.
- **`mrk-status` runs again after each pane change**: a switch, a login item decision, or an edit of `config/dock.txt`.
- **`--snapshot` takes a folder** and draws the menu bar window, each pane of mrk Settings and the console into numbered PNGs in it.

**Moving from Gearbox**
- **Dipstick 0.4 does what Gearbox did, so you can delete Gearbox.** Its panes, its console and its `--check` reading are here, and Gearbox has no further releases.
- **macOS gives each app its own permissions**, so Gearbox's do not carry over. The Defaults pane reads Mail's keys only with Full Disk Access, and TextEdit's and Passwords' keys only with permission to get the data of other apps as well. Give Dipstick those permissions in System Settings → Privacy & Security. The Login Items pane reads the login items from System Events, so macOS asks once whether Dipstick may control System Events, unless `make update` in the console has already asked.
- **Gearbox's own settings do not move**: the pane it showed, the Defaults filter and the trackpad switch start fresh.

**Requirements**
- Every pane needs mrk from 2026-10-23 on ([sevmorris/mrk#131](https://github.com/sevmorris/mrk/pull/131)). With an older mrk, a pane says what it cannot read and to run `make pull`, and the other panes still work.

## [0.3] — 2026-10-22

**Changed**
- **Fixes run in Dipstick's console, not in Terminal.** Click a fix and confirm, and the command runs in a window of Dipstick's own: Gearbox's console, a phosphor screen over a terminal that Dipstick reads and types at. The command runs as before, with zsh in `~/mrk`, with the login shell's environment and `MRK_ROOT`. You answer its prompts in the console: `mrk-push`'s commit message, the secret scan before a commit, `sudo`'s password. ⌃C or ⌘. stops it: Stop sends ⌃C, then SIGTERM, then SIGKILL. When it ends, Dipstick runs `mrk-status` again, so you no longer click ↻. The button at the top right of the console picks Phosphor Green, Phosphor Amber or Plain.
- **Three fixes still open a terminal.** `make sync ARGS=-c`, `make sync-login-items ARGS=-c` and `make brew` draw a full-screen picker (mrk-picker or `gum choose`), and the console is a dumb terminal that cannot show one. The mrk-menu button opens a terminal too.
- **While a fix runs, its window does not close and Dipstick does not quit.** Quitting would cut the fix off, perhaps between a commit and its push. The console comes to the front instead. The fix buttons that use the console wait until it has finished, and the menu names the fix with a Show button.
- **`make update` asks for System Events.** It removes the login items mrk keeps off, through System Events, and macOS now asks about Dipstick rather than Terminal. Dipstick carries the usage text and the entitlement for that request, so macOS asks once. Fixes in the console may also need App Management (for `brew upgrade`) or access to other apps' data (for `make snapshot-prefs` and `make defaults`).
- **`--snapshot` also draws the console**, running `make help`, into a second PNG beside the first. It puts back any key the run wrote in Dipstick's defaults domain.

## [0.2] — 2026-10-19

**Fixed**
- **The window shows the panels.** In 0.1 the window under the menu bar icon showed the verdict and the footer, and nothing between them. The menu bar window is as tall as its content asks to be, and the list of panels, a scroll view, asked for no height, so it got none. The list is now as tall as what it holds, up to 520 points, and scrolls past that.

**Changed**
- **Each warning and error is listed under the verdict.** Each one is under the name of its panel, with its detail lines and its fix button, so what is wrong shows without opening a panel. The four panels follow, closed. Their headers no longer show a fix button, because the list above already shows each fix.
- **`--snapshot` draws the menu bar window itself.** It opens the window as a click on the icon does, and saves what the window shows, at the size the menu bar gives it. In 0.1 it drew the view in a separate window, sized by its own measurement, and that window showed the panels when the menu bar window did not.

## [0.1] — 2026-10-18

The first release.

**Added**
- **mrk's daily dashboard in the menu bar.** Dipstick runs `mrk-status --json` and shows its four panels: Unrecorded, Upkeep, Time Machine Backups and Installation. It does no checks of its own, so the menu bar and `mrk-status` in a terminal always agree. It runs `mrk-status` at launch, every 30 minutes, when you open the menu on a report more than two minutes old, and when you click ↻.
- **The icon shows the worst result.** A check mark when every check passes, a triangle for a warning, an octagon for an error, and a question mark when `mrk-status` did not run or gave no report. A panel with a warning or an error opens by itself.
- **Each fix is a button that shows its command.** Click it and confirm, and the command runs in a terminal, in `~/mrk`, as the `f` key runs it in `mrk-status`. A fix needs a terminal: `make sync ARGS=-c` opens the picker, and `sudo` asks for a password. Dipstick opens a `.command` file that deletes itself, so it needs no Automation permission.
- **Check for Updates…** in the window's footer asks GitHub for a newer Dipstick. Dipstick also checks without asking at launch and once a day. When a newer version is out, the footer names it in place of the button. A version that needs a newer macOS than the Mac has is not offered.

**Requirements**
- macOS 15 or later, on Apple silicon.
- An mrk whose `mrk-status` has `--json`, which mrk has had since 2026-10-18 ([sevmorris/mrk#104](https://github.com/sevmorris/mrk/pull/104)). With an older mrk, Dipstick says so and offers `make pull`.
