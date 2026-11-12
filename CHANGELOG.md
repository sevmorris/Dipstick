# Changelog

All notable changes to Dipstick are documented here. Every released version has a matching `v*` git tag. `release.sh` keeps the five most recent GitHub release pages, so an older version is reachable by its tag after its page is pruned.

Write a version's entry before releasing it, and put the same prose in `release-notes/v<version>.md`: `release.sh` publishes that file as the release's notes, and stops before building anything when it is absent.

## [0.12] — 2026-11-12

**Changed**
- **Outdated Homebrew packages no longer turn the menu bar icon into a warning.** Something is outdated nearly every day, so the triangle stopped meaning anything. The icon now leaves out mrk-status's lines for outdated formulae and casks; the window still lists them as warnings, with their **make update** buttons. Every other warning or error still shows in the menu bar, including a Homebrew list too long unfetched to trust.

**Updating**
- From 0.8, **Update and Relaunch** installs this version in place.

## [0.11] — 2026-11-07

**Added**
- **A way to Full Disk Access from the menu bar.** Time Machine's settings can be read only by an app with Full Disk Access, which macOS never asks for, so without it the Time Machine panel said only "operation not permitted". With an mrk from 2026-11-07 or later (`make pull`), the line says it needs Full Disk Access, and a **Full Disk Access…** button beside it opens the pane in System Settings where you turn Dipstick on. Then quit and reopen Dipstick.

**Updating**
- From 0.8, **Update and Relaunch** installs this version in place. The button needs an mrk from 2026-11-07 or later (`make pull`); with an older one, the menu bar is as in 0.10.

## [0.10] — 2026-11-07

**Changed**
- **Every command runs in Dipstick's console.** Nothing opens Terminal any more. The fixes that show a picker, `make sync ARGS=--push` (without Barkeep 1.17.0 or later) and `make brew`, and the mrk-menu button now run in the console, and so do the Commands pane's `sync` and `sync-login-items` commands, `update-full` and `nuke-mrk`. The Barkeep button and the buttons that open a pane of mrk Settings work as before.
- **The console draws full-screen programs.** mrk-picker, gum's picker and mrk-menu draw in it as they do in Terminal, and leave the console's record as it was when they exit. The arrow keys, Escape, ⇧Tab and the function keys reach them. Page Up and Down, Home and End go to a full-screen program, and scroll the console otherwise.
- **mrk-picker and mrk-menu start at once.** As they start, they ask the terminal for its colours, and wait five seconds for an answer that never comes. The console answers.
- **The console is as big as its window.** A program learns its size when it starts and again when you resize the window, so a picker redraws to fit, and long lines wrap at the window's edge. The window opens larger, and can't be made smaller than 920 × 600, which holds the 80 × 22 mrk-menu needs.
- **Colours on a phosphor screen.** A colour beyond the basic sixteen glows as bright as it is, so a picker's grey help text sits back, and a highlighted background shows as a faint bar. Plain shows the colours.

**Developer**
- The console's terminal is xterm-256color, as far as mrk's programs need one: an alternate screen, cursor addressing, scroll regions, 256-colour and 24-bit colour, and answers to DSR, DA and OSC 10/11. It's written in Dipstick, with no new dependency. `TerminalLauncher` and its `.command` files are gone.
- Dipstick no longer reads `scripts/mrk-contract`'s `terminal` list or `mrk-menu --json`'s `terminal` key. mrk keeps both while Dipstick 0.9 is in use.

**Updating**
- From 0.8, **Update and Relaunch** installs this version in place. It needs no newer mrk.

## [0.9] — 2026-11-05

