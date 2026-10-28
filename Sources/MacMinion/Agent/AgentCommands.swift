import Foundation
import MacMinionKit

/// Everything an agent can do in macminion. Add a command here and the CLI,
/// `help`, and the MCP tools all get it. Each `run` is on the main actor
/// with the app's model, like a button in the window, and calls the same model code.
/// Addons are named by their ESOUI id (the number in esoui.com/downloads/info<id>).
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the AddOns folder, catalog, and counts of installed addons and updates.",
                     example: "macminion status --json", readOnly: true) { _, model in
            let out: JSONObject = ["running": true, "page": model.sidebar?.rawValue ?? "none", "addonsFolder": model.addonsFolder.path,
             "catalog": model.catalog.count, "catalogUpdated": model.catalogDate.map(JSON.date) ?? NSNull(),
             "installed": model.installed.count, "updates": model.updates.count,
             "ignored": model.installed.filter(\.record.ignored).count, "notOnESOUI": model.unmatched.count,
             "updating": model.batch != nil, "ai": model.prefs.aiProvider.rawValue,
             "autoUpdate": model.prefs.autoUpdate, "ready": model.hasScanned,
             "problem": (model.scanError ?? model.refreshError).map { $0 as Any } ?? NSNull()]
            return out
        },
        AgentCommand(name: "addons list", summary: "List installed addons, by name.",
                     params: [.init(name: "status", help: "only this status: update, uptodate, ignored, unknown"),
                              .init(name: "search", help: "only names or authors containing this text"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 100)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion addons list --status update --json", readOnly: true) { args, model in
            var list = model.installed
            if let wanted = args.string("status") {
                guard let status = statusNames[wanted] else {
                    throw AgentError.usage("no status \"\(wanted)\". Use one of: \(statusNames.keys.sorted().joined(separator: ", "))")
                }
                list = list.filter { $0.status == status }
            }
            if let text = args.string("search") {
                list = list.filter { $0.catalog.name.localizedStandardContains(text) || $0.catalog.author.localizedStandardContains(text) }
            }
            return try page(list.map(json), args, key: "addons", defaultLimit: 100)
        },
        AgentCommand(name: "addons show", summary: "Show one installed or catalog addon, with its changelog since the installed version.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ESOUI id"),
                              .init(name: "changelog", kind: .boolean, help: "include the changelog text")],
                     example: "macminion addons show 7 --changelog --json", readOnly: true) { args, model in
            let addon = try catalogAddon(args, model)
            var out = json(addon, model.installed(addon.id))
            if try args.bool("changelog") == true {
                let info = try await model.loadDetails(addon.id)
                out["changelog"] = ChangelogText.since(model.installed(addon.id)?.installedVersion,
                                                       in: BBCode.plainText(info.changelog), limit: 20_000).text
            }
            return out
        },
        AgentCommand(name: "folders list", summary: "List folders in AddOns that no ESOUI entry lists (your own or hand-copied addons).",
                     example: "macminion folders list --json", readOnly: true) { _, model in
            let rows: [JSONObject] = model.unmatched.map { f in
                ["folder": f.folder, "title": f.title, "version": f.manifest?.version ?? NSNull(), "author": f.manifest?.author ?? NSNull()]
            }
            return ["folders": rows, "total": rows.count]
        },
        AgentCommand(name: "catalog search", summary: "Search the ESOUI catalog by name or author.",
                     params: [.init(name: "query", positional: true, help: "text to find; leave out to browse"),
                              .init(name: "category", kind: .integer, help: "only this category id (see `macminion categories list`)"),
                              .init(name: "sort", help: "downloads, monthly, favorites, newest, or name (default downloads)"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 25)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion catalog search \"master merchant\" --limit 5 --json", readOnly: true) { args, model in
            let saved = (model.search, model.category, model.sort)
            defer { (model.search, model.category, model.sort) = saved }
            model.search = args.string("query") ?? ""
            model.category = try args.string("category").map { _ in try args.int("category", default: 0) }
            if let sort = args.string("sort") {
                guard let value = CatalogSort(rawValue: sort) else {
                    throw AgentError.usage("no sort \"\(sort)\". Use downloads, monthly, favorites, newest, or name")
                }
                model.sort = value
            }
            let results: [JSONObject] = model.findMoreResults.map { addon in json(addon, model.installed(addon.id)) }
            return try page(results, args, key: "addons", defaultLimit: 25)
        },
        AgentCommand(name: "categories list", summary: "List ESOUI categories and their ids.",
                     example: "macminion categories list --json", readOnly: true) { _, model in
            let rows: [JSONObject] = model.categories.sorted { $0.title < $1.title }.map { c in
                ["id": c.id, "title": c.title, "files": c.fileCount]
            }
            return ["categories": rows]
        },
        AgentCommand(name: "history list", summary: "List recent installs, updates, and removals, newest first.",
                     params: [.init(name: "limit", kind: .integer, help: "at most this many (default 20)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "macminion history list --limit 10 --json", readOnly: true) { args, model in
            let events = model.history.map { e -> JSONObject in
                ["date": JSON.date(e.date), "kind": e.kind.rawValue, "name": e.name, "id": e.addonID.map { $0 as Any } ?? NSNull(),
                 "version": e.version ?? NSNull(), "previousVersion": e.previousVersion ?? NSNull(), "byMinion": e.fromMinion]
            }
            return try page(events, args, key: "events", defaultLimit: 20)
        },
        AgentCommand(name: "refresh", summary: "Download the ESOUI catalog again and rescan AddOns.",
                     example: "macminion refresh --json") { _, model in
            await model.refresh()
            if let error = model.refreshError { throw AgentError.invalid("couldn't refresh the catalog: \(error)") }
            return ["catalog": model.catalog.count, "installed": model.installed.count, "updates": model.updates.count]
        },
        AgentCommand(name: "addons install", summary: "Install an addon from the catalog, or update or reinstall an installed one.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ESOUI id")],
                     example: "macminion addons install 7 --json") { args, model in
            let addon = try catalogAddon(args, model)
            await model.install(addon.id)
            if let error = model.errors[addon.id] { throw AgentError.invalid("\(addon.name): \(error)") }
            return json(addon, model.installed(addon.id))
        },
        AgentCommand(name: "updates install", summary: "Update every addon that has an update, except ignored ones.",
                     example: "macminion updates install --json") { _, model in
            let before = model.updates.map { ($0.id, $0.catalog.name) }
            await model.updateAll()
            let failed = before.compactMap { id, name in model.errors[id].map { ["id": id, "name": name, "error": $0] } }
            return ["updated": before.count - failed.count, "failed": failed, "remaining": model.updates.count]
        },
        AgentCommand(name: "addons ignore", summary: "Skip an addon in Update All and the update count, or stop skipping it.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ESOUI id of an installed addon"),
                              .init(name: "off", kind: .boolean, help: "stop ignoring it")],
                     example: "macminion addons ignore 1146 --json") { args, model in
            let addon = try installedAddon(args, model)
            model.setIgnored(addon.id, try args.bool("off") != true)
            await model.rescan()
            return json(addon.catalog, model.installed(addon.id))
        },
        AgentCommand(name: "addons remove", summary: "Move an installed addon's folders to the Trash. Saved settings stay.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ESOUI id of an installed addon")],
                     example: "macminion addons remove 1146 --yes --json", destructive: true) { args, model in
            let addon = try installedAddon(args, model)
            let shown = json(addon.catalog, addon)
            guard args.confirmed else {
                return ["removed": false, "wouldTrash": addon.record.dirs, "addon": shown, "hint": "add --yes to move the folders to the Trash"]
            }
            await model.remove(addon)
            if let error = model.errors[addon.id] { throw AgentError.invalid(error) }
            return ["removed": true, "trashed": addon.record.dirs, "addon": shown]
        },
        AgentCommand(name: "addons summarize", summary: "Ask the AI provider set in Settings what changed since the installed version.",
                     params: [.init(name: "id", required: true, positional: true, help: "the ESOUI id")],
                     example: "macminion addons summarize 7 --json") { args, model in
            let addon = try catalogAddon(args, model)
            await model.summarize(addon.id)
            if let error = model.summaryErrors[addon.id] { throw AgentError.invalid(error) }
            return ["id": addon.id, "name": addon.name, "summary": model.summaries[addon.id] ?? "", "by": model.aiSource]
        },
        AgentCommand(name: "updates summarize", summary: "Ask the AI provider what every pending update brings, in one digest.",
                     example: "macminion updates summarize --json") { _, model in
            guard !model.updates.isEmpty else { return ["digest": "", "updates": 0] }
            await model.digestUpdates()
            model.showDigest = false
            if let error = model.digestError { throw AgentError.invalid(error) }
            return ["digest": model.digest ?? "", "updates": model.updates.count, "by": model.aiSource]
        },
        AgentCommand(name: "ai models", summary: "List the Ollama server's chat models, best for summaries first, and the recommended one.",
                     example: "macminion ai models --json", readOnly: true) { _, model in
            let base = model.prefs.aiConfig.ollamaURL
            let models = try await AIClient.ollamaModels(at: base)
            let loaded = await AIClient.loadedModels(at: base)
            let host = HostProfile.current()
            let speeds = model.prefs.modelSpeeds
            let ranked = ModelAdvisor.rank(models, host: host, loaded: loaded, speeds: speeds).map(\.name)
            let pick = ModelAdvisor.recommend(models, host: host, loaded: loaded, speeds: speeds)
            let rows: [JSONObject] = models.map { m in
                ["name": m.name, "billions": (m.billions * 10).rounded() / 10, "bytes": m.bytes, "loaded": loaded.contains(m.name),
                 "rank": ranked.firstIndex(of: m.name).map { $0 + 1 as Any } ?? NSNull(),
                 "tokensPerSecond": speeds[m.name].map { ($0.tokensPerSecond * 10).rounded() / 10 as Any } ?? NSNull()]
            }
            let recommended: Any = pick.map { ["model": $0.model, "reason": $0.reason] as JSONObject } ?? NSNull()
            let hostInfo: JSONObject = ["chip": host.chip, "memoryBytes": host.memoryBytes, "availableBytes": host.availableBytes,
                                        "performanceCores": host.performanceCores]
            return ["server": model.prefs.ollamaURL, "current": model.prefs.ollamaModel, "host": hostInfo,
                    "recommended": recommended, "models": rows]
        },
        AgentCommand(name: "ai benchmark", summary: "Measure the three best Ollama candidates' speed on this Mac, then recommend again.",
                     params: [.init(name: "models", help: "comma-separated model names instead of the top three")],
                     example: "macminion ai benchmark --json") { args, model in
            let base = model.prefs.aiConfig.ollamaURL
            let models = try await AIClient.ollamaModels(at: base)
            let host = HostProfile.current()
            let loadedNow = await AIClient.loadedModels(at: base)
            let names = args.string("models")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                ?? ModelAdvisor.rank(models, host: host, loaded: loadedNow).prefix(3).map(\.name)
            var results: [JSONObject] = []
            for name in names {
                do {
                    let speed = try await AIClient.benchmark(name, at: base)
                    model.prefs.modelSpeeds[name] = speed
                    results.append(["model": name, "tokensPerSecond": (speed.tokensPerSecond * 10).rounded() / 10,
                                    "loadSeconds": (speed.loadSeconds * 10).rounded() / 10])
                } catch {
                    results.append(["model": name, "error": error.localizedDescription])
                }
            }
            let pick = ModelAdvisor.recommend(models, host: HostProfile.current(), loaded: await AIClient.loadedModels(at: base),
                                              speeds: model.prefs.modelSpeeds)
            let recommended: Any = pick.map { ["model": $0.model, "reason": $0.reason] as JSONObject } ?? NSNull()
            return ["results": results, "recommended": recommended]
        },
        AgentCommand(name: "addons recommend", summary: "Ask the AI provider which uninstalled addons would add something to what is installed.",
                     params: [.init(name: "refresh", kind: .boolean, help: "ask again instead of showing the saved suggestions")],
                     example: "macminion addons recommend --refresh --json") { args, model in
            if try args.bool("refresh") == true || model.suggestionsStale {
                await model.suggestAddons()
                if let error = model.suggestError { throw AgentError.invalid(error) }
            }
            let rows: [JSONObject] = model.suggestions.map { s in
                var row = json(s.addon)
                row["reason"] = s.reason
                return row
            }
            return ["suggestions": rows, "made": model.suggestionsDate.map(JSON.date) ?? NSNull(), "by": model.aiSource]
        },
        AgentCommand(name: "open", summary: "Show a page in the window, optionally with an addon selected.",
                     params: [.init(name: "page", required: true, positional: true,
                                    help: SidebarItem.allCases.map(\.rawValue).joined(separator: ", ")),
                              .init(name: "addon", kind: .integer, help: "the ESOUI id to select")],
                     example: "macminion open findMore --addon 7") { args, model in
            let name = try args.required("page")
            guard let page = SidebarItem(rawValue: name) else {
                throw AgentError.usage("no page \"\(name)\". Pages: \(SidebarItem.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            let id = try args.string("addon").map { _ in try args.int("addon", default: 0) }
            model.open(page, selecting: id)
            return ["page": page.rawValue, "addon": id.map { $0 as Any } ?? NSNull()] as JSONObject
        },
    ]

    static let statusNames: [String: AddonStatus] = ["update": .updateAvailable, "uptodate": .upToDate,
                                                     "ignored": .ignored, "unknown": .versionUnknown]

    static func json(_ addon: CatalogAddon, _ installed: InstalledAddon? = nil) -> JSONObject {
        var out: JSONObject = ["id": addon.id, "name": addon.name, "author": addon.author, "latest": addon.version,
                               "updated": JSON.date(addon.date), "downloads": addon.downloads, "category": addon.categoryID,
                               "url": addon.infoURL?.absoluteString ?? NSNull()]
        if let installed {
            out["installed"] = installed.installedVersion ?? NSNull()
            out["status"] = statusNames.first { $0.value == installed.status }?.key ?? ""
            out["folders"] = installed.record.dirs
        } else {
            out["status"] = "not installed"
        }
        return out
    }

    static func json(_ installed: InstalledAddon) -> JSONObject { json(installed.catalog, installed) }

    static func page(_ items: [JSONObject], _ args: Args, key: String, defaultLimit: Int) throws -> JSONObject {
        let limit = try args.int("limit", default: defaultLimit)
        let offset = try args.int("offset", default: 0)
        let slice = Array(items.dropFirst(offset).prefix(limit))
        var out: JSONObject = [key: slice, "total": items.count]
        if offset + slice.count < items.count { out["nextOffset"] = offset + slice.count }
        return out
    }

    static func catalogAddon(_ args: Args, _ model: AppModel) throws -> CatalogAddon {
        let raw = try args.required("id")
        guard let id = Int(raw) else { throw AgentError.usage("--id must be an ESOUI id (a number), not \"\(raw)\"") }
        guard let addon = model.catalogAddon(id) else {
            throw AgentError.notFound("no ESOUI addon with id \(id). Run `macminion catalog search <name>`")
        }
        return addon
    }

    static func installedAddon(_ args: Args, _ model: AppModel) throws -> InstalledAddon {
        let addon = try catalogAddon(args, model)
        guard let installed = model.installed(addon.id) else {
            throw AgentError.notFound("\(addon.name) (\(addon.id)) is not installed. Run `macminion addons list`")
        }
        return installed
    }
}
