# Changelog

All notable changes to Dipstick are documented here. Every released version has a matching `v*` git tag. `release.sh` keeps the five most recent GitHub release pages, so an older version is reachable by its tag after its page is pruned.

Write a version's entry before releasing it, and put the same prose in `release-notes/v<version>.md`: `release.sh` publishes that file as the release's notes, and stops before building anything when it is absent.

## [0.1] — unreleased

The first release.

**Added**
- **mrk's daily dashboard in the menu bar.** Dipstick runs `mrk-status --json` and shows its four panels: Unrecorded, Upkeep, Time Machine Backups and Installation. It does no checks of its own, so the menu bar and `mrk-status` in a terminal always agree. It runs `mrk-status` at launch, every 30 minutes, when you open the menu on a report more than two minutes old, and when you click ↻.
- **The icon shows the worst result.** A check mark when every check passes, a triangle for a warning, an octagon for an error, and a question mark when `mrk-status` did not run or gave no report. A panel with a warning or an error opens by itself.
- **Each fix is a button that shows its command.** Click it and confirm, and the command runs in a terminal, in `~/mrk`, as the `f` key runs it in `mrk-status`. A fix needs a terminal: `make sync ARGS=-c` opens the picker, and `sudo` asks for a password. Dipstick opens a `.command` file that deletes itself, so it needs no Automation permission.
- **Check for Updates…** in the window's footer asks GitHub for a newer Dipstick. Dipstick also checks without asking at launch and once a day. When a newer version is out, the footer names it in place of the button. A version that needs a newer macOS than the Mac has is not offered.

**Requirements**
- macOS 15 or later, on Apple silicon.
- An mrk whose `mrk-status` has `--json`, which mrk has had since 2026-10-18 ([sevmorris/mrk#104](https://github.com/sevmorris/mrk/pull/104)). With an older mrk, Dipstick says so and offers `make pull`.
