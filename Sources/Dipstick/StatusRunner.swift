import Foundation

/// Why there is no report to show.
enum StatusError: Error, Equatable, Sendable {
    case notFound(searched: [String])
    /// An mrk-status built before `--json`.
    case tooOld(path: String)
    case timedOut(seconds: Int)
    case failed(status: Int32, message: String)
    case unreadable(message: String)

    var message: String {
        switch self {
        case .notFound:
            return "mrk-status is not built."
        case .tooOld:
            return "This mrk-status has no --json. Dipstick needs a newer mrk."
        case .timedOut(let seconds):
            return "mrk-status did not finish in \(seconds) seconds."
        case .failed(let status, let message):
            return message.isEmpty
                ? "mrk-status exited \(status)."
                : "mrk-status exited \(status): \(message)"
        case .unreadable(let message):
            return "mrk-status printed something Dipstick cannot read: \(message)"
        }
    }

    /// The command that repairs it, run in ~/mrk like a panel's fix, or nil.
    var fix: String? {
        switch self {
        case .notFound: return "make build-tools"
        case .tooOld: return "make pull"
        case .timedOut, .failed, .unreadable: return nil
        }
    }
}

enum StatusRunner {
    static let timeoutSeconds = 120

    /// Where to look for mrk-status, first match wins: `DIPSTICK_MRK_STATUS`
    /// alone when it is set; then the checkout MRK_ROOT names, as mrk-status
    /// itself reads it; then the ~/bin link `make build-tools` makes; then the
    /// default checkout.
    static func candidates(environment: [String: String], home: String) -> [String] {
        if let override = environment["DIPSTICK_MRK_STATUS"], !override.isEmpty {
            return [override]
        }
        var paths: [String] = []
        if let root = environment["MRK_ROOT"], !root.isEmpty {
            paths.append("\(root)/bin/mrk-status")
        }
        paths.append("\(home)/bin/mrk-status")
        paths.append("\(home)/mrk/bin/mrk-status")
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    static func locate(
        environment: [String: String],
        home: String,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> Result<String, StatusError> {
        let paths = candidates(environment: environment, home: home)
        if let found = paths.first(where: isExecutable) { return .success(found) }
        return .failure(.notFound(searched: paths))
    }

    /// What one run of `mrk-status --json` amounts to.
    static func interpret(_ result: ProcessResult, path: String) -> Result<StatusReport, StatusError> {
        if result.timedOut { return .failure(.timedOut(seconds: timeoutSeconds)) }

        let stderr = String(decoding: result.stderr, as: UTF8.self)
        // mrk-status exits 2 on a flag it does not know, after its usage text.
        if result.status == 2, stderr.contains("unknown argument: --json") {
            return .failure(.tooOld(path: path))
        }
        guard result.status == 0 else {
            let last = stderr
                .split(whereSeparator: \.isNewline)
                .last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return .failure(.failed(status: result.status, message: last))
        }
        do {
            return .success(try StatusReport.decode(result.stdout))
        } catch {
            return .failure(.unreadable(message: String(describing: error)))
        }
    }

    static func fetch(environment: [String: String], home: String) async -> Result<StatusReport, StatusError> {
        let path: String
        switch locate(environment: environment, home: home) {
        case .success(let found): path = found
        case .failure(let error): return .failure(error)
        }
        do {
            let result = try await Subprocess.run(
                URL(fileURLWithPath: path),
                arguments: ["--json"],
                environment: environment,
                currentDirectory: URL(fileURLWithPath: home),
                timeout: .seconds(timeoutSeconds)
            )
            return interpret(result, path: path)
        } catch {
            return .failure(.failed(status: -1, message: error.localizedDescription))
        }
    }
}
