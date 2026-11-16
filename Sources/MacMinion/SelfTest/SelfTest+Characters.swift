import AppKit
import MacMinionKit

extension SelfTest {
    /// Character cards (S-049).
    static func characterCards(_ model: AppModel) async {
        // S-049 Character cards
        let cards = model.gameFolder.usage?.characters ?? []
        let masisiCard = cards.first { $0.id == "8796093036412335" }
        check("a card has the character's server, class, and level from the companion", masisiCard.map { characterLine(model, $0) }
              == "NA · Nightblade 50 · CP 2,410", masisiCard.map { characterLine(model, $0) } ?? "no card")
        check("a character no file names gets its own card, flagged", cards.contains { $0.id == "8796093079837777" && $0.flagged })
        if let masisiCard {
            let places = await model.gameFolder.characterPlaces(masisiCard)
            let writ = places.first { $0.file == "WritWorthy.lua" }
            check("a card lists what each addon keeps, opening at the character's table", writ?.addon == "WritWorthy"
                  && writ?.path == [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string("8796093036412335")]
                  && places.reduce(0) { $0 + $1.bytes } == masisiCard.bytes, "\(places.map(\.file))")
            if let writ {
                await model.gameFolder.reveal(file: writ.file, path: writ.path)
                check("Show opens the character in the Inspector", model.gameFolder.inspectorSelectedNode?.key == .string("8796093036412335"))
            }
        }
    }

    /// The connections map (S-051).
    static func connections(_ model: AppModel) async {
        // S-051 Connections map
        let masisiID = SVTarget(.character, "8796093036412335")
        await model.gameFolder.showConnections(masisiID)
        let hood = model.gameFolder.inspectorConnections
        check("the map puts the character in the middle", hood?.target == masisiID && model.gameFolder.tab == .inspector)
        check("files that mention it sit around it", Set(hood?.files.map(\.file) ?? []) == ["WritWorthy.lua", "ZO_Ingame.lua", "EsoMacMinion_Data.lua", "HarvestMap.lua", "AutoResearch.lua"])
        let around = Set(hood?.neighbors.map(\.target) ?? [])
        check("things stored with it sit around it", around.contains(SVTarget(.zone, "3")) && around.contains(SVTarget(.item, "29516")),
              "\(around.map(\.description))")
        await model.gameFolder.showConnections(SVTarget(.item, "29516"))
        let itemAround = Set(model.gameFolder.inspectorConnections?.neighbors.map(\.target) ?? [])
        check("following an item shows who sold it and in which guild", itemAround.contains(SVTarget(.account, "@Paltop"))
              && itemAround.contains(SVTarget(.guild, "Bandits Clan")), "\(itemAround.map(\.description))")
        await model.gameFolder.connectionsGoBack()
        check("Back returns to what you followed it from", model.gameFolder.inspectorConnections?.target == masisiID && model.gameFolder.connectionsBack.isEmpty)
        await model.gameFolder.revealFirst(masisiID, in: "WritWorthy.lua")
        check("a file on the map opens at the mention", model.gameFolder.inspectorConnections == nil && model.gameFolder.inspectorFile == "WritWorthy.lua"
              && model.gameFolder.inspectorSelectedNode?.key == .string("8796093036412335"))
        model.gameFolder.inspectorReadable = true
    }