**Added**
- **A Commands pane in mrk Settings.** It lists every mrk-menu command, in the same groups and order, and runs the one you choose. That means you can run `make pull`, `make update`, `clean-ds` or `tidy-projects` whenever you want, not only when the menu bar shows a fix for it.
- **A row runs exactly what it shows.** Commands that can show a picker (those of `sync` and `sync-login-items`), `update-full` and `nuke-mrk` open in Terminal. Every other command runs in Dipstick's console. Unlike a fix, a command here never opens another pane or Barkeep instead. nuke-mrk runs only after you type `nuke`, as in mrk-menu.
- **The list comes from mrk.** It's read from `mrk-menu --json` in your checkout, so commands mrk adds to the menu appear here without a Dipstick update. If mrk-menu isn't built, the pane tells you to run `make build-tools`. If it's from before `--json`, the pane tells you to run `make pull`.

**Developer**
- `--snapshot` draws the new pane as `6-commands.png`, and the console is now `7-console.png`.
- `StatusModel` takes the Commands pane's confirmation and its Terminal launcher as parameters, so tests never show a dialog or open Terminal.

**Updating**
- From 0.8, **Update and Relaunch** installs this version in place. The Commands pane needs an mrk from 2026-11-05 or later (`make pull`), whose mrk-menu has `--json`.

## [0.8] — 2026-11-01

**Added**
- **Dipstick updates itself.** The update prompt now offers **Update and Relaunch**. Dipstick downloads the new version, checks that it's a signed release, replaces itself and reopens, with no disk image to open or app to drag. This starts with the update after this one: to get this version, download it as usual.
- **An update never interrupts a console command.** It waits for the command to finish, then asks before relaunching.

**Changed**
- **If Dipstick can't update itself, it says why.** A copy running from the disk image, or one you don't have permission to change, still offers **Download**, with the reason. So does any update that fails, and the installed app is left as it was.

**Developer**
- `SelfUpdater.swift` is shared verbatim with the sibling apps and needs no update feed or new key: it relies on the Developer ID signature that release DMGs and apps already carry.

## [0.7] — 2026-10-29

**Added**
- **The fix for a package the Brewfile lacks opens Barkeep.** With Barkeep 1.17.0 or later installed, in `/Applications` or `~/Applications`, the Unrecorded panel's fix for a package the Brewfile lacks is a **Barkeep…** button. A click opens Barkeep's Untracked list through its link, `barkeep://untracked`, where each package is added, adopted or ignored with mrk's sync, and runs nothing in a terminal. Dipstick looks for Barkeep at each refresh. It opens the installed copy by its path, because a build of Barkeep in Xcode's DerivedData declares the link too. With an earlier Barkeep, or none, the fix opens sync's picker in a terminal, as before.

## [0.6] — 2026-10-29

