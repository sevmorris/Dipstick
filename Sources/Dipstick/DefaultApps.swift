import Foundation
import UniformTypeIdentifiers

/// One line of `default-apps --check`: a type of config/default-apps.tsv, the
/// app the list gives it, and the app that opens it on this Mac.
struct DefaultAppCheck: Hashable, Sendable, Identifiable {
    enum State: String, Sendable, CaseIterable {
        /// The listed app opens it.
        case set
        /// Another app opens it: an app took it, or you gave it away.
        case differs
        /// No app opens it.
        case none
        /// The listed app is not on this Mac; --apply skips it.
        case noapp
        /// No app on this Mac declares the type; --apply skips it.
        case unknown

        /// What default-apps --apply would change.
        var isDrift: Bool { self == .differs || self == .none }
    }

    /// A uniform type identifier, such as public.mp3, or scheme:NAME.
    let type: String
    /// The bundle identifier of the app the list gives the type.
    let app: String
    /// The bundle identifier of the app that opens it now, or "" for none.
    let current: String
    let state: State

    var id: String { type }

    /// Four fields or more, by mrk's --check line contract, each with its
    /// escapes undone. A line in any other shape, or with a state this
    /// Dipstick does not know, is passed over.
    static func parse(_ output: String) -> [DefaultAppCheck] {
        MrkText.lines(output).compactMap { line in
            guard let f = MrkText.fields(line), f.count >= 4, !f[0].isEmpty, !f[1].isEmpty,
                  let state = State(rawValue: f[3]) else { return nil }
            return DefaultAppCheck(type: f[0], app: f[1], current: f[2], state: state)
        }
    }

    /// The URL scheme, for a type that is one.
    var scheme: String? { type.hasPrefix("scheme:") ? String(type.dropFirst("scheme:".count)) : nil }

    /// What a person calls the type: "MP3 audio (.mp3)", or "https links".
    var title: String {
        if let scheme { return "\(scheme) links" }
        guard let ut = UTType(type), !ut.isDynamic else { return type }
        let name = ut.localizedDescription ?? type
        if let ext = ut.preferredFilenameExtension { return "\(name) (.\(ext))" }
        return name
    }
}

/// The checks under the app the list gives them, in the order the list first
/// names each app.
struct DefaultAppGroup: Hashable, Sendable, Identifiable {
    let app: String
    let checks: [DefaultAppCheck]
    var id: String { app }

    static func group(_ checks: [DefaultAppCheck]) -> [DefaultAppGroup] {
        var order: [String] = []
        var byApp: [String: [DefaultAppCheck]] = [:]
        for check in checks {
            let key = check.app.lowercased()
            if byApp[key] == nil { order.append(key) }
            byApp[key, default: []].append(check)
        }
        return order.map { DefaultAppGroup(app: byApp[$0]![0].app, checks: byApp[$0]!) }
    }
}

/// How many types are in each state.
struct DefaultAppCounts: Equatable, Sendable {
    var set = 0, differs = 0, none = 0, noApp = 0, unknown = 0

    init(set: Int = 0, differs: Int = 0, none: Int = 0, noApp: Int = 0, unknown: Int = 0) {
        self.set = set; self.differs = differs; self.none = none; self.noApp = noApp; self.unknown = unknown
    }

    init(_ checks: [DefaultAppCheck]) {
        for check in checks {
            switch check.state {
            case .set: set += 1
            case .differs: differs += 1
            case .none: none += 1
            case .noapp: noApp += 1
            case .unknown: unknown += 1
            }
        }
    }

    /// What default-apps --apply would change.
    var drift: Int { differs + none }
}
