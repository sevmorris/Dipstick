import XCTest
@testable import Dipstick

/// The Default Apps pane: `default-apps --check` read, grouped by the listed
/// app and counted, and `--snapshot` run through the script's own flag.
@MainActor
final class DefaultAppsTests: XCTestCase {
    /// The real output, from mrk#175 on the owner's Mac, where every type
    /// opens in its listed app. Fixtures/README.md says whence.
    func testTheRealCheck() throws {
        let checks = DefaultAppCheck.parse(try Fixture.text("mrk-175/default-apps--check.out"))
        XCTAssertEqual(checks.count, 19)
        XCTAssertEqual(DefaultAppCounts(checks), DefaultAppCounts(set: 19))
        let groups = DefaultAppGroup.group(checks)
        XCTAssertEqual(groups.map(\.app), ["com.duckduckgo.macos.browser", "local.mrk.media-opener"])
        XCTAssertEqual(groups.map(\.checks.count), [3, 16])
        XCTAssertEqual(checks.first?.title, "https links".replacingOccurrences(of: "https", with: "http"))
    }

    /// Each state, a field after the four, and an escape undone. A state
    /// this Dipstick does not know, and a line of another shape, are passed
    /// over.
    func testEachStateAndTheLinesPassedOver() {
        let checks = DefaultAppCheck.parse("""
        public.mp3\tlocal.mrk.media-opener\tlocal.mrk.media-opener\tset
        public.mpeg-4\tlocal.mrk.media-opener\torg.musicbrainz.picard\tdiffers\ta later field
        public.aiff-audio\tlocal.mrk.media-opener\t\tnone
        public.avi\tcom.example.player\t\tnoapp
        org.example.nosuch\tlocal.mrk.media-opener\t\tunknown
        public.mp2\tlocal.mrk.media-opener\t\tperhaps
        a line of another shape
        scheme:a\\tb\tcom.example.x\t\tnone

        """)
        XCTAssertEqual(checks.map(\.state), [.set, .differs, .none, .noapp, .unknown, .none])
        XCTAssertEqual(checks[1].current, "org.musicbrainz.picard")
        XCTAssertEqual(checks[5].type, "scheme:a\tb")
        XCTAssertEqual(DefaultAppCounts(checks), DefaultAppCounts(set: 1, differs: 1, none: 2, noApp: 1, unknown: 1))
        XCTAssertEqual(DefaultAppCounts(checks).drift, 3)
        XCTAssertEqual(DefaultAppGroup.group(checks).map(\.app),
                       ["local.mrk.media-opener", "com.example.player", "com.example.x"])
    }

    func testTheTitles() {
        XCTAssertEqual(DefaultAppCheck(type: "scheme:https", app: "a", current: "", state: .set).title, "https links")
        XCTAssertTrue(DefaultAppCheck(type: "public.mp3", app: "a", current: "", state: .set).title.hasSuffix("(.mp3)"))
        XCTAssertEqual(DefaultAppCheck(type: "org.example.nosuch", app: "a", current: "", state: .unknown).title,
                       "org.example.nosuch")
    }

