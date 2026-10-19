import XCTest
@testable import Dipstick

/// `minimumMacOS(inReleaseNotes:)` and its helpers decide whether the update
/// check offers a release, from the marker release.sh writes into its notes.
/// A missing or malformed marker sets no minimum, so the release is offered.
/// The same tests as the sibling apps', for the same code.
final class UpdateCheckerMinimumMacOSTests: XCTestCase {

    private func version(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    private func fields(_ version: OperatingSystemVersion?) -> [Int]? {
        version.map { [$0.majorVersion, $0.minorVersion, $0.patchVersion] }
    }

    /// The footer release.sh appends after the curated notes.
    func testReadsTheMarkerReleaseShWrites() {
        XCTAssertEqual(fields(UpdateChecker.minimumMacOS(inReleaseNotes: "**Fixed**\n- Something.\n\n---\nRequires macOS 15.0 or later.\n<!-- minimum-macos: 15.0 -->")), [15, 0, 0])
        XCTAssertEqual(fields(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15.2.1 -->")), [15, 2, 1])
        XCTAssertEqual(fields(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 26 -->")), [26, 0, 0])
    }

    /// The visible "Requires macOS" line is prose, not the marker.
    func testNotesWithoutAMarkerSetNoMinimum() {
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: nil))
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "**Fixed**\n- Something."))
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "Requires macOS 15.0 or later."))
    }

    func testAMalformedMarkerSetsNoMinimum() {
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: fifteen -->"))
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15.0"))
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15..0 -->"))
        XCTAssertNil(UpdateChecker.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 1.2.3.4 -->"))
    }

    func testComparesMajorThenMinorThenPatch() {
        XCTAssertFalse(UpdateChecker.runs(on: version(14, 6), given: version(15)))
        XCTAssertTrue(UpdateChecker.runs(on: version(15), given: version(15)))
        XCTAssertTrue(UpdateChecker.runs(on: version(26, 7, 1), given: version(15)))
        XCTAssertFalse(UpdateChecker.runs(on: version(15), given: version(15, 1)))
        XCTAssertTrue(UpdateChecker.runs(on: version(15, 1), given: version(15, 0, 1)))
    }

    func testDescribesAVersionTheWayMacOSDoes() {
        XCTAssertEqual(UpdateChecker.describe(version(15)), "15.0")
        XCTAssertEqual(UpdateChecker.describe(version(15, 2, 1)), "15.2.1")
    }
}

/// `result(for:installed:os:)`: what a release from GitHub means for this copy,
/// from the JSON GitHub sends. No request is made.
final class UpdateCheckerResultTests: XCTestCase {

    private let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)
    private let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)

    /// A /releases/latest answer, cut down to the fields the check reads plus
    /// a few it ignores, as release.sh publishes one: the DMG as the only
    /// asset, and the notes ending in the marker.
    private func release(tag: String, minimum: String? = "15.0",
                         assets: [String] = ["Dipstick-TAG.dmg"]) throws -> UpdateChecker.Release {
        let assetJSON = assets.map { name in
            let file = name.replacingOccurrences(of: "TAG", with: tag)
            return """
                {"name": "\(file)", "size": 1234567,
                 "browser_download_url": "https://github.com/sevmorris/Dipstick/releases/download/\(tag)/\(file)"}
                """
        }.joined(separator: ", ")
        let notes = "**Added**\\n- Something.\\n\\n---\\nRequires macOS 15.0 or later."
            + (minimum.map { "\\n<!-- minimum-macos: \($0) -->" } ?? "")
        let json = """
            {"tag_name": "\(tag)", "name": "Dipstick \(tag)", "draft": false, "prerelease": false,
             "html_url": "https://github.com/sevmorris/Dipstick/releases/tag/\(tag)",
             "body": "\(notes)", "assets": [\(assetJSON)]}
            """
        return try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
    }

    func testANewerReleaseIsOfferedWithItsDMG() throws {
        let result = UpdateChecker.result(for: try release(tag: "v0.2"), installed: "0.1", os: sequoia)
        XCTAssertEqual(result, .available(AvailableUpdate(
            version: "0.2",
            downloadURL: URL(string: "https://github.com/sevmorris/Dipstick/releases/download/v0.2/Dipstick-v0.2.dmg")!,
            releaseURL: URL(string: "https://github.com/sevmorris/Dipstick/releases/tag/v0.2")!)))
    }

    /// Numeric, not textual: 0.10 is after 0.9.
    func testVersionsCompareAsNumbers() throws {
        guard case .available(let update) = UpdateChecker.result(
            for: try release(tag: "v0.10"), installed: "0.9", os: sequoia) else {
            return XCTFail("0.10 should be offered over 0.9")
        }
        XCTAssertEqual(update.version, "0.10")
    }

    func testTheSameOrAnOlderReleaseIsUpToDate() throws {
        XCTAssertEqual(UpdateChecker.result(for: try release(tag: "v0.2"), installed: "0.2", os: sequoia),
                       .upToDate(version: "0.2"))
        XCTAssertEqual(UpdateChecker.result(for: try release(tag: "v0.1"), installed: "0.2", os: sequoia),
                       .upToDate(version: "0.2"))
    }

    func testAReleaseThisMacCannotRunIsNotOffered() throws {
        let result = UpdateChecker.result(for: try release(tag: "v0.3", minimum: "26.0"),
                                          installed: "0.2", os: sequoia)
        XCTAssertEqual(result, .needsNewerMacOS(version: "0.3", minimum: "26.0", installed: "0.2"))
        guard case .available = UpdateChecker.result(for: try release(tag: "v0.3", minimum: "26.0"),
                                                     installed: "0.2", os: tahoe) else {
            return XCTFail("a Mac on 26.1 runs a release that needs 26.0")
        }
    }

    /// Notes with no marker set no minimum, so the release is offered.
    func testAReleaseWithoutTheMarkerIsOffered() throws {
        guard case .available = UpdateChecker.result(for: try release(tag: "v0.2", minimum: nil),
                                                     installed: "0.1", os: sequoia) else {
            return XCTFail("a release without the marker should be offered")
        }
    }

    /// With no DMG among the assets, Download opens the release page.
    func testAReleaseWithoutADMGDownloadsFromItsPage() throws {
        guard case .available(let update) = UpdateChecker.result(
            for: try release(tag: "v0.2", assets: ["Dipstick-TAG-app.zip"]), installed: "0.1", os: sequoia) else {
            return XCTFail("expected an update")
        }
        XCTAssertEqual(update.downloadURL, update.releaseURL)
    }
}
