import XCTest
@testable import Dipstick

final class BarkeepLinkTests: XCTestCase {

    func testOnlyTheSyncFixIsBarkeeps() {
        XCTAssertTrue(BarkeepLink.makes("make sync ARGS=--push"))
        XCTAssertTrue(BarkeepLink.makes("make sync"))
        XCTAssertFalse(BarkeepLink.makes("make sync-login-items ARGS=-c"))
        XCTAssertFalse(BarkeepLink.makes("bin/mrk-push"))
        XCTAssertFalse(BarkeepLink.makes("make brew"))
    }

    /// An app bundle at PATH with BUNDLE's identifier.
    private func app(_ path: URL, bundle: String) throws -> URL {
        try FileManager.default.createDirectory(at: path.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": bundle, "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: path.appendingPathComponent("Contents/Info.plist"))
        return path
    }

    /// A build in DerivedData declares the link too, and LaunchServices may
    /// list it first. The installed copy is the one that opens it.
    func testTheInstalledBarkeepNotABuild() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("dipstick-barkeep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let build = try app(home.appendingPathComponent("Library/Developer/Xcode/DerivedData/B/Build/Products/Debug/Barkeep.app"),
                            bundle: BarkeepLink.bundleIdentifier)
        let installed = try app(home.appendingPathComponent("Applications/Barkeep.app"), bundle: BarkeepLink.bundleIdentifier)
        let other = try app(home.appendingPathComponent("Applications/Other.app"), bundle: "dev.example.other")

        XCTAssertEqual(BarkeepLink.installedApp(among: [build, other, installed], home: home.path), installed)
        XCTAssertNil(BarkeepLink.installedApp(among: [build], home: home.path), "a build alone is no Barkeep")
        XCTAssertNil(BarkeepLink.installedApp(among: [other], home: home.path), "another app that takes the link")
        XCTAssertNil(BarkeepLink.installedApp(among: [], home: home.path))
    }

    /// With Barkeep, the fix opens its Untracked list and runs nothing; the
    /// button names Barkeep. Without one, the fix is the terminal's, as before.
    @MainActor
    func testTheSyncFixOpensBarkeepWhenThereIsOne() async throws {
        let stub = try StubMrk()
        let barkeep = URL(fileURLWithPath: "/Applications/Barkeep.app")
        var opened: [URL] = []
        let model = stub.model(findBarkeep: { barkeep }, openInBarkeep: { opened.append($0) })
        await model.refresh()
        XCTAssertEqual(model.barkeepApp, barkeep)
        XCTAssertTrue(model.opensInBarkeep("make sync ARGS=--push"))
        XCTAssertFalse(model.opensInBarkeep("make sync-login-items ARGS=-c"))

        let runs = stub.calls.count
        model.run("make sync ARGS=--push")
        XCTAssertEqual(opened, [barkeep])
        XCTAssertEqual(stub.calls.count, runs, "nothing ran")
        XCTAssertNil(model.console)

        let none = stub.model()
        await none.refresh()
        XCTAssertNil(none.barkeepApp)
        XCTAssertFalse(none.opensInBarkeep("make sync ARGS=--push"))
        XCTAssertTrue(none.needsTerminal("make sync ARGS=--push"))
    }
}
