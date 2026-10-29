# Fixtures

Real output of mrk's `--check` modes on the owner's Mac, captured on 2026-10-22, so the parsers are tested against what the scripts print and not only against lines written by hand.

- `mrk-122/` — sevmorris/mrk#122 (branch `claude/charming-shamir-b646de`, commit `1e3f979`), the first mrk with one line contract for the five `--check` modes. Each `<script>--<flag>….out` is that command's stdout. `dock.txt`, `defaults.tsv`, `login-items.txt` and `app-prefs.tsv` are the `config/` files it read.
  - `dock-setup--check.out` has the fifth field on every line, and an `unlisted` line for `/Applications/Signal.app`, which is in the Dock and not in `dock.txt`.
  - `defaults.sh--check--with-trackpad.out` has no `nodomain` line: Mail's and TextEdit's domains exist on this Mac.
  - `sync-login-items--check.out` is empty: the login items match the list.
- `mrk-before-122/dock-setup--check.out` — `dock-setup --check` from mrk `8760cc7`, before #122: four fields, with the same `dock.txt`. Dipstick must still read it.
- `mrk-135/snapshot-prefs--check-unread.out` — `snapshot-prefs --check` from mrk `3c3e765` (sevmorris/mrk#135 and #136), captured on 2026-10-28 under a throwaway HOME with a stub `defaults` and a stub `ls` that refuses Keka's container, as macOS refuses it to a process without permission to get the data of other apps. Keka's line is `unread`.
- `mrk-contract.json` — the output of `scripts/mrk-contract` from [sevmorris/mrk#142](https://github.com/sevmorris/mrk/pull/142), which added the `terminal` list to the document of [sevmorris/mrk#140](https://github.com/sevmorris/mrk/pull/140). `ContractTests` requires that it takes every option of every command Dipstick runs, and `TerminalLauncherTests` that its `terminal` list names each target Dipstick keeps for an older mrk. Capture it again when a pane passes a new option, or when the list changes.
- `mrk-140/mrk-contract.json` — the output of `scripts/mrk-contract` from mrk `1c9e748` (#140), the first, with no `terminal` list. Dipstick must read it, with its own targets.
- `check-lines.json` — a copy, byte for byte, of mrk's `tests/fixtures/check-lines.json`: the line contract of the five `--check` modes as data. Each case has its fields, and the line that `mrk_check_line` writes for them. mrk's Go tests write the lines from the encoder (`MRK_UPDATE_FIXTURES=1 go test` in `tools/mrk-status`), and fail when this copy is not mrk's file. Copy it again from mrk when it changes.

Capture them again with the scripts themselves; never edit one by hand.
