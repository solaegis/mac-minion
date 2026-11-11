import Foundation
import MacMinionKit

/// `macminion sv …`: the SavedVariables Inspector for agents (S-041). Read-only, and the same
/// model code as the Game Folder page: files, a file's tree, find, one ID, problems, and space.
extension AgentCommands {
    static let savedVariables: [AgentCommand] = [
        AgentCommand(name: "sv files", summary: "List SavedVariables files with the addon each belongs to, size, and problems found.",
                     params: [.init(name: "limit", kind: .integer, help: "at most this many (default 200)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion sv files --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let problems = Dictionary(grouping: model.gameFolder.svProblems ?? [], by: \.file)
            let rows: [JSONObject] = model.gameFolder.savedVariables.map { file in
                ["file": file.name, "belongsTo": file.ownerText, "bytes": file.bytes,
                 "changed": file.modified.map(JSON.date) ?? NSNull(), "cleanUp": file.isTidyable,
                 "problems": problems[file.name]?.count ?? 0]
            }
            return try page(rows, args, key: "files", defaultLimit: 200)
        },
        AgentCommand(name: "sv tree", summary: "Show one table in a SavedVariables file: its entries with values, names for IDs, and sizes.",
                     params: [.init(name: "file", required: true, positional: true, help: "the file, like pChat.lua"),
                              .init(name: "path", help: "the table, as Copy Path writes it (Var[\"NA Megaserver\"][1]) or Var › NA Megaserver › 1; leave out for the variables"),
                              .init(name: "limit", kind: .integer, help: "at most this many entries (default 200)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion sv tree WritWorthy.lua --path 'WritWorthy_SavedVars[\"NA Megaserver\"]' --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let name = try svFile(args, model)
            guard let typed = LuaPath.parse(args.string("path") ?? "") else {
                throw AgentError.usage("can't read --path \"\(args.string("path") ?? "")\". Write it as Var[\"key\"][1] or Var › key › 1")
            }
            let url = model.gameFolderURL.appending(path: "SavedVariables/\(name)")
            let doc = await Task.detached { (try? SVDocument.read(url)) ?? SVDocument(variables: [], error: nil, byteCount: 0) }.value
            var entries = doc.variables
            var path = typed
            if !typed.isEmpty {
                guard let found = doc.resolve(typed), let table = found.value.table else {
                    throw AgentError.notFound("no table at \(typed.luaPath) in \(name). Run `macminion sv tree \(name)` to see what's there")
                }
                path = found.path
                entries = table.entries
            }
            let rows: [JSONObject] = entries.map { entry in
                var row: JSONObject = ["key": entry.key.description, "type": entry.value.typeName, "bytes": entry.span.count,
                                       "path": (path + [entry.key]).luaPath]
                if let table = entry.value.table { row["entries"] = table.count } else { row["value"] = InspectorValue.plain(entry.value) ?? "" }
                if let level = SVLevel.of(entry.key, at: path) { row["level"] = level.title }
                if let label = (model.gameFolder.names?.name(forKey: entry.key, at: path)
                                ?? model.gameFolder.names?.name(forValue: entry.value, key: entry.key, at: path))?.label { row["name"] = label }
                return row
            }
            var out = try page(rows, args, key: "entries", defaultLimit: 200)
            out["file"] = name
            out["path"] = path.luaPath
            if let error = doc.error { out["problem"] = error.description }
            return out
        },
        AgentCommand(name: "sv find", summary: "Find every place a character, account, item, guild, set, zone, or quest appears, by name or ID, across all SavedVariables.",
                     params: [.init(name: "query", required: true, positional: true, help: "a name or ID: Masisi, @Paltop, Glenumbra, 96175"),
                              .init(name: "places", kind: .integer, help: "at most this many places per match (default 50)")],
                     example: "macminion sv find Masisi --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let query = try args.required("query")
            guard let refs = model.gameFolder.references, let names = model.gameFolder.names else { return ["matches": [JSONObject](), "total": 0] }
            let results = await model.gameFolder.findResults(refs.targets(matching: query, names: names), perTarget: try args.int("places", default: 50))
            return ["matches": results.map(json), "total": results.count] as JSONObject
        },
        AgentCommand(name: "sv id", summary: "Name one ID (character, item, guild, zone, quest, set, account) and count where it appears.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ID: 8796093036412335, 96175, @Paltop")],
                     example: "macminion sv id 8796093036412335 --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let id = try args.required("id")
            guard let refs = model.gameFolder.references, let names = model.gameFolder.names else { return ["matches": [JSONObject](), "total": 0] }
            let targets = refs.hits.keys.filter { $0.id.caseInsensitiveCompare(id) == .orderedSame }.sorted { $0.description < $1.description }
            guard !targets.isEmpty else {
                throw AgentError.notFound("no SavedVariables mention \(id). Try `macminion sv find \(id)` to match names")
            }
            let rows: [JSONObject] = targets.map { target in
                let hits = refs.hits[target] ?? []
                return ["kind": target.kind.rawValue, "id": target.id, "name": names.title(for: target) ?? NSNull(),
                        "places": hits.count, "files": Set(hits.map { refs.files[Int($0.file)] }).sorted()]
            }
            return ["matches": rows, "total": rows.count] as JSONObject
        },
        AgentCommand(name: "sv problems", summary: "What's wrong in the game folder, one finding per cause, worst first: its tier, what it means in game, what it touches, the action that fixes it, and the raw checks under it. --raw lists the raw checks alone, errors first.",
                     params: [.init(name: "file", help: "only findings with a check in this file"),
                              .init(name: "raw", kind: .boolean, help: "the raw checks, one per row, as before findings"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 100)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion sv problems --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let file = args.string("file")
            if try args.bool("raw") == true {
                let rows = (model.gameFolder.svProblems ?? []).filter { file == nil || $0.file == file }.map(json)
                return try page(rows, args, key: "problems", defaultLimit: 100)
            }
            let findings = model.gameFolder.healthFindings.filter { finding in file == nil || finding.problems.contains { $0.file == file } }
            return try page(findings.map { json($0, model) }, args, key: "findings", defaultLimit: 100)
        },
        AgentCommand(name: "sv biggest", summary: "What takes space in SavedVariables, largest first: tables, or totals by character, account, server, or file.",
                     params: [.init(name: "by", help: "tables, characters, accounts, servers, or files (default tables)"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 25)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion sv biggest --by characters --json", readOnly: true) { args, model in
            await readSavedVariables(model)
            let by = args.string("by") ?? "tables"
            guard let group = BiggestGroup(rawValue: by) else {
                throw AgentError.usage("--by must be tables, characters, accounts, servers, or files, not \"\(by)\"")
            }
            guard let usage = model.gameFolder.usage else { return ["rows": [JSONObject](), "total": 0] }
            let buckets: [SVUsage.Bucket] = switch group {
            case .tables: usage.biggest
            case .characters: usage.characters
            case .accounts: usage.accounts
            case .servers: usage.servers
            case .files: usage.files
            }
            let rows: [JSONObject] = buckets.map { b in
                var row: JSONObject = ["id": b.id, "title": b.title, "bytes": b.bytes,
                                       "share": NSDecimalNumber(string: String(format: "%.4f", Double(b.bytes) / Double(max(usage.totalBytes, 1))))]
                if let detail = b.detail { row["detail"] = detail }
                if b.kind == .table { row["file"] = b.file ?? ""; row["path"] = b.path.luaPath } else { row["files"] = b.files }
                if b.flagged { row["flagged"] = true }
                return row
            }
            var out = try page(rows, args, key: "rows", defaultLimit: 25)
            out["totalBytes"] = usage.totalBytes
            return out
        },
    ]

    /// Scans the game folder and reads every SavedVariables file, as the Game Folder page does.
    @MainActor static func readSavedVariables(_ model: AppModel) async {
        await model.gameFolder.scan()
        await model.gameFolder.load()
    }

    @MainActor static func svFile(_ args: Args, _ model: AppModel) throws -> String {
        let raw = try args.required("file")
        let name = raw.hasSuffix(".lua") ? raw : raw + ".lua"
        guard let file = model.gameFolder.savedVariables.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw AgentError.notFound("no SavedVariables file \(name). Run `macminion sv files`")
        }
        return file.name
    }

    static func json(_ p: SVProblem) -> JSONObject {
        var row: JSONObject = ["severity": "\(p.severity)", "kind": p.kind.rawValue, "title": p.kind.title, "file": p.file,
                               "path": p.path.luaPath, "message": p.message]
        if let addon = p.addon { row["addon"] = addon }
        return row
    }

    /// One finding, flat enough to read as text: the raw checks print on indented lines below it.
    @MainActor static func json(_ f: HealthFinding, _ model: AppModel) -> JSONObject {
        var row: JSONObject = ["id": f.id, "tier": "\(f.tier)", "cause": f.cause.rawValue, "certainty": f.certainty.rawValue,
                               "title": f.title, "impact": f.impact, "main": f.isMain, "bytes": f.bytes,
                               "affected": f.affected.map(\.name),
                               "problems": f.problems.map(json)]
        if let summary = f.summary { row["summary"] = summary }
        if let note = f.certaintyNote { row["certaintyNote"] = note }
        if let action = f.action {
            let (kind, targets): (String, [String]) = switch action {
            case .installLibraries(let folders): ("installLibraries", folders)
            case .update(let folders): ("update", folders)
            case .showAddon(let folder): ("showAddon", [folder])
            case .restoreFromBackup(let files): ("restoreFromBackup", files)
            case .cleanUp(let ids): ("cleanUp", ids)
            case .showInInspector(let id): ("showInInspector", [id])
            case .findCharacter(let id): ("findCharacter", [id])
            }
            row["action"] = kind
            row["actionTitle"] = model.gameFolder.title(for: action)
            row["targets"] = targets
        }
        return row
    }

    static func json(_ result: SVFindResult) -> JSONObject {
        ["kind": result.target.kind.rawValue, "id": result.target.id, "title": result.title, "places": result.total,
         "shown": result.files.flatMap(\.rows).map { row -> JSONObject in
             ["file": row.file, "path": row.path.luaPath, "value": row.value]
         }]
    }
}

/// What `sv biggest --by` totals: the size tally's groups.
private enum BiggestGroup: String {
    case tables, characters, accounts, servers, files
}
