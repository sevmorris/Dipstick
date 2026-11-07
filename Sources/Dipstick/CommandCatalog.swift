import Foundation

/// The `mrk-menu --json` document: mrk-menu's commands, in its categories and
/// its order, for the Commands pane (BIN-1, mrk-menu). The list is mrk's, so
/// a command mrk adds to the menu shows here with no Dipstick release, and
/// Dipstick keeps no copy of it (sevmorris/mrk audit 22, opportunity 5).
///
/// Each command also has `terminal`, for one that a program must not run
/// where it cannot draw a full screen. Dipstick reads no further than the
/// keys below: its console draws one, and runs every command.
struct CommandCatalog: Decodable, Equatable, Sendable {
    /// The schema this build reads. mrk raises it when a key changes meaning
    /// or goes away; a new key alone does not raise it.
    static let supportedSchema = 1

    let schema: Int
    let categories: [Category]

    struct Category: Decodable, Equatable, Sendable, Identifiable {
        let name: String
        let commands: [Command]
        var id: String { name }
    }

    struct Command: Decodable, Equatable, Hashable, Sendable, Identifiable {
        /// The menu's label: the command as a person types it, such as
        /// `sync --push`.
        let name: String
        let description: String
        /// The line to run in the checkout, as a fix is: `bin/TOOL`,
        /// `scripts/TOOL` or `make TARGET`, with arguments that need no quotes.
        let command: String
        /// The word to type before it runs, as mrk-menu asks for nuke-mrk, or
        /// "" for none.
        let typeToConfirm: String

        var id: String { name }

        enum CodingKeys: String, CodingKey {
            case name, description, command
            case typeToConfirm = "type_to_confirm"
        }
    }

    /// Why a document is not one this build runs commands from.
    enum Failure: LocalizedError, Equatable {
        case newerSchema(Int)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .newerSchema(let schema):
                return "mrk-menu's list is schema \(schema), and this Dipstick reads schema \(CommandCatalog.supportedSchema): "
                    + "this Dipstick is older than mrk. Choose Check for Updates… in Dipstick's menu."
            case .unreadable(let message):
                return "Could not read mrk-menu --json: \(message)"
            }
        }
    }

    /// The document in DATA. A later schema is refused even when it decodes:
    /// a key that changed meaning could make a row run something other than
    /// it says, which is the one thing this pane must not do.
    static func read(_ data: Data) -> Result<CommandCatalog, Failure> {
        do {
            let catalog = try JSONDecoder().decode(CommandCatalog.self, from: data)
            if catalog.schema > supportedSchema { return .failure(.newerSchema(catalog.schema)) }
            return .success(catalog)
        } catch {
            struct Schema: Decodable { let schema: Int }
            if let schema = try? JSONDecoder().decode(Schema.self, from: data).schema, schema > supportedSchema {
                return .failure(.newerSchema(schema))
            }
            return .failure(.unreadable(String(describing: error)))
        }
    }

    /// The categories with only the commands whose name, description or
    /// category holds `search`, ignoring case, as mrk-menu's `/` filter
    /// matches. A category left with none is left out.
    static func filter(_ categories: [Category], _ search: String) -> [Category] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return categories }
        return categories.compactMap { category in
            let inCategory = category.name.lowercased().contains(needle)
            let commands = category.commands.filter {
                inCategory || $0.name.lowercased().contains(needle) || $0.description.lowercased().contains(needle)
            }
            return commands.isEmpty ? nil : Category(name: category.name, commands: commands)
        }
    }
}
