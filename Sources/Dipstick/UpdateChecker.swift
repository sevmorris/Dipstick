import Foundation

/// A release newer than this build, which this Mac can run.
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let releaseURL: URL
}

/// Asks GitHub for Dipstick's latest release, as each sibling app asks for its
/// own: sevmorris/Dipstick's /releases/latest, and the minimum-macos marker
/// release.sh ends every release's notes with.
actor UpdateChecker {
    static let shared = UpdateChecker()

    enum Result: Equatable {
        case upToDate(version: String)
        case available(AvailableUpdate)
        /// Newer than this build, but it needs a newer macOS than this Mac has.
        case needsNewerMacOS(version: String, minimum: String, installed: String)
        case error(String)
    }

    /// The fields of GitHub's release JSON that the check reads.
    struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]
        /// The release notes, which carry the minimum-macos marker.
        let body: String?

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
            case body
        }
    }

    static let apiURL = URL(string: "https://api.github.com/repos/sevmorris/Dipstick/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/sevmorris/Dipstick/releases")!

    /// The version this copy is: the bundle's, or appVersion under `swift run`,
    /// which has no bundle.
    nonisolated static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersion
    }

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// The macOS a release says it needs. release.sh ends every release's notes
    /// with `<!-- minimum-macos: 15.0 -->`, read from the built app's
    /// LSMinimumSystemVersion; GitHub does not render the comment. nil when there
    /// is no marker: a release from before it existed, which runs on every macOS
    /// this build does.
    nonisolated static func minimumMacOS(inReleaseNotes notes: String?) -> OperatingSystemVersion? {
        guard let notes,
              let start = notes.range(of: "<!-- minimum-macos:"),
              let end = notes[start.upperBound...].range(of: "-->") else { return nil }
        return macOSVersion(String(notes[start.upperBound..<end.lowerBound]))
    }

    /// "15", "15.0" or "15.2.1" as a version; nil for anything else.
    nonisolated static func macOSVersion(_ string: String) -> OperatingSystemVersion? {
        let fields = string.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        let numbers = fields.compactMap { Int($0) }
        guard (1...3).contains(fields.count), numbers.count == fields.count else { return nil }
        return OperatingSystemVersion(majorVersion: numbers[0],
                                      minorVersion: numbers.count > 1 ? numbers[1] : 0,
                                      patchVersion: numbers.count > 2 ? numbers[2] : 0)
    }

    /// True when a Mac running `os` meets `minimum`.
    nonisolated static func runs(on os: OperatingSystemVersion, given minimum: OperatingSystemVersion) -> Bool {
        (os.majorVersion, os.minorVersion, os.patchVersion)
            >= (minimum.majorVersion, minimum.minorVersion, minimum.patchVersion)
    }

    /// "15.0", or "15.2.1" when there is a patch number.
    nonisolated static func describe(_ version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion > 0 ? "\(base).\(version.patchVersion)" : base
    }

    /// What `release` means for a copy at `installed` on a Mac running `os`.
    /// Apart from the request, so the tests can ask it.
    nonisolated static func result(for release: Release, installed: String,
                                   os: OperatingSystemVersion) -> Result {
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        guard latest.compare(installed, options: .numeric) == .orderedDescending else {
            return .upToDate(version: installed)
        }
        // A release this Mac cannot run is not an update for it: its DMG would
        // replace a working app with one that will not open.
        if let minimum = minimumMacOS(inReleaseNotes: release.body), !runs(on: os, given: minimum) {
            return .needsNewerMacOS(version: latest, minimum: describe(minimum), installed: installed)
        }
        let releaseURL = URL(string: release.htmlUrl) ?? releasesURL
        let downloadURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
            .flatMap { URL(string: $0.browserDownloadUrl) }
            ?? releaseURL
        return .available(AvailableUpdate(version: latest, downloadURL: downloadURL, releaseURL: releaseURL))
    }

    func check() async -> Result {
        do {
            var request = URLRequest(url: Self.apiURL, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await urlSession.data(for: request)

            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                break
            case 404:
                // What /releases/latest answers while a repo has no release.
                return .error("Dipstick has no published release yet.")
            default:
                return .error("Could not reach GitHub. Check your internet connection.")
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            return Self.result(for: release, installed: Self.installedVersion,
                               os: ProcessInfo.processInfo.operatingSystemVersion)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
