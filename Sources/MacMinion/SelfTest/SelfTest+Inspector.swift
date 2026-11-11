import AppKit
import MacMinionKit

extension SelfTest {
    /// What the scan finds in the game folder (S-028).
    static func gameFolderScan(_ model: AppModel) async {
        // S-028 See what's in the game folder
        // Updating HarvestMap above replaced its folder, so put back the module seeded inside it.
        let module = model.addonsFolder.appending(path: "HarvestMap/Modules/HarvestMapAD", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
        try? "## SavedVariables: HarvestMapAD_SavedVars\n".write(to: module.appending(path: "HarvestMapAD.txt"), atomically: true, encoding: .utf8)
        await model.gameFolder.scan()
        let scan = model.gameFolder.gameScan
        check("the scan finds the game's own items, by name", scan?.items.map(\.kind) == [.addOnSettings, .guildHistory, .logs, .machineSettings,
              .pipelineCache, .savedVariables, .screenshots, .shaderCache, .userSettings], "\(scan?.items.map(\.name) ?? [])")
        check("copies beside AddOns are grouped apart", scan?.copies.map(\.name) == ["AddOnSettings.txt.bak-20260829", "SavedVariables.bak-prune-20261006"],
              "\(scan?.copies.map(\.name) ?? [])")
        check("item sizes are read", (scan?.items.first { $0.kind == .shaderCache }?.bytes ?? 0) >= 2_000_000)
    }

    /// The Inspector's tree, names for IDs, and Find (S-036 to S-038).
    static func inspector(_ model: AppModel) async {
        // S-036 Browse the tree, S-037 Name the IDs
        SeedData.writeInspectorSamples(game: model.gameFolderURL, addons: model.addonsFolder)
        await model.gameFolder.scan()
        await model.gameFolder.inspect("WritWorthy.lua")
        let roots = model.gameFolder.inspectorRoots
        check("the Inspector opens a file's variables", roots.map(\.key) == [.string("WritWorthy_SavedVars")])
        let server = roots.first?.children?.first, account = server?.children?.first
        let masisi = account?.children?.first { $0.key == .string("8796093036412335") }
        check("levels are labeled profile, account, and character",
              server?.level == .profile && account?.level == .account && masisi?.level == .character)
        check("a character ID is named from ZO_Ingame", masisi.flatMap(model.gameFolder.inspectorName)?.label == "Masisi · character")
        check("your account is marked yours", account.flatMap(model.gameFolder.inspectorName)?.detail == "yours")
        check("a character no file names is Unknown",
              account?.children?.first { $0.key == .string("8796093079837777") }.flatMap(model.gameFolder.inspectorName)?.title == "Unknown character")
        @MainActor func field(_ key: String) -> SVName? {
            masisi?.children?.first { $0.key == .string(key) }.flatMap(model.gameFolder.inspectorName)
        }
        check("a zone ID is named from LibZone", field("zoneId")?.title == "Glenumbra")
        check("a quest ID is named from LibQuestData", field("questId")?.title == "Dark Brotherhood Assassination")
        check("a set ID is named from LibSets", field("setId")?.title == "Vestments of the Warlock")
        check("an item link is decoded and its set named", field("lastReward")?.detail?.hasPrefix("Vestments of the Warlock set · level 50") == true,
              field("lastReward")?.label ?? "")
        check("an achievement links to UESP", field("achievementId")?.uesp != nil)
        let sale: [LuaKey] = [.string("GS00DataSavedVariables"), .string("dataeu"), .integer(29516), .string("sales"), .integer(1)]
        let names = model.gameFolder.names
        check("LibGuildStore's numbers become an item, an account, and a guild",
              names?.name(forValue: .integer(7), key: .string("itemLink"), at: sale)?.detail?.hasPrefix("Vestments") == true
              && names?.name(forValue: .integer(21531), key: .string("seller"), at: sale)?.title == "@Paltop"
              && names?.name(forValue: .integer(118), key: .string("guild"), at: sale)?.title == "Bandits Clan")
        if let masisi {
            model.gameFolder.inspectorOpen(masisi)
            check("Open Table shows only that table", model.gameFolder.inspectorRows.count == masisi.children?.count && model.gameFolder.inspectorFocus == masisi.path)
            model.gameFolder.inspectorEnclosing()
            check("Enclosing Table goes up and selects where it was", model.gameFolder.inspectorFocus == masisi.parentPath && model.gameFolder.inspectorSelection == masisi.id)
            check("Open in Editor finds the inspected file", model.gameFolder.inspectorFileURL?.lastPathComponent == model.gameFolder.inspectorFile)
            check("files open in their default app until an editor is chosen", model.prefs.editorURL == nil)
            model.prefs.editorPath = "/Applications/TextEdit.app"
            check("a chosen editor is kept", model.prefs.editorURL?.lastPathComponent == "TextEdit.app")
            model.prefs.editorPath = ""
            check("Copy Path writes a Lua path", masisi.path.luaPath == "WritWorthy_SavedVars[\"NA Megaserver\"][\"@SOLAEGIS\"][\"8796093036412335\"]")
        }
        // S-038 Find every place an ID appears
        model.gameFolder.inspectorQuery = "Masisi"
        await model.gameFolder.find("Masisi")
        let found = model.gameFolder.inspectorResults?.first
        check("finding a name finds that character", found?.target == SVTarget(.character, "8796093036412335"))
        check("it lists every file that mentions the character", Set(found?.files.map(\.file) ?? []) == ["WritWorthy.lua", "ZO_Ingame.lua", "EsoMacMinion_Data.lua", "HarvestMap.lua"],
              "\(found?.files.map(\.file) ?? [])")
        check("each place is the path down to that ID",
              found?.files.flatMap(\.rows).allSatisfy { $0.path.last == .string("8796093036412335") } == true)
        if let reward = masisi?.children?.first(where: { $0.key == .string("lastReward") }) { await model.gameFolder.findEverywhere(reward) }
        let itemFound = model.gameFolder.inspectorResults?.first
        check("Find Everywhere on an item link finds it in LibGuildStore's index and sales too",
              itemFound?.target == SVTarget(.item, "29516")
              && Set(itemFound?.files.map(\.file) ?? []) == ["WritWorthy.lua", "GS16Data.lua", "GS00Data.lua"],
              "\(itemFound?.files.map(\.file) ?? [])")
        if let sale = itemFound?.files.first(where: { $0.file == "GS00Data.lua" })?.rows.first(where: { $0.path.last == .string("itemLink") }) {
            await model.gameFolder.reveal(sale)
            check("Show in Tree opens the file at that place", model.gameFolder.inspectorFile == "GS00Data.lua" && model.gameFolder.inspectorResults == nil
                  && model.gameFolder.inspectorSelectedNode?.key == .string("itemLink") && model.gameFolder.inspectorSelectedNode?.parentPath.count == 5)
        }
        let extra = model.gameFolderURL.appending(path: "SavedVariables/Extra.lua")
        try? "Extra =\n{\n    [\"owner\"] = \"8796093036412335\",\n}\n".write(to: extra, atomically: true, encoding: .utf8)
        await model.gameFolder.scan()
        await model.gameFolder.find("Masisi")
        check("the index is rebuilt when a file changes", model.gameFolder.inspectorResults?.first?.files.contains { $0.file == "Extra.lua" } == true)
        check("only the file that changed is read again", model.gameFolder.readCache.parsed.first == 1, "\(model.gameFolder.readCache.parsed)")
        await model.gameFolder.find("zzz-nothing")
        check("a find with no matches says so", model.gameFolder.inspectorResults?.isEmpty == true && model.gameFolder.inspectorFindMessage != nil)
        model.gameFolder.clearFind()
        try? FileManager.default.removeItem(at: extra)
    }

    /// What takes space in SavedVariables (S-040).
    static func space(_ model: AppModel) async {
        // S-040 Find what to trim
        let usage = model.gameFolder.usage
        check("space adds up by character, with names", usage?.characters.contains { $0.title == "Masisi" && $0.bytes > 0 && $0.files == 4 } == true)
        check("a character no file names is flagged", usage?.characters.contains { $0.id == "8796093079837777" && $0.flagged } == true)
        check("your accounts come before other people's", usage?.accounts.first?.id == "@SOLAEGIS"
              && usage?.accounts.contains { $0.id == "@Paltop" && $0.flagged } == true, "\(usage?.accounts.map(\.id) ?? [])")
        check("space adds up by server", Set(usage?.servers.map(\.id) ?? []).isSuperset(of: ["NA Megaserver", "Default"]))
        let biggest = usage?.biggest ?? []
        check("the biggest tables come largest first", !biggest.isEmpty && zip(biggest, biggest.dropFirst()).allSatisfy { $0.bytes >= $1.bytes }
              && biggest.contains { $0.title == "LibDebugLoggerLog" })
        if let log = biggest.first(where: { $0.title == "LibDebugLoggerLog" }), let file = log.file {
            await model.gameFolder.reveal(file: file, path: log.path)
            check("a table on Space opens in the Inspector", model.gameFolder.inspectorSelectedNode?.key == .string("LibDebugLoggerLog"))
        }
        await model.gameFolder.findEverywhere(SVTarget(.character, "8796093036412335"))
        check("a character on Space finds everywhere it appears", model.gameFolder.tab == .inspector
              && model.gameFolder.inspectorResults?.first?.target == SVTarget(.character, "8796093036412335"))
        model.gameFolder.clearFind()
    }

    /// The agent's sv commands (S-041).
    static func agentSV(_ model: AppModel) async {
        // S-041 Inspect from the command line
        @MainActor func sv(_ name: String, _ values: [String: String]) async -> JSONObject? {
            guard let command = AgentCommands.all.first(where: { $0.name == name }) else { return nil }
            return try? await command.run(Args(values: values), model) as? JSONObject
        }
        @MainActor func rows(_ out: JSONObject?, _ key: String) -> [JSONObject] { out?[key] as? [JSONObject] ?? [] }
        check("sv files lists SavedVariables with the addon each belongs to",
              rows(await sv("sv files", [:]), "files").contains { $0["file"] as? String == "WritWorthy.lua" && $0["belongsTo"] as? String == "WritWorthy" })
        let tree = await sv("sv tree", ["file": "WritWorthy", "path": "WritWorthy_SavedVars[\"NA Megaserver\"][\"@SOLAEGIS\"]"])
        check("sv tree shows a table's entries with names and levels", rows(tree, "entries").contains {
            $0["key"] as? String == "8796093036412335" && ($0["name"] as? String)?.hasPrefix("Masisi") == true && $0["level"] as? String == "character"
        }, "\(rows(tree, "entries").first ?? [:])")
        let svFound = rows(await sv("sv find", ["query": "Masisi"]), "matches").first
        let typed = await sv("sv tree", ["file": "WritWorthy.lua", "path": "WritWorthy_SavedVars › NA Megaserver › @SOLAEGIS › 8796093036412335"])
        check("sv tree finds a character ID typed as a number", typed?["path"] as? String
              == "WritWorthy_SavedVars[\"NA Megaserver\"][\"@SOLAEGIS\"][\"8796093036412335\"]" && rows(typed, "entries").count == 12)
        check("sv find lists every place a name appears", svFound?["places"] as? Int == 5 && (svFound?["shown"] as? [JSONObject])?.count == 5,
              "\(svFound?["places"] ?? "") places: \((svFound?["shown"] as? [JSONObject])?.map { "\($0["file"] ?? "") \($0["path"] ?? "")" } ?? [])")
        let item = rows(await sv("sv id", ["id": "29516"]), "matches").first
        check("sv id names an ID and counts where it appears", item?["kind"] as? String == "item" && (item?["places"] as? Int ?? 0) >= 3
              && (item?["files"] as? [String])?.contains("GS00Data.lua") == true)
        let cliFindings = rows(await sv("sv problems", [:]), "findings")
        check("sv problems lists the same findings as the page, in the same order",
              cliFindings.map { $0["id"] as? String } == model.gameFolder.healthFindings.map(\.id), "\(cliFindings.map { $0["id"] ?? "" })")
        // While LibLazyCrafting is missing, its finding holds what it broke; once installed (an earlier check installs
        // it), last session's "didn't load" stands alone until the game writes the companion file again.
        let library = cliFindings.first { $0["cause"] as? String == "missingLibraries" }
        let libraryInstalled = model.installedAddon(folder: "LibLazyCrafting") != nil
        let alone = cliFindings.first { ($0["problems"] as? [JSONObject])?.first?["addon"] as? String == "MissingLibAddon" }
        check("sv problems groups a missing library's breakage under it, and lets it go once installed",
              libraryInstalled
                ? library == nil && alone?["cause"] as? String == "single" && alone?["action"] as? String == "showAddon"
                : library?["action"] as? String == "installLibraries" && (library?["targets"] as? [String]) == ["LibLazyCrafting"]
                  && (library?["problems"] as? [JSONObject])?.first?["kind"] as? String == "didntLoad",
              "\(cliFindings.map { "\($0["cause"] ?? "") \($0["title"] ?? "") \(($0["affected"] as? [String])?.count ?? 0)" })")
        check("sv problems --raw lists the raw checks", rows(await sv("sv problems", ["raw": "true"]), "problems").first?["kind"] as? String == "endsEarly")
        check("sv biggest totals by character", rows(await sv("sv biggest", ["by": "characters"]), "rows").contains { $0["title"] as? String == "Masisi" })
        do {
            _ = try await AgentCommands.all.first { $0.name == "sv tree" }!.run(Args(values: ["file": "Nope.lua"]), model)
            check("sv tree on a missing file says how to find one", false)
        } catch let error as AgentError {
            check("sv tree on a missing file says how to find one", error.code == "not_found" && error.message.contains("sv files"))
        } catch {
            check("sv tree on a missing file says how to find one", false, "\(error)")
        }
    }

    /// Settings as you'd read them, names from the addon's source, and AI names (S-050).
    static func readable(_ model: AppModel) async {
        // S-050 Settings as you'd read them
        await model.gameFolder.inspect("WritWorthy.lua")
        let sheet = SVReadable.sheet(model.gameFolder.inspectorRows.map { LuaEntry(key: $0.key, value: $0.value, span: $0.span) },
                                     at: [], title: "WritWorthy", names: model.gameFolder.names)
        check("settings come in sections by who they're for", sheet.map(\.title) == ["Every character", "Alpha Top (8798292071293572)", "Masisi (8796093036412335)",
                                                                                     "Unknown character (8796093079837777)"],
              "\(sheet.map(\.title))")
        @MainActor func setting(_ section: String, _ label: String) -> SVDisplay? {
            sheet.first { $0.title == section }?.rows.first { $0.label == label }?.display
        }
        check("true and false read as On or Off", setting("Every character", "Show mat cost") == .toggle(true)
              && setting("Every character", "Auto accept") == .toggle(false))
        if case .color(let r, _, _, _)? = setting("Every character", "Mat cost color"), case .color? = setting("Every character", "Header color") {
            check("colors read as swatches, from tables and color codes", abs(r - 0.36) < 0.001)
        } else {
            check("colors read as swatches, from tables and color codes", false)
        }
        check("times read as dates and money as gold", setting("Every character", "Last scan time") == .date(Date(timeIntervalSince1970: 1_793_288_692))
              && setting("Every character", "Gold budget") == .gold(50_000) && setting("Masisi (8796093036412335)", "Gold spent") == .gold(12_850.5))
        if case .item(let title, let detail)? = setting("Masisi (8796093036412335)", "Last reward") {
            check("item links read as items with their set", title == "Item 29516" && detail?.hasPrefix("Vestments of the Warlock set") == true)
        } else {
            check("item links read as items with their set", false)
        }
        if case .name(let zone)? = setting("Masisi (8796093036412335)", "Zone ID") {
            check("IDs read as names, with the ID beside", zone.titleWithID == "Glenumbra (3)")
        } else {
            check("IDs read as names", false, "\(String(describing: setting("Masisi (8796093036412335)", "Zone ID")))")
        }
        // Names from the addon's own Lua source (docs/SOURCE-NAMES.md).
        let named = SVReadable.sheet(model.gameFolder.inspectorRows.map { LuaEntry(key: $0.key, value: $0.value, span: $0.span) },
                                     at: [], title: "WritWorthy", names: model.gameFolder.names, source: model.gameFolder.inspectorSourceNames["WritWorthy.lua"])
        @MainActor func row(_ section: String, key: String) -> SVReadable.Row? {
            named.first { $0.title == section }?.rows.first { $0.key == .string(key) }
        }
        check("a key takes its name from the addon's settings panel", row("Every character", key: "showMatCost")?.label == "Show material cost"
              && row("Every character", key: "showMatCost")?.source?.detail == "Show what a writ's materials cost in its tooltip."
              && row("Every character", key: "bAutoAccept")?.label == "Accept writs automatically", "\(named.first?.rows.map(\.label) ?? [])")
        check("a comment in the source describes a key, marked as a guess", row("Every character", key: "lastScanTime")?.source?.detail
              == "When the bank was last scanned for writs" && row("Every character", key: "lastScanTime")?.source?.isGuess == true)
        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide"), .string("byType")]
        check("a table keyed by game constants says so", model.gameFolder.inspectorFocus.last.flatMap { model.gameFolder.inspectorSourceNames["WritWorthy.lua"]?.note(forTable: $0) }?
            .hasPrefix("Keyed by SETTING_TYPE_* values") == true)
        model.gameFolder.inspectorFocus = []
        check("keys the source doesn't name keep their own label", row("Every character", key: "headerColor")?.label == "Header color"
              && row("Every character", key: "headerColor")?.source == nil)
        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide")]
        check("the tree finds the source's name for a key", model.gameFolder.inspectorSourceName(.string("showMatCost"), at: model.gameFolder.inspectorFocus)?.title == "Show material cost")
        model.gameFolder.inspectorFocus = []

        // AI names for keys the source rules can't name: asked with key names and source lines only.
        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide")]
        let unnamed = model.gameFolder.keysToNameWithAI
        check("AI is asked only about keys the source doesn't name", unnamed.contains("goldBudget") && unnamed.contains("tooltipStyle")
              && !unnamed.contains("showMatCost") && !unnamed.contains("bAutoAccept"), "\(unnamed)")
        let wwSource = SVSourceNames.sourceTexts(folder: model.addonsFolder.appending(path: "WritWorthy"))
        let evidence = SVAINaming.evidence(keys: unnamed, sources: wwSource)
        let aiPrompt = SVAINaming.prompt(addon: "WritWorthy", table: "WritWorthy.lua › $AccountWide", evidence: evidence)
        check("AI reads the lines that use a key, and never a saved value", evidence.map(\.key).contains("goldBudget") && !evidence.map(\.key).contains("tooltipStyle")
              && aiPrompt.contains("WritWorthy.savedVariables.goldBudget / 1000") && !aiPrompt.contains("50000") && !aiPrompt.contains("Compact"),
              "\(evidence.map(\.key))")
        let aiAnswer = "goldBudget = Gold budget in thousands\nshowMatCost = Something else\n"
        model.gameFolder.applyAINames(SVAINaming.parse(aiAnswer, keys: Set(evidence.map(\.key))), file: "WritWorthy.lua", folder: "WritWorthy",
                           version: Manifest.read(folder: model.addonsFolder.appending(path: "WritWorthy"))?.version ?? "", parent: "$AccountWide")
        let aiName = model.gameFolder.inspectorSourceName(.string("goldBudget"), at: model.gameFolder.inspectorFocus)
        check("an AI name shows as a guess", aiName?.title == "Gold budget in thousands" && aiName?.source == .ai && aiName?.isGuess == true)
        check("AI never replaces a name from the settings panel", model.gameFolder.inspectorSourceName(.string("showMatCost"), at: model.gameFolder.inspectorFocus)?.title == "Show material cost")
        check("AI names are kept for the addon's version", Store.loadAINames().entries(folder: "WritWorthy", version: Manifest.read(folder: model.addonsFolder.appending(path: "WritWorthy"))?.version ?? "")
            .contains { $0.key == "goldBudget" && $0.parent == "$AccountWide" })
        model.gameFolder.inspectorSourceNames = [:]
        await model.gameFolder.inspect("WritWorthy.lua")
        model.gameFolder.inspectorFocus = [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("$AccountWide")]
        check("AI names come back when the file is opened again", model.gameFolder.inspectorSourceName(.string("goldBudget"), at: model.gameFolder.inspectorFocus)?.source == .ai)
        check("only the open file's addon source is read", model.gameFolder.inspectorSourceNames.keys.sorted() == ["WritWorthy.lua"], "\(model.gameFolder.inspectorSourceNames.keys.sorted())")
        let aiBefore = model.prefs.aiProvider
        model.prefs.aiProvider = .claude
        await model.gameFolder.nameKeysWithAI()
        check("naming with AI says what's missing in Settings", model.gameFolder.errorMessage == "Add a Claude API key in Settings.", model.gameFolder.errorMessage ?? "")
        model.prefs.aiProvider = aiBefore
        model.gameFolder.errorMessage = nil
        model.gameFolder.inspectorFocus = []

        check("plain words stay plain", setting("Every character", "Tooltip style") == .text("Compact")
              && setting("Masisi (8796093036412335)", "Version") == .number("1"))
    }

    /// A 100 000-row table opens at once.
    static func bigTable(_ model: AppModel) async {
        let big = model.gameFolderURL.appending(path: "SavedVariables/BigList.lua")
        var bigText = "BigList =\n{\n"
        for i in 1...100_000 { bigText += "    [\(i)] = \"row \(i)\",\n" }
        try? (bigText + "}\n").write(to: big, atomically: true, encoding: .utf8)
        await model.gameFolder.scan()
        let opened = Date()
        await model.gameFolder.inspect("BigList.lua")
        let bigRows = model.gameFolder.inspectorRoots.first?.children?.count
        check("a 100 000-row table opens at once", bigRows == 100_000 && Date().timeIntervalSince(opened) < 3,
              "\(bigRows ?? 0) rows in \(Date().timeIntervalSince(opened)) s")
        try? FileManager.default.removeItem(at: big)
        await model.gameFolder.scan()
        model.gameFolder.tab = .characters
    }
}
