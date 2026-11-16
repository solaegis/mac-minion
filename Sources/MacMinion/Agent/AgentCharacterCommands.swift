import Foundation
import MacMinionKit

/// `macminion characters …`: which addons each character loads, from AddOnSettings.txt, and Clone between
/// two characters (S-069). The same model code as Compare on the Characters page.
extension AgentCommands {
    static let characters: [AgentCommand] = [
        AgentCommand(name: "characters addons", summary: "List which addons a character loads, from AddOnSettings.txt, and whether that's their own list or #Default.",
                     params: [.init(name: "id", required: true, positional: true, help: "the character ID, like 8796093036412335")],
                     example: "macminion characters addons 8796093036412335 --json", readOnly: true) { args, model in
            let id = try await character(args, "id", model)
            let header = try addOnHeader(id, model)
            let effective = model.gameFolder.addOnChoices?.effective(for: header)
            let rows: [JSONObject] = (effective?.choices ?? [:]).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map { ["addon": $0.key, "name": model.addonTitle(folder: $0.key), "on": $0.value] }
            return ["character": id, "name": model.gameFolder.characterName(id), "list": header,
                    "fromDefault": effective?.fromDefault ?? true, "addons": rows, "total": rows.count] as JSONObject
        },
        AgentCommand(name: "characters clone-addons", summary: "Turn addons on or off for one character as another has them, in AddOnSettings.txt. Backs up first; Edit › Undo in the app takes it back.",
                     params: [.init(name: "from", required: true, help: "the character ID to copy from"),
                              .init(name: "to", required: true, help: "the character ID to change"),
                              .init(name: "addons", help: "only these addon folders, comma-separated; leave out for every difference"),
                              .init(name: "dry-run", kind: .boolean, help: "only list what would change")],
                     example: "macminion characters clone-addons --from 8796093036412335 --to 8798292071293572 --dry-run --json") { args, model in
            let from = try await character(args, "from", model)
            let to = try await character(args, "to", model)
            guard from != to else { throw AgentError.usage("--from and --to are the same character") }
            _ = try addOnHeader(from, model)
            _ = try addOnHeader(to, model)
            let only = args.string("addons").map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
            let rows = (model.gameFolder.addOnRows(to, from) ?? []).filter { row in
                model.gameFolder.canCloneAddOn(row.addon, from: from, to: to) && (only?.contains(row.addon) ?? true)
            }
            let changes: [JSONObject] = rows.map { row in
                ["addon": row.addon, "name": model.addonTitle(folder: row.addon), "was": row.a.map { $0 as Any } ?? NSNull(), "now": row.b ?? false]
            }
            if try args.bool("dry-run") == true || rows.isEmpty {
                return ["changed": false, "wouldChange": changes, "total": changes.count] as JSONObject
            }
            guard !model.gameIsRunning else {
                throw AgentError.invalid("Quit Elder Scrolls Online first: it writes its own copy of AddOnSettings.txt when it quits")
            }
            await model.gameFolder.applyCloneOps(rows.map { SettingsMatrix.CloneOp(file: AddOnChoices.fileName, key: $0.addon, from: from, to: to) })
            if let error = model.gameFolder.errorMessage { throw AgentError.invalid(error) }
            return ["changed": true, "changes": changes, "total": changes.count,
                    "message": model.gameFolder.message ?? NSNull()] as JSONObject
        },
    ]

    /// A character ID from the command line that the Characters page knows.
    @MainActor static func character(_ args: Args, _ name: String, _ model: AppModel) async throws -> String {
        let id = try args.required(name)
        if model.gameFolder.matrix == nil { await readSavedVariables(model) }
        model.gameFolder.loadGameSettings()
        guard model.gameFolder.characterName(id) != SVName.unknownCharacter else {
            throw AgentError.notFound("no character \(id). Run `macminion sv biggest --by characters` to see their IDs")
        }
        return id
    }

    @MainActor static func addOnHeader(_ id: String, _ model: AppModel) throws -> String {
        guard model.gameFolder.gameSettings[.addOns] != nil else {
            throw AgentError.notFound("there's no AddOnSettings.txt in the game folder yet: the game writes it the first time it runs")
        }
        guard let header = model.gameFolder.addOnHeader(id) else {
            throw AgentError.invalid("MacMinion can't tell which list in AddOnSettings.txt is \(id)'s: its megaserver isn't known")
        }
        return header
    }
}