    /// The Characters grid, Compare, and Copy Settings (S-053 to S-057, S-060, S-064, S-066).
    static func characters(_ model: AppModel) async {
        // S-053 to S-056 Characters and addons
        // S-064 Four tabs: Characters, Inspector, Problems, and Game Settings.
        check("Game Folder has four tabs, Characters first", GameFolderTab.top == [.characters, .inspector, .problems, .gameSettings])
        model.sidebar = .gameFolder
        check("Game Folder subtitle names SavedVariables, not the catalog",
              model.gameFolderStatusLine.contains("SavedVariables") && !model.gameFolderStatusLine.contains("updated"),
              model.gameFolderStatusLine)
        let matrix = model.gameFolder.matrix
        let masisiKey = "8796093036412335", alphaKey = "8798292071293572"
        check("the grid has the addons that keep per-character settings", Set(matrix?.addons.map(\.file) ?? []).isSuperset(of: ["WritWorthy.lua", "HarvestMap.lua"])
              && matrix?.characterIDs.contains(masisiKey) == true, "\(matrix?.addons.map(\.file) ?? [])")
        check("a character set up differently is outlined in the grid", matrix?.cell("WritWorthy.lua", masisiKey)?.odd == 1
              && matrix?.cell("HarvestMap.lua", alphaKey)?.odd == 1 && matrix?.cell("HarvestMap.lua", masisiKey)?.odd == 0)
        let ww = matrix?.addon("WritWorthy.lua")
        check("an addon shows what's set differently and who has each value", ww?.differing.contains("Auto craft") == true
              && ww?.values(of: "Auto craft").last?.characters == [masisiKey] && ww?.differing.contains("Max writs") == false)
        check("a character's odd ones out come with the usual value",
              ww?.oddOnesOut(masisiKey).first.map { $0.key == "Auto craft" && $0.usual.text == "true" } == true)
        model.gameFolder.tab = .characters
        model.gameFolder.explorerReset()
        model.gameFolder.explorerOpen(.character(masisiKey))
        model.gameFolder.explorerOpen(.characterAddon(id: masisiKey, file: "WritWorthy.lua"))
        model.gameFolder.explorerOpen(.setting(file: "WritWorthy.lua", key: "Auto craft"))
        check("digging down goes character, addon, setting", model.gameFolder.explorerPath.count == 4)
        model.gameFolder.explorerBack()
        check("Back goes up a level", model.gameFolder.explorerPath.last == .characterAddon(id: masisiKey, file: "WritWorthy.lua"))
        if let ww {
            check("Show in Inspector opens the character's table", model.gameFolder.characterTablePath(masisiKey, in: ww)
                  == [.string("WritWorthy_SavedVars"), .string("NA Megaserver"), .string("@SOLAEGIS"), .string(masisiKey)])
        }
        // Addons read in name order, not file order, wherever no other sort was chosen.
        if let matrix {
            let names = model.byName(matrix.addons, file: \.file).map { model.addonName($0.file) }
            check("Characters lists addons by the name shown",
                  names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(names)")
        }
        // S-057 Compare two characters
        let compared = matrix?.compare(masisiKey, alphaKey) ?? []
        check("comparing two characters lists what differs in each addon", compared.first { $0.file == "WritWorthy.lua" }?.differing.map(\.key) == ["Auto craft", "Writ count"]
              && compared.first { $0.file == "HarvestMap.lua" }?.differing.map(\.key) == ["Minimap pins"], "\(compared.map { "\($0.file): \($0.differing.map(\.key))" })")
        check("settings only one of them has are listed apart", compared.first { $0.file == "WritWorthy.lua" }?.onlyA.contains { $0.key == "Gold spent" } == true)
        // Characters by account, then megaserver
        check("characters are grouped by account, then megaserver",
              matrix?.accounts.map(\.account) == ["@SOLAEGIS", "@SolaegisAlt"]
              && matrix?.accounts.first?.servers.map(\.server) == ["EU Megaserver", "NA Megaserver"]
              && matrix?.homes["8798292033334444"]?.server == "EU Megaserver"
              && matrix?.characterIDs.prefix(2) == ["8798292033334444", alphaKey],
              "\(matrix?.accounts.map { "\($0.account): \($0.servers.map(\.server))" } ?? [])")
        // A name is unique only on one megaserver: Inspector groups and name-only characters carry it.
        let defaultTable = SVDocument.parse(Data("""
        T = { ["Default"] = { ["@SOLAEGIS"] = { ["\(masisiKey)"] = { ["a"] = 1 }, ["8798292033334444"] = { ["a"] = 1 }, ["Masisi"] = { ["a"] = 1 } } } }
        """.utf8))
        let defaultGroups = SVReadable.grouped(SVReadable.sheet(defaultTable.variables, at: [], title: "T", names: model.gameFolder.names,
                                                                locations: model.gameFolder.characterLocations))
        let groupTitles = Dictionary(uniqueKeysWithValues: defaultGroups.map { ($0.title ?? "", $0.sections.count) })
        check("Inspector groups Default-profile characters by account and megaserver",
              groupTitles["@SOLAEGIS · NA"] == 2 && groupTitles["@SOLAEGIS · EU"] == 1, "\(groupTitles)")
        let nameOnly = model.gameFolder.lastRead?.graph.nodes.keys.filter { $0.kind == .character && $0.key.hasPrefix("name:") } ?? []
        check("characters known only by name are kept apart by megaserver",
              nameOnly.allSatisfy { $0.key.split(separator: ":", omittingEmptySubsequences: false).count >= 4 }, "\(nameOnly)")
        check("an ID used as a key reads as the name, with the ID beside",
              SVReadable.label(.string(masisiKey), names: model.gameFolder.names) == "Masisi (8796093036412335)"
              && model.gameFolder.characterTitle(masisiKey) == "Masisi (8796093036412335)")
        check("the progress bar is gone once SavedVariables are read", model.gameFolder.progress == nil && model.gameFolder.loading == nil)
        model.gameFolder.explorerOpen(.compare(masisiKey, alphaKey, file: nil))
        check("a comparison is a level you can climb out of", model.gameFolder.explorerPath.last == .compare(masisiKey, alphaKey, file: nil))
        // S-060 Copy settings from one character to the other, one or all, either way.
        model.open(.gameFolder)
        model.gameFolder.tab = .characters
        check("Compare knows which two characters it shows", model.gameFolder.comparedCharacters.map { [$0.0, $0.1] } == [masisiKey, alphaKey])
        check("all-addons Compare has no file scope", model.gameFolder.comparedFile == nil)
        let svFolder = model.gameFolderURL.appending(path: "SavedVariables")
        var svBefore: [URL: Data] = [:]
        for file in model.gameFolder.savedVariables where file.name.hasSuffix(".lua") { svBefore[file.url] = try? Data(contentsOf: file.url) }
        let writURL = svFolder.appending(path: "WritWorthy.lua")
        @MainActor func writDiff() -> SettingsMatrix.Comparison? {
            model.gameFolder.matrix?.compare(masisiKey, alphaKey).first { $0.file == "WritWorthy.lua" }
        }
        model.simulatesRunningGame = true
        await model.gameFolder.copySettings([("WritWorthy.lua", "Auto craft")], from: masisiKey, to: alphaKey)
        check("copying refuses while the game runs", model.gameFolder.errorMessage != nil && (try? Data(contentsOf: writURL)) == svBefore[writURL])
        model.simulatesRunningGame = false
        check("Copy All takes every difference shown", model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey).count
              == compared.filter { !$0.isGame }.flatMap { c in c.differing.map { (c.file, $0.key) } }
                  .filter { model.gameFolder.copyTarget(file: $0.0, key: $0.1, from: masisiKey, to: alphaKey) != nil }.count)
        // Mixed directions in one Clone: Auto craft Masisi→Alpha, Writ count Alpha→Masisi.
        await model.gameFolder.applyCloneOps([
            .init(file: "WritWorthy.lua", key: "Auto craft", from: masisiKey, to: alphaKey),
            .init(file: "WritWorthy.lua", key: "Writ count", from: alphaKey, to: masisiKey),
        ])
        check("mixed clone makes both WritWorthy settings the same", writDiff()?.differing.isEmpty == true,
              "\(writDiff()?.differing.map(\.key) ?? []) \(model.gameFolder.errorMessage ?? "")")
        check("a clone says what it did", model.gameFolder.message?.contains("cloned") == true, model.gameFolder.message ?? "none")
        await model.gameFolder.copySettings([("WritWorthy.lua", "Gold spent")], from: masisiKey, to: alphaKey)
        check("a setting only one has can be given to the other", writDiff().map { !$0.onlyA.contains { $0.key == "Gold spent" } } ?? true)
        // Restore sample, then remove an only-one key by cloning from the empty side.
        for (url, data) in svBefore { try? data.write(to: url) }
        await model.gameFolder.scan()
        await model.gameFolder.load()
        await model.gameFolder.applyCloneOps([
            .init(file: "WritWorthy.lua", key: "Gold spent", from: alphaKey, to: masisiKey),
        ])
        check("cloning from the empty side removes the only-one key",
              model.gameFolder.matrix?.addons.first { $0.file == "WritWorthy.lua" }?.characters[masisiKey]?["Gold spent"] == nil,
              "\(model.gameFolder.matrix?.addons.first { $0.file == "WritWorthy.lua" }?.characters[masisiKey]?.keys.sorted() ?? [])")
        for (url, data) in svBefore { try? data.write(to: url) }
        await model.gameFolder.scan()
        await model.gameFolder.load()
        await model.gameFolder.copySettings(model.gameFolder.copyAllRows(from: alphaKey, to: masisiKey), from: alphaKey, to: masisiKey)
        await model.gameFolder.copySettings(model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey), from: masisiKey, to: alphaKey)
        check("cloning both ways leaves no differences",
              model.gameFolder.matrix?.compare(masisiKey, alphaKey).allSatisfy { $0.isGame || $0.differing.isEmpty } == true)
        // Dustman.lua is damaged on purpose in the sample; every file that read cleanly still does.
        let brokenAfter = model.gameFolder.savedVariables.filter { file in
            guard let before = svBefore[file.url], SVDocument.parse(before).error == nil else { return false }
            return (try? SVDocument.read(file.url))?.error != nil
        }
        check("every file still reads cleanly after copying", brokenAfter.isEmpty, "\(brokenAfter.map(\.name))")
        for (url, data) in svBefore { try? data.write(to: url) }
        await model.gameFolder.scan()
        await model.gameFolder.load()
        check("the sample files are back as they were", writDiff()?.differing.map(\.key) == ["Auto craft", "Writ count"])
        model.gameFolder.message = nil
        model.gameFolder.errorMessage = nil
        // S-066 Compare two characters in one addon, from character-in-addon.
        model.gameFolder.explorerPath = [.grid, .character(masisiKey), .characterAddon(id: masisiKey, file: "WritWorthy.lua")]
        model.gameFolder.explorerOpen(.compare(masisiKey, alphaKey, file: "WritWorthy.lua"))
        check("a scoped comparison is a level you can climb out of",
              model.gameFolder.explorerPath.last == .compare(masisiKey, alphaKey, file: "WritWorthy.lua"))
        check("scoped Compare knows its addon file", model.gameFolder.comparedFile == "WritWorthy.lua"
              && model.gameFolder.comparedCharacters.map { [$0.0, $0.1] } == [masisiKey, alphaKey])
        let writOnly = model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey, file: "WritWorthy.lua")
        check("scoped Copy All is only that addon's differences",
              writOnly.map(\.file).allSatisfy { $0 == "WritWorthy.lua" }
              && Set(writOnly.map(\.key)) == Set(compared.first { $0.file == "WritWorthy.lua" }?.differing.map(\.key) ?? []),
              "\(writOnly)")
        check("scoped Copy All is fewer than every addon",
              writOnly.count < model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey).count)
        await model.gameFolder.copySettings(writOnly, from: masisiKey, to: alphaKey)
        check("scoped clone clears that addon's differences",
              model.gameFolder.matrix?.compare(masisiKey, alphaKey).first { $0.file == "WritWorthy.lua" }?.differing.isEmpty == true,
              "\(model.gameFolder.matrix?.compare(masisiKey, alphaKey).first { $0.file == "WritWorthy.lua" }?.differing.map(\.key) ?? [])")
        check("scoped clone leaves other addons' differences",
              model.gameFolder.matrix?.compare(masisiKey, alphaKey).first { $0.file == "HarvestMap.lua" }?.differing.map(\.key) == ["Minimap pins"])
        model.gameFolder.explorerBack()
        check("Back from scoped Compare returns to character-in-addon",
              model.gameFolder.explorerPath.last == .characterAddon(id: masisiKey, file: "WritWorthy.lua"))
        for (url, data) in svBefore { try? data.write(to: url) }
        await model.gameFolder.scan()
        await model.gameFolder.load()
        check("the sample files are back after scoped clone", writDiff()?.differing.map(\.key) == ["Auto craft", "Writ count"])
        model.gameFolder.message = nil
        model.gameFolder.errorMessage = nil
        // Two characters with one name: Compare adds each one's megaserver, and only then.
        let velvet = "8798292033334444"
        let velvetName = model.gameFolder.names?.characters[velvet]
        model.gameFolder.lastRead?.names.characters[velvet] = (name: "Masisi", source: "test")
        check("same-named characters show their megaserver in Compare",
              model.gameFolder.compareName(masisiKey, other: velvet) == "Masisi (NA)" && model.gameFolder.compareName(velvet, other: masisiKey) == "Masisi (EU)"
              && model.gameFolder.compareName(masisiKey, other: alphaKey) == "Masisi",
              "\(model.gameFolder.compareName(masisiKey, other: velvet)) / \(model.gameFolder.compareName(velvet, other: masisiKey))")
        model.gameFolder.lastRead?.names.characters[velvet] = velvetName
        check("packed data and timestamps aren't settings",
              model.gameFolder.matrix?.addons.allSatisfy { $0.characters.values.allSatisfy { $0.values.allSatisfy { s in
                  !(s.value.string.map(SettingsMatrix.isPacked) ?? false)
              } } } == true)
    }

    /// The game's own addons on a character's page, and cloning which addons load (S-068, S-069).
    static func defaultAddonsAndChoices(_ model: AppModel) async {
        let masisiKey = "8796093036412335", alphaKey = "8798292071293572", emberKey = "8796093011112222"
        // S-068 The game's own addons join a character's graph and Compare only when asked.
        check("Show All Addons starts off", model.prefs.showAllAddons == false)
        let matrix = model.gameFolder.matrix
        check("the game's files are known as the game's", matrix?.addon("ZO_Ingame.lua")?.isGame == true
              && matrix?.addon("WritWorthy.lua")?.isGame == false)
        check("the game's files each get their own name", model.addonName("ZO_Ingame.lua") == String(localized: "The game (\("Ingame"))")
              && model.addonName("ZO_Ingame.lua") != model.addonName("ZO_Pregame.lua"), model.addonName("ZO_Ingame.lua"))
        check("the game keeps per-character settings in ZO_Ingame",
              matrix?.addon("ZO_Ingame.lua")?.characters[masisiKey]?.isEmpty == false,
              "\(matrix?.addon("ZO_Ingame.lua")?.characters.keys.sorted() ?? [])")
        check("with the checkbox off, Copy All leaves the game's files alone",
              !model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey).contains { SettingsMatrix.isGame($0.file) })
        model.prefs.showAllAddons = true
        check("with the checkbox on, Copy All includes the game's differences",
              model.gameFolder.copyAllRows(from: masisiKey, to: alphaKey).contains { $0.file == "ZO_Ingame.lua" })
        check("an account-wide game file is there to show",
              model.gameFolder.savedVariables.contains { $0.name == "ZO_Pregame.lua" && $0.owner == .game }
              && matrix?.addon("ZO_Pregame.lua") == nil)
        model.prefs.showAllAddons = false

        // S-070 Default addon profiles: AutoResearch keeps nothing of Masisi's but bookkeeping, and Alpha Top uses
        // the account-wide settings; both run on its defaults, from its source.
        let research = model.gameFolder.addonDefaults["AutoResearch.lua"]?.first
        check("an addon's defaults are read from its source", research?.variable == "AutoResearch_Character"
              && research?.libSavedVars == true && research?.unresolved.values.contains("ITEM_FUNCTIONAL_QUALITY_ARCANE") == true,
              "\(model.gameFolder.addonDefaults.keys.sorted())")
        let auto = model.gameFolder.matrix?.addon("AutoResearch.lua")
        check("a character with only bookkeeping runs on the defaults", auto?.profile(masisiKey) == .defaults
              && auto?.characters[masisiKey]?.values.contains { SettingsMatrix.isBookkeeping($0) } == false,
              "\(String(describing: auto?.profile(masisiKey)))")
        check("a character on LibSavedVars' account-wide settings gets them over the defaults", auto?.profile(alphaKey) == .accountWide,
              "\(String(describing: auto?.profile(alphaKey)))")
        let bagsKey = auto?.characters[masisiKey]?.keys.first { $0.hasSuffix("Bags") }
        if let bagsKey {
            check("defaults and account-wide values show where they come from",
                  auto?.source(masisiKey, bagsKey) == .defaults && auto?.source(alphaKey, bagsKey) == .account)
            check("Compare sees the default against the account-wide value",
                  model.gameFolder.matrix?.compare(masisiKey, alphaKey).first { $0.file == "AutoResearch.lua" }?.differing.contains { $0.key == bagsKey } == true)
            check("nothing is cloned to a character on account-wide settings",
                  model.gameFolder.copyTarget(file: "AutoResearch.lua", key: bagsKey, from: masisiKey, to: alphaKey) == nil)
        } else {
            check("AutoResearch's defaults reach the matrix", false, "\(auto?.characters[masisiKey]?.keys.sorted() ?? [])")
        }
        check("a constant in the defaults is never compared", auto?.characters[masisiKey]?.keys.contains { $0.contains("Max quality") } == false)
        check("characters on defaults have no grid cell", model.gameFolder.matrix?.cell("AutoResearch.lua", masisiKey) == nil
              && !(model.gameFolder.matrix?.onlyHere(masisiKey).contains("AutoResearch.lua") ?? true))

        // S-069 Compare and clone which addons each character loads (AddOnSettings.txt).
        model.gameFolder.loadGameSettings()
        let url = model.gameFolderURL.appending(path: AddOnChoices.fileName)
        let before = (try? Data(contentsOf: url)) ?? Data()
        check("a character's list in AddOnSettings.txt is found by megaserver and name",
              model.gameFolder.addOnHeader(masisiKey) == "NA Megaserver-Masisi" && model.gameFolder.addOnHeader(alphaKey) == "NA Megaserver-Alpha Top",
              model.gameFolder.addOnHeader(alphaKey) ?? "none")
        let rows = model.gameFolder.addOnRows(masisiKey, alphaKey) ?? []
        check("Compare lists the addons two characters load differently",
              rows.first { $0.addon == "HarvestMap" }.map { $0.a == true && $0.b == false } == true
              && rows.first { $0.addon == "WritWorthy" }?.differs == false, "\(rows)")
        check("a character with no list of their own uses #Default", model.gameFolder.addOnsFromDefault(emberKey)
              && model.gameFolder.addOnValue(emberKey, addon: "pChat") == true)
        let harvest = SettingsMatrix.CloneOp(file: AddOnChoices.fileName, key: "HarvestMap", from: masisiKey, to: alphaKey)
        model.simulatesRunningGame = true
        await model.gameFolder.applyCloneOps([harvest])
        check("cloning addon choices refuses while the game runs", model.gameFolder.errorMessage != nil && (try? Data(contentsOf: url)) == before)
        model.simulatesRunningGame = false
        let backupsBefore = model.backups.count
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        MainUndo.override = undo
        model.gameFolder.copyBackedUp = []
        await model.gameFolder.applyCloneOps([harvest])
        undo.endUndoGrouping()
        let after = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
        check("cloning an addon choice changes only that line",
              after == String(decoding: before, as: UTF8.self).replacingOccurrences(of: "#NA Megaserver-Alpha Top\nHarvestMap 0", with: "#NA Megaserver-Alpha Top\nHarvestMap 1"),
              after)
        check("cloning addon choices backs up first", model.backupError == nil
              && model.gameFolder.copyBackedUp.contains([masisiKey, alphaKey].sorted().joined(separator: "|")), "\(backupsBefore) backups before")
        check("cloning addon choices says what it did", model.gameFolder.message?.contains("addon choice") == true, model.gameFolder.message ?? "none")
        check("they now load HarvestMap the same", model.gameFolder.addOnRows(masisiKey, alphaKey)?.first { $0.addon == "HarvestMap" }?.differs == false)
        undo.undo()
        await MainUndo.settle()
        check("Undo puts AddOnSettings.txt back byte for byte", (try? Data(contentsOf: url)) == before)
        MainUndo.override = nil
        // A character with no list gets one, starting from #Default.
        model.gameFolder.loadGameSettings()
        model.gameFolder.copyAddOnChoices(from: masisiKey, to: emberKey)
        check("Copy Addon Choices From opens Compare with the other's choices picked",
              model.gameFolder.explorerPath.last == .compare(emberKey, masisiKey, file: nil)
              && model.gameFolder.cloneSources[.init(file: AddOnChoices.fileName, key: "HarvestMap")] == masisiKey,
              "\(model.gameFolder.cloneSources)")
        await model.gameFolder.applyCloneOps(model.gameFolder.selectedCloneOps())
        let ember = model.gameFolder.addOnChoices?.blocks["NA Megaserver-Quiet Ember"]
        check("cloning to a character with no list gives them one, from #Default",
              ember?["pChat"] == true && ember?["MasterMerchant"] == false && ember?["HarvestMap"] == true && ember?["WritWorthy"] == true,
              "\(ember ?? [:]) \(model.gameFolder.errorMessage ?? "")")
        try? before.write(to: url)
        model.gameFolder.loadGameSettings()
        model.gameFolder.explorerReset()
        model.gameFolder.message = nil
        model.gameFolder.errorMessage = nil
    }

    /// The game's settings files: edit, save, undo (S-062).
    static func gameSettings(_ model: AppModel) async {
        // S-062 The game's settings files, edited as typed fields and saved line by line.
        model.gameFolder.loadGameSettings()
        let userURL = model.gameFolderURL.appending(path: "UserSettings.txt")
        let userBefore = (try? Data(contentsOf: userURL)) ?? Data()
        if let user = model.gameFolder.gameSettings[.user], let fps = user.fields.first(where: { $0.key == "BACKGROUND_FPS_LIMIT" }) {
            let types = Dictionary(uniqueKeysWithValues: user.fields.map { ($0.key, $0.type) })
            check("settings get an editor that fits their value",
                  types["InvertMouseY"] == .toggle && types["BACKGROUND_FPS_LIMIT"] == .integer
                  && types["MouseSensitivityFirstPerson"] == .decimal && types["PlayerWaypointIconColor"] == .color
                  && model.gameFolder.gameSettings[.machine]?.fields.first { $0.key == "RESOLUTION" }?.type == .size)
            model.gameFolder.setGameSetting(fps, in: .user, to: "30")
            model.simulatesRunningGame = true
            await model.gameFolder.saveGameSettings(.user)
            check("saving settings refuses while the game runs", (try? Data(contentsOf: userURL)) == userBefore && model.gameFolder.gameSettingsEdits(.user) == 1)
            model.simulatesRunningGame = false
            let undo = UndoManager()
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            MainUndo.override = undo
            await model.gameFolder.saveGameSettings(.user)
            undo.endUndoGrouping()
            let savedData = (try? Data(contentsOf: userURL)) ?? Data()
            let saved = String(decoding: savedData, as: UTF8.self)
            check("saving rewrites only the changed line, keeping CRLF",
                  saved == String(decoding: userBefore, as: UTF8.self).replacingOccurrences(of: "BACKGROUND_FPS_LIMIT \"60\"", with: "BACKGROUND_FPS_LIMIT \"30\"")
                  && model.gameFolder.gameSettingsEdits(.user) == 0, saved)
            // Rule 43: Edit › Undo puts the file back as it was, and Redo writes the save again.
            check("Undo names the save", undo.canUndo && undo.undoActionName == String(localized: "Save Game Settings"), undo.undoActionName)
            undo.undo()
            await MainUndo.settle()
            check("Undo after Save puts the file back byte for byte", (try? Data(contentsOf: userURL)) == userBefore)
            undo.redo()
            await MainUndo.settle()
            check("Redo writes the save again", (try? Data(contentsOf: userURL)) == savedData)
            try? userBefore.write(to: userURL)
            MainUndo.override = nil
        } else {
            check("the sample UserSettings.txt reads", false)
        }
        if let addOns = model.gameFolder.gameSettings[.addOns],
           let harvest = addOns.fields.first(where: { $0.section == "NA Megaserver-Alpha Top" && $0.key == "HarvestMap" }) {
            check("AddOnSettings reads each character's addons", harvest.value == "0" && harvest.type == .toggle)
            model.gameFolder.setGameSetting(harvest, in: .addOns, to: "1")
            model.gameFolder.setGameSetting(harvest, in: .addOns, to: "0")
            check("an edit set back to the file's value isn't an edit", model.gameFolder.gameSettingsEdits(.addOns) == 0)
        }
        if let zip = model.backups.first?.zip {
            check("backups keep MachineSettings.txt too", MinionBackup.files(in: zip).contains("MachineSettings.txt"),
                  "\(MinionBackup.files(in: zip).filter { !$0.hasPrefix("SavedVariables") })")
        }
    }

    /// An account's megaservers and one megaserver's characters (S-061).
    static func accountsAndServers(_ model: AppModel) async {
        let masisiKey = "8796093036412335"
        // S-061 An account's megaservers, then one megaserver's characters, from the grid's header.
        model.gameFolder.explorerReset()
        model.gameFolder.explorerOpen(.account("@SOLAEGIS"))
        model.gameFolder.explorerOpen(.server(account: "@SOLAEGIS", server: "NA Megaserver"))
        let naCharacters = model.gameFolder.matrix?.accounts.first { $0.account == "@SOLAEGIS" }?.servers.first { $0.server == "NA Megaserver" }?.characters ?? []
        check("a megaserver's graph holds that account's characters on it",
              model.gameFolder.explorerPath == [.grid, .account("@SOLAEGIS"), .server(account: "@SOLAEGIS", server: "NA Megaserver")]
              && naCharacters.contains(masisiKey) && !naCharacters.contains("8798292033334444"))
        // Back on Characters after the Inspector: the character you were on, not every character.
        model.gameFolder.explorerReset()
        model.gameFolder.explorerOpen(.character(masisiKey))
        model.gameFolder.tab = .inspector
        model.gameFolder.tab = .characters
        model.gameFolder.explorerResume()
        check("the Characters tab returns to the last character", model.gameFolder.explorerPath == [.grid, .character(masisiKey)])
        model.gameFolder.explorerPath = [.grid, .character("8796093000000000"), .characterAddon(id: "8796093000000000", file: "WritWorthy.lua")]
        model.gameFolder.explorerResume()
        check("a character that's gone trims the path back", model.gameFolder.explorerPath == [.grid])
        model.gameFolder.explorerReset()
        model.gameFolder.tab = .characters
    }
}