    func testThePaneReadsTheCheck() async throws {
        let stub = try StubMrk()
        try stub.answer("default-apps", ["--check"], out: """
        public.mp3\tlocal.mrk.media-opener\tlocal.mrk.media-opener\tset
        public.mpeg-4\tlocal.mrk.media-opener\torg.musicbrainz.picard\tdiffers
        public.avi\tcom.example.player\t\tnoapp

        """)
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.counts, DefaultAppCounts(set: 1, differs: 1, noApp: 1))
        XCTAssertEqual(model.subtitle, "1 set · 1 in another app · 1 waiting")
        XCTAssertEqual(stub.calls.map { $0.components(separatedBy: " cwd=")[0] }, ["scripts/default-apps [--check]"])
    }

    /// Lines, and not one Dipstick can read: an mrk newer than this Dipstick.
    func testLinesItCannotReadSaySo() async throws {
        let stub = try StubMrk()
        try stub.answer("default-apps", ["--check"], out: "public.mp3\tx\tx\tperhaps\n")
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        await model.load()
        guard case .failed(let message) = model.phase else { return XCTFail("got \(model.phase)") }
        XCTAssertTrue(message.contains("scripts/default-apps --check"), message)
        XCTAssertTrue(message.contains("this Dipstick is older than mrk's output"), message)
    }

    /// An mrk from before sevmorris/mrk#175 has no script: pull, rather than
    /// "could not start". The other panes are not affected.
    func testAnMrkWithoutDefaultAppsSaysToPull() async throws {
        let stub = try StubMrk()
        try FileManager.default.removeItem(at: stub.root.appendingPathComponent("scripts/default-apps"))
        XCTAssertNil(stub.checkout.missing(), "the other panes still work")
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        await model.load()
        guard case .failed(let message) = model.phase else { return XCTFail("got \(model.phase)") }
        XCTAssertTrue(message.contains("older than Dipstick"), message)
        XCTAssertTrue(message.contains("make pull"), message)
        XCTAssertTrue(stub.calls.isEmpty)
    }

    func testARefusedListSaysWhy() async throws {
        let stub = try StubMrk()
        try stub.answer("default-apps", ["--check"],
                        err: "  ✗ config/default-apps.tsv lists public.mp3 twice\n", status: 1)
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        await model.load()
        XCTAssertEqual(model.phase,
                       .failed("default-apps refuses config/default-apps.tsv: config/default-apps.tsv lists public.mp3 twice"))
    }

    /// Snapshot runs the script's flag, shows what it changed, reads the
    /// types again, and tells the menu bar.
    func testSnapshotRunsItsFlagThenChecksAgain() async throws {
        let stub = try StubMrk()
        try stub.answer("default-apps", ["--check"], out: "public.mp3\ta\ta\tset\n")
        try stub.answer("default-apps", ["--snapshot"], err: """

        ══ Default apps snapshot

          ▸ Change: public.mpeg-4 → com.example.player (the list says local.mrk.media-opener)
          ✓ 1 change(s) in config/default-apps.tsv
            Review: git -C /x diff config/default-apps.tsv

        """)
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        var told = 0
        model.changed = { told += 1 }
        await model.snapshot()
        XCTAssertEqual(stub.calls.map { $0.components(separatedBy: " cwd=")[0] },
                       ["scripts/default-apps [--snapshot]", "scripts/default-apps [--check]"])
        XCTAssertEqual(model.snapshotLog,
                       "Change: public.mpeg-4 → com.example.player (the list says local.mrk.media-opener)\n"
                       + "1 change(s) in config/default-apps.tsv")
        XCTAssertNil(model.decisionError)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(told, 1)
        XCTAssertFalse(model.busy)
    }

    func testARefusedSnapshotIsShown() async throws {
        let stub = try StubMrk()
        try stub.answer("default-apps", ["--snapshot"], err: "  ✗ Cannot read /x/secure.plist\n", status: 1)
        let model = DefaultAppsModel(checkout: stub.checkout, runner: stub.runner())
        await model.snapshot()
        XCTAssertEqual(model.decisionError, "Cannot read /x/secure.plist")
    }

    /// mrk Settings has the pane, after the Dock, and a snapshot holds the
    /// menu bar's fixes as a switch does.
    func testSettingsHasThePane() throws {
        let stub = try StubMrk()
        let settings = SettingsModel(checkout: stub.checkout, runner: stub.runner(), store: stub.store())
        XCTAssertEqual(Pane.allCases.firstIndex(of: .defaultApps), Pane.allCases.firstIndex(of: .dock)! + 1)
        XCTAssertEqual(Pane.defaultApps.title, "Default Apps")
        XCTAssertFalse(settings.isDeciding)
        settings.defaultApps.busy = true
        XCTAssertTrue(settings.isDeciding)
    }
}