**Added**
- **Dipstick asks mrk which options its scripts take.** mrk from 2026-10-29 has `scripts/mrk-contract` ([sevmorris/mrk#140](https://github.com/sevmorris/mrk/pull/140)), which lists, as JSON, the options of each script that Dipstick runs. Dipstick reads it once for each checkout, and again when the file changes, before a pane runs a script. When the script does not take an option, the pane runs nothing and says that this mrk is older than Dipstick, with `make pull`; or, for a contract of a later version, that this Dipstick is older. When the script takes the option and still exits 2, the pane shows mrk's reason, and never says to run `make pull` ([sevmorris/mrk audit 22](https://github.com/sevmorris/mrk/blob/main/audit/22-audit-2026-10-28.md), O-2). With an mrk from before the command, Dipstick reads an exit 2 as 0.5 does.
- **A later `mrk-status --json` schema is named.** A document whose schema is later than Dipstick reads, and that it cannot decode, says so, with Check for Updates…, where it said that the output could not be read.

**Changed**
- **mrk names the fixes that need a terminal.** mrk from 2026-10-29 lists, in `scripts/mrk-contract`, the Make targets whose scripts can start `gum`, `mrk-picker` or `mrk-menu` ([sevmorris/mrk#142](https://github.com/sevmorris/mrk/pull/142)). Dipstick reads the list with the rest of the contract at each refresh, and sends a fix for one of those targets to Terminal; every other fix runs in the console. So a new mrk target that starts a picker opens a terminal, where Dipstick's console could not show it. mrk's tests hold the list to its Makefile and to the scripts that each target runs ([sevmorris/mrk audit 22](https://github.com/sevmorris/mrk/blob/main/audit/22-audit-2026-10-28.md), opportunity 5). With an mrk whose contract has no list, Dipstick sends `make sync`, `make sync-login-items` and `make brew` to Terminal, as 0.5 does.
- **The Login Items pane no longer says that Add and Remove change the manual.** mrk from 2026-10-29 keeps the list of login items in `config/login-items.txt` alone, and its manual links to the file ([sevmorris/mrk audit 22](https://github.com/sevmorris/mrk/blob/main/audit/22-audit-2026-10-28.md), D-3).

**Developer**
- `MrkText.swift` (it was `TSV.swift`), the reader of mrk's `--check` lines, and `ShellEnvironment.swift` are shared verbatim with Barkeep, and `scripts/check-shared.sh` compares them in each release preflight. Dipstick keeps its own `ShellEnvironment.capture`, beside `Subprocess`, which runs it.
- `Tests/DipstickTests/Fixtures/check-lines.json` is a copy of mrk's `tests/fixtures/check-lines.json`: for each case, the fields and the line mrk writes for them. Dipstick's tests read each line back to its fields, and mrk's tests check that the copy matches mrk's file, byte for byte ([sevmorris/mrk audit 22](https://github.com/sevmorris/mrk/blob/main/audit/22-audit-2026-10-28.md), O-1).
- `Tests/DipstickTests/Fixtures/mrk-contract.json` is the output of mrk's `scripts/mrk-contract` with its `terminal` list, and `mrk-140/mrk-contract.json` the first output, without one. Tests read both.

## [0.5] — 2026-10-28

**Added**
- **App Preferences shows a file that `snapshot-prefs` could not read.** mrk from 2026-10-28 ([sevmorris/mrk#135](https://github.com/sevmorris/mrk/pull/135)) shows such a file as `unread`: an export that failed, or an app whose container macOS does not let Dipstick read. The pane lists it with a **not read** badge and counts it apart in its subtitle. Over the list it says that a change in the file is not known and that the snapshot keeps the saved copy, with a button to Full Disk Access. Until now the pane showed nothing for that app.

**Fixed**
- **A line with an escape before an accent is read.** Dipstick undid mrk's escapes one Character at a time, and a backslash, or the `t` of `\t`, joins an accent after it into one Character. So a line where mrk escaped a tab or a backslash before an accent was passed over. Dipstick now undoes the escapes by Unicode scalar.
- **"This mrk is older than Dipstick" only when it is.** mrk exits 2 for an option it does not know, and also for a value it refuses, such as a login item's name. Dipstick told you to run `make pull` for both. Now it does so only when mrk names an unknown option, and otherwise shows mrk's own reason, the line it marks ✗.
- **The Login Items pane names Automation only when System Events failed.** A bad line in `config/login-items.txt`, a file mrk cannot read, or another run of `sync-login-items` shows as mrk says it.
- **A login item whose name starts with a dash** can be added, ignored or removed. Dipstick passes it as `--add=NAME`, which needs mrk from 2026-10-28; with an older mrk the pane says to run `make pull`.
- **A pane's console command waits for a switch or a login item decision.** While a macOS Defaults switch ran, the Dock pane's **Apply…** could start `make dock`, which restarts the Dock beside the switch's own restart, and **Snapshot…** could export a domain half changed. **Snapshot…**, **Apply…** and **Apply All…** now wait while any pane decides, the **Trackpad** box waits for a switch, and two quick clicks on a login item run its decision once.
- **The temporary file beside `config/dock.txt`** is named for Dipstick, not Gearbox, and a write that fails part way leaves none.

**Requirements**
- The panes still work with mrk from 2026-10-23 on ([sevmorris/mrk#131](https://github.com/sevmorris/mrk/pull/131)). The **not read** files, and a login item whose name starts with a dash, need mrk from 2026-10-28 ([sevmorris/mrk#135](https://github.com/sevmorris/mrk/pull/135)). Run `make pull` in `~/mrk` to get it.

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
