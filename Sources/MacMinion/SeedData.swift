import Foundation
import MacMinionKit

/// Sample data for snapshots and the self-test: APP_SEED=1 (or --selftest) with
/// APP_STORE in /tmp builds an AddOns folder and a small catalog in the store,
/// with zips on disk so installs and updates run without the network.
@MainActor
enum SeedData {
    struct Sample {
        let id: Int, name: String, author: String, category: Int, version: String
        let dirs: [String], downloads: Int, daysAgo: Double
        /// Installed version, nil when not installed. "manifest" means found on disk only.
        var installed: String?
        var ignored = false
    }

    static let samples: [Sample] = [
        Sample(id: 7, name: "LibAddonMenu-2.0", author: "sirinsidiator", category: 53, version: "2.0 r43",
               dirs: ["LibAddonMenu-2.0"], downloads: 6_330_822, daysAgo: 3, installed: "2.0 r42"),
        Sample(id: 57, name: "HarvestMap", author: "Shinni", category: 17, version: "3.16.5",
               dirs: ["HarvestMap", "HarvestMapData"], downloads: 2_904_113, daysAgo: 12, installed: "3.16.5"),
        Sample(id: 1605, name: "WritWorthy", author: "ziggr", category: 18, version: "7.5.4",
               dirs: ["WritWorthy"], downloads: 1_120_448, daysAgo: 1, installed: "7.5.2"),
        Sample(id: 97, name: "Dustman", author: "Garkin, Ayantir", category: 18, version: "5.4.1",
               dirs: ["Dustman"], downloads: 986_200, daysAgo: 40, installed: "manifest"),
        Sample(id: 1146, name: "LibCustomMenu", author: "votan", category: 53, version: "7.3.1",
               dirs: ["LibCustomMenu"], downloads: 2_210_007, daysAgo: 8, installed: "7.3.0", ignored: true),
        Sample(id: 1360, name: "Master Merchant 3.0", author: "Sharlikran", category: 17, version: "3.8.21",
               dirs: ["MasterMerchant"], downloads: 3_402_116, daysAgo: 2),
        Sample(id: 695, name: "AwesomeGuildStore", author: "sirinsidiator", category: 17, version: "1.12.4",
               dirs: ["AwesomeGuildStore"], downloads: 4_118_930, daysAgo: 6),
        Sample(id: 1536, name: "Lazy Writ Crafter", author: "Dolgubon", category: 18, version: "4.2.1",
               dirs: ["DolgubonsLazyWritCreator"], downloads: 3_877_451, daysAgo: 20),
        Sample(id: 2163, name: "Inventory Insight", author: "manavortex, Baertram", category: 17, version: "3.93",
               dirs: ["IIfA"], downloads: 1_654_002, daysAgo: 90),
        Sample(id: 2275, name: "LibDebugLogger", author: "sirinsidiator", category: 53, version: "2.6.1",
               dirs: ["LibDebugLogger"], downloads: 1_402_550, daysAgo: 60),
        Sample(id: 1594, name: "LibLazyCrafting", author: "Dolgubon", category: 53, version: "4.026",
               dirs: ["LibLazyCrafting"], downloads: 2_118_904, daysAgo: 25),
        Sample(id: 1245, name: "Bandits User Interface", author: "Hoft", category: 17, version: "4.12",
               dirs: ["BanditsUserInterface"], downloads: 1_998_113, daysAgo: 30),
    ]

    static let categories = [
        AddonCategory(id: 23, title: "Graphic & Plug-ins", parentIDs: [0]),
        AddonCategory(id: 17, title: "Graphic UI Mods", parentIDs: [0, 23]),
        AddonCategory(id: 18, title: "Character Advancement", parentIDs: [0, 23]),
        AddonCategory(id: 53, title: "Libraries", parentIDs: [0]),
    ]

    static var requested: Bool {
        ProcessInfo.processInfo.environment["APP_SEED"] == "1" || SelfTest.requested
    }

    static func insertIfRequested(into model: AppModel) async {
        guard requested else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a folder in /tmp")
            return
        }
        let fm = FileManager.default
        let addons = model.addonsFolder
        let zips = Store.directory.appending(path: "zips", directoryHint: .isDirectory)
        try? fm.createDirectory(at: addons, withIntermediateDirectories: true)
        try? fm.createDirectory(at: zips, withIntermediateDirectories: true)

        var records: [Int: InstallRecord] = [:]
        var details: [Int: AddonDetails] = [:]
        for s in samples {
            if let v = s.installed {
                let shown = v == "manifest" ? s.version : v
                for dir in s.dirs { writeAddon(dir, version: shown, author: s.author, in: addons) }
                if v != "manifest" { records[s.id] = InstallRecord(id: s.id, version: v, dirs: s.dirs, ignored: s.ignored) }
            }
            if let zip = makeZip(s, in: zips) {
                details[s.id] = AddonDetails(
                    id: s.id, version: s.version, md5: Installer.md5((try? Data(contentsOf: zip)) ?? Data()),
                    fileName: zip.lastPathComponent, downloadURL: zip,
                    description: "[B]\(s.name)[/B] by \(s.author).\r\n\r\nSample text for snapshots.\r\n[LIST][*]Works offline[*]Installs from a local zip[/LIST]",
                    changelog: "\(s.version)\r\n- updated for Season One\r\n- fixed a rare error on login")
            }
        }
        // A folder no catalog entry lists, like an addon you build yourself.
        writeAddon("EsoVendorJunk", version: "1.4.0", author: "solaegis", in: addons)
        // MacMinion Companion: a first-party addon that is not on ESOUI.
        writeCompanion(in: addons)
        let companionSrc = Store.directory.appending(path: "companion-src/\(CompanionData.folderName)")
        try? FileManager.default.createDirectory(at: companionSrc.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: companionSrc)
        try? FileManager.default.copyItem(at: addons.appending(path: CompanionData.folderName), to: companionSrc)

        let catalog = samples.map { s in
            CatalogAddon(id: s.id, categoryID: s.category, version: s.version,
                         date: .now.addingTimeInterval(-s.daysAgo * 86_400), name: s.name, author: s.author,
                         infoURL: URL(string: "https://www.esoui.com/downloads/info\(s.id).html"),
                         downloads: s.downloads, downloadsMonthly: s.downloads / 120, favorites: s.downloads / 1_500,
                         compatibility: [GameVersion(version: "12.1.0", name: "Season One")], dirs: s.dirs)
        }
        await model.load(catalog: catalog, categories: categories, details: details, records: records, history: sampleHistory)
        // Snapshots show the assistant set up, with one finished summary. Nothing is sent: the store is in /tmp.
        model.prefs.aiProvider = .ollama
        model.prefs.ollamaModel = "llama3.2"
        // HarvestMap's archive: the latest and two older releases, as local zips.
        if let harvest = samples.first(where: { $0.id == 57 }) {
            var files: [Int: URL] = [:]
            let list = [ArchivedVersion(aid: 9003, version: "3.16.5", size: "1.2MB", date: "10/14/26 09:12 AM"),
                        ArchivedVersion(aid: 9002, version: "3.16.4", size: "1.2MB", date: "09/02/26 06:40 PM"),
                        ArchivedVersion(aid: 9001, version: "3.15.9", size: "1.1MB", date: "07/21/26 11:05 AM")]
            for v in list { files[v.aid] = makeZip(harvest, in: zips, version: v.version) }
            model.setSampleArchives(list, for: 57, files: files)
        }
        model.setSampleSearch("track my crafting writs", [
            AddonSuggestion(id: 1536, reason: "Crafts every daily writ in one click when you open a crafting station."),
            AddonSuggestion(id: 1605, reason: "Shows what a master writ is worth and what it takes, before you accept it."),
        ])
        // The game folder around AddOns: SavedVariables and settings files, a backup from three days ago,
        // and a Minion-style first backup of the whole AddOns folder.
        let game = model.gameFolderURL
        try? fm.createDirectory(at: game.appending(path: "SavedVariables"), withIntermediateDirectories: true)
        for name in ["HarvestMap", "WritWorthy", "LibAddonMenu"] {
            try? "\(name)_SavedVars =\n{\n    [\"Default\"] = { version = 1 },\n}\n"
                .write(to: game.appending(path: "SavedVariables/\(name).lua"), atomically: true, encoding: .utf8)
        }
        // The game's settings files as it writes them (S-062): UserSettings with CRLF endings, the others with LF.
        let addOnSettings = "#Version 101051\n#AcknowledgedOutOfDateAddonsVersion 101050\n#AddOnsEnabled 1\n#Default\npChat 1\nMasterMerchant 0\n"
            + "#NA Megaserver-Masisi\nHarvestMap 1\nWritWorthy 1\nLibAddonMenu-2.0 1\n#NA Megaserver-Alpha Top\nHarvestMap 0\nWritWorthy 1\n"
        try? addOnSettings.write(to: game.appending(path: "AddOnSettings.txt"), atomically: true, encoding: .utf8)
        let userSettings = [("Language.2", "en"), ("LastRealm", "NA Megaserver"), ("MouseSensitivityFirstPerson", "0.85000002"),
                            ("InvertMouseY", "1"), ("USE_BACKGROUND_FPS_LIMIT", "0"), ("BACKGROUND_FPS_LIMIT", "60"),
                            ("PlayerWaypointIconColor", "ffa4ecee"), ("ScreenshotFormat.2", "PNG"), ("SUBTITLES_ENABLED", "1")]
        try? userSettings.map { "SET \($0.0) \"\($0.1)\"\r\n" }.joined()
            .write(to: game.appending(path: "UserSettings.txt"), atomically: true, encoding: .utf8)
        try? "SET TerrainShadowsEnabled \"1\"\nSET RESOLUTION \"2560x1440\"\n"
            .write(to: game.appending(path: "MachineSettings.txt"), atomically: true, encoding: .utf8)
        // The rest of a real game folder (S-028, S-029): the game's own SavedVariables, one left by a removed
        // addon, a copy, a module nested inside HarvestMap, caches, logs, and copies kept beside AddOns.
        let nested = addons.appending(path: "HarvestMap/Modules/HarvestMapAD", directoryHint: .isDirectory)
        try? fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try? "## Title: HarvestMap AD\n## SavedVariables: HarvestMapAD_SavedVars\n".write(to: nested.appending(path: "HarvestMapAD.txt"), atomically: true, encoding: .utf8)
        for dir in ["GuildHistory", "Logs", "Screenshots", "SavedVariables.bak-prune-20261006"] {
            try? fm.createDirectory(at: game.appending(path: dir), withIntermediateDirectories: true)
        }
        // S-052: data that keeps growing. HarvestMap AD's node list is long enough and big enough to be both a
        // long list and a large file, so Problems groups them into one "keeps growing" finding.
        var nodes = "HarvestMapAD_SavedVars =\n{\n    [\"nodes\"] =\n    {\n"
        let node = String(repeating: "x", count: 1_010)
        for i in 1...SVProblems.longList { nodes += "        [\(i)] = \"\(node)\",\n" }
        try? (nodes + "    },\n}\n").write(to: game.appending(path: "SavedVariables/HarvestMapAD.lua"), atomically: true, encoding: .utf8)
        let extras: [(String, Int)] = [("SavedVariables/EsoSocial.lua", 420_000), ("SavedVariables/HarvestMap.lua.bak-20261024", 60_000),
                                       ("SavedVariables.bak-prune-20261006/HarvestMap.lua", 60_000),
                                       ("AddOnSettings.txt.bak-20260829", 4_000), ("ShaderCache.cooked", 2_000_000),
                                       ("PipelineCache.esopc", 700_000), ("GuildHistory/4000_1.dat", 90_000),
                                       ("Logs/interface.log", 72_000)]
        for (path, size) in extras {
            // SavedVariables get a real variable around the padding, so they read like the game's own.
            if path.hasSuffix(".lua") {
                let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".lua", with: "")
                let text = "\(name)_SavedVars =\n{\n    [\"data\"] = \"" + String(repeating: "-", count: size) + "\",\n}\n"
                try? text.write(to: game.appending(path: path), atomically: true, encoding: .utf8)
            } else {
                try? Data(repeating: 0x2D, count: size).write(to: game.appending(path: path))
            }
        }
        writeInspectorSamples(game: game, addons: addons)
        let backupDir = model.prefs.backupFolder, gameID = model.prefs.backupGameID
        _ = try? MinionBackup.create(gameFolder: game, addonIDs: records.keys.sorted(), backupDir: backupDir, gameID: gameID,
                                     date: .now.addingTimeInterval(-3 * 86_400))
        let initial = MinionBackup.initialZip(backupDir: backupDir, gameID: gameID)
        try? fm.createDirectory(at: initial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ZipWriter.write([ZipWriter.Entry(name: addons.appending(path: "Dustman/Dustman.txt").path,
                                              data: Data("## Title: Dustman\n## Version: 5.0\n".utf8), modified: .now)], to: initial)
        model.loadBackups()
        model.setSampleSuggestions([
            AddonSuggestion(id: 1360, reason: "Tracks guild store prices and sales history, so AwesomeGuildStore shows what items are worth."),
            AddonSuggestion(id: 1536, reason: "Crafts daily writs in one click; pairs with WritWorthy, which already values master writs."),
            AddonSuggestion(id: 1245, reason: "Replaces the stock HUD with configurable frames, a different job from anything installed."),
        ])
        model.setSampleSummary("• Fixes a Lua error when opening the settings panel after Season One.\n• Dropdowns size correctly inside submenus again.\n• Adds Turkish and Ukrainian translations.", for: 7)
    }

    /// Half a year of updates: libraries and busy addons often, others now and then. The older half came from Minion.
    static var sampleHistory: [HistoryEvent] {
        let cadence: [(String, Int, Double)] = [  // name, id, days between updates
            ("LibAddonMenu-2.0", 7, 21), ("HarvestMap", 57, 9), ("WritWorthy", 1605, 6),
            ("Dustman", 97, 45), ("LibCustomMenu", 1146, 30),
        ]
        var events: [HistoryEvent] = []
        for (offset, (name, id, every)) in cadence.enumerated() {
            var day = Double(offset) * 2 + 1
            var minor = 40
            while day < 180 {
                events.append(HistoryEvent(date: .now.addingTimeInterval(-day * 86_400), addonID: id, name: name,
                                           version: "1.\(minor + 1)", previousVersion: "1.\(minor)",
                                           kind: .update, fromMinion: day > 60))
                minor -= 1
                day += every
            }
        }
        events.append(HistoryEvent(date: .now.addingTimeInterval(-3 * 3_600), addonID: 1360, name: "Master Merchant 3.0",
                                   version: "3.8.21", kind: .install))
        events.append(HistoryEvent(date: .now.addingTimeInterval(-26 * 3_600), addonID: 1360, name: "Master Merchant 3.0",
                                   version: "3.8.20", kind: .remove))
        return events
    }

    /// Dependencies the sample manifests declare, so the Overview's library card has something to show.
    static let dependencies: [String: String] = [
        "HarvestMap": "## OptionalDependsOn: LibDebugLogger LibStub\n",
        "WritWorthy": "## DependsOn: LibLazyCrafting>=4000\n## OptionalDependsOn: LibDebugLogger\n",
    ]

    /// SavedVariables with the ZO_SavedVars levels and IDs to name (S-036, S-037), LibGuildStore's
    /// indexes, and small data files for LibSets, LibZone, and LibQuestData inside WritWorthy/libs.
    static func writeInspectorSamples(game: URL, addons: URL) {
        let fm = FileManager.default
        let sv = game.appending(path: "SavedVariables")
        let files: [(URL, String)] = [
            (sv.appending(path: "ZO_Ingame.lua"), """
            ZO_Ingame_SavedVariables =
            {
                ["Default"] =
                {
                    ["@SOLAEGIS"] =
                    {
                        ["$AccountWide"] =
                        {
                            ["NameChange"] =
                            {
                                ["8796093036412335"] = "Masisi",
                                ["8798292071293572"] = "Alpha Top",
                                ["8796093011112222"] = "Quiet Ember",
                                ["8798292033334444"] = "Velvet Thorn",
                            },
                        },
                    },
                },
            }

            """),
            (sv.appending(path: "WritWorthy.lua"), """
            WritWorthy_SavedVars =
            {
                ["NA Megaserver"] =
                {
                    ["@SOLAEGIS"] =
                    {
                        ["$AccountWide"] =
                        {
                            ["version"] = 1,
                            ["byType"] = { [3] = { [12] = 1 }, [14] = { [2] = 0 } },
                            ["showMatCost"] = true,
                            ["bAutoAccept"] = false,
                            ["matCostColor"] =
                            {
                                ["r"] = 0.36,
                                ["g"] = 0.79,
                                ["b"] = 0.65,
                                ["a"] = 1,
                            },
                            ["headerColor"] = "|cEF9F27",
                            ["lastScanTime"] = 1793288692,
                            ["goldBudget"] = 50000,
                            ["tooltipStyle"] = "Compact",
                        },
                        ["8796093036412335"] =
                        {
                            ["version"] = 1,
                            ["$LastCharacterName"] = "Masisi",
                            ["zoneId"] = 3,
                            ["questId"] = 30,
                            ["setId"] = 19,
                            ["achievementId"] = 1000,
                            ["lastReward"] = "|H1:item:29516:363:50:0:0:0:0:0:0:0:0:0:0:0:0:9:0:1:0:300:0|h|h",
                            ["lastWrit"] = "|H1:item:119682:5:1:0:0:0:65:192:4:224:16:110:0:0:0:0:0:0:0:0:61500|h|h",
                            ["writCount"] = 42,
                            ["goldSpent"] = 12850.5,
                            ["autoCraft"] = false,
                            ["maxWrits"] = 10,
                        },
                        ["8798292071293572"] =
                        {
                            ["version"] = 1,
                            ["writCount"] = 3,
                            ["autoCraft"] = true,
                            ["maxWrits"] = 10,
                        },
                        ["8796093079837777"] =
                        {
                            ["version"] = 1,
                            ["writCount"] = "7",
                            ["autoCraft"] = true,
                            ["maxWrits"] = 10,
                        },
                    },
                },
            }

            """),
            (sv.appending(path: "HarvestMap.lua"), """
            HarvestMap_SavedVars =
            {
                ["NA Megaserver"] =
                {
                    ["@SOLAEGIS"] =
                    {
                        ["$AccountWide"] =
                        {
                            ["version"] = 1,
                            ["farmingMode"] = false,
                            ["pinColor"] = { ["r"] = 0.36, ["g"] = 0.79, ["b"] = 0.65, ["a"] = 1 },
                        },
                        ["8796093036412335"] = { ["showOnMap"] = true, ["minimapPins"] = true, ["pinSize"] = 20 },
                        ["8798292071293572"] = { ["showOnMap"] = true, ["minimapPins"] = false, ["pinSize"] = 20 },
                        ["8796093079837777"] = { ["showOnMap"] = true, ["minimapPins"] = true, ["pinSize"] = 32 },
                    },
                    ["@SolaegisAlt"] =
                    {
                        ["8796093011112222"] = { ["showOnMap"] = true, ["minimapPins"] = true, ["pinSize"] = 20 },
                    },
                },
                ["EU Megaserver"] =
                {
                    ["@SOLAEGIS"] =
                    {
                        ["8798292033334444"] = { ["showOnMap"] = false, ["minimapPins"] = true, ["pinSize"] = 20 },
                    },
                },
            }

            """),
            (sv.appending(path: "GS16Data.lua"), """
            GS16DataSavedVariables =
            {
                ["itemLink"] =
                {
                    ["|H0:item:29516:363:50:0:0:0:0:0:0:0:0:0:0:0:0:9:0:0:0:300:0|h|h"] = 7,
                },
                ["guildNames"] =
                {
                    ["Bandits Clan"] = 118,
                },
            }

            """),
            (sv.appending(path: "GS17Data.lua"), """
            GS17DataSavedVariables =
            {
                ["accountNames"] =
                {
                    ["@Paltop"] = 21531,
                },
                ["memberNotes"] =
                {
                    ["@Paltop"] =
                    {
                        ["note"] = "Sells Vestments of the Warlock below market",
                    },
                },
            }

            """),
            (sv.appending(path: "GS00Data.lua"), """
            GS00DataSavedVariables =
            {
                ["dataeu"] =
                {
                    [29516] =
                    {
                        ["sales"] =
                        {
                            [1] =
                            {
                                ["itemLink"] = 7,
                                ["seller"] = 21531,
                                ["guild"] = 118,
                                ["price"] = 4500,
                            },
                        },
                    },
                },
            }

            """),
        ]
        // S-039: a file the game stopped writing halfway, and a log that keeps growing under a
        // variable the manifest doesn't declare (it declares LibDebugLogger_SavedVars).
        var log = "LibDebugLoggerLog =\n{\n"
        for i in 1...SVProblems.longList { log += "    [\(i)] = \"line \(i)\",\n" }
        let problemFiles: [(URL, String)] = [
            (sv.appending(path: "Dustman.lua"),
             "Dustman_SavedVars =\n{\n    [\"Default\"] =\n    {\n        [\"@SOLAEGIS\"] =\n        {\n            [\"$AccountWide\"] =\n            {\n                [\"junkName\"] = \"Mudcrab Ch"),
            (sv.appending(path: "LibDebugLogger.lua"), log + "}\n"),
        ]
        let libs = addons.appending(path: "WritWorthy/libs")
        var all = files + problemFiles
        all += [
            (libs.appending(path: "LibSets/Data/LibSets_Data_SetNames.lua"),
             "    setDataPreloaded[LIBSETS_TABLEKEY_SETNAMES]={[19]={[\"en\"]=\"Vestments of the Warlock\"}}\n"),
            (libs.appending(path: "LibSets/Data/LibSets_Data_SetItemIds.lua"),
             "    setDataPreloaded[LIBSETS_TABLEKEY_SETITEMIDS]={[19]={[1]=\"29513,3\"}}\n"),
            (libs.appending(path: "LibZone/LibZone_Data.lua"), "preloadedZoneNames = {\n\t[\"en\"] = { [3] = \"Glenumbra\" },\n}\n"),
            (libs.appending(path: "LibQuestData/quest_names/LibQuestData_QuestNames_en.lua"),
             "lib.quest_names[\"en\"] = {\n  [30] = \"Dark Brotherhood Assassination\",\n}\n"),
        ]
        // WritWorthy's settings panel, so the Inspector can name its keys from the addon's source.
        all.append((addons.appending(path: "WritWorthy/WritWorthy_Settings.lua"), #"""
        ZO_CreateStringId("SI_WRITWORTHY_MAT_COST", "Show material cost")
        WritWorthy.Types = { SETTING_TYPE_CAMERA, SETTING_TYPE_COMBAT }
        for _, t in pairs(WritWorthy.Types) do WritWorthy.Default.byType[t] = {} end
        local defaults = {
            lastScanTime = 0, -- When the bank was last scanned for writs
        }
        local options = {
            {
                type = "checkbox",
                name = GetString(SI_WRITWORTHY_MAT_COST),
                tooltip = "Show what a writ's materials cost in its tooltip.",
                getFunc = function() return WritWorthy.savedVariables.showMatCost end,
            },
            {
                type = "slider",
                name = function() return "Budget" end,
                getFunc = function() return math.floor(WritWorthy.savedVariables.goldBudget / 1000) end,
            },
            {
                type = "checkbox",
                name = "Accept writs automatically",
                getFunc = function() return WritWorthy.savedVariables.bAutoAccept end,
            },
        }
        """#))
        // MacMinion Companion snapshot (S-042, S-043, S-049): roster, addon states, a Lua error, and a guild.
        all.append((sv.appending(path: CompanionData.fileName), """
        EsoMacMinion_Data =
        {
            ["NA Megaserver"] =
            {
                ["@SOLAEGIS"] =
                {
                    ["$AccountWide"] =
                    {
                        ["version"] = 1,
                        ["schema"] = 1,
                        ["written"] = 1793288692,
                        ["env"] = { ["apiVersion"] = 101051, ["gameVersion"] = "12.1.6", ["server"] = "NA Megaserver", ["language"] = "en", ["companionVersion"] = "0.1.0" },
                        ["characters"] =
                        {
                            ["8796093036412335"] = { ["name"] = "Masisi", ["class"] = 3, ["race"] = 9, ["alliance"] = 1, ["level"] = 50, ["champion"] = 2410, ["lastPlayed"] = 1793288692 },
                            ["8798292071293572"] = { ["name"] = "Alpha Top", ["class"] = 6, ["race"] = 7, ["alliance"] = 3, ["level"] = 50 },
                        },
                        ["addons"] =
                        {
                            ["WritWorthy"] = { ["title"] = "WritWorthy", ["version"] = "7.5.2", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = false, ["isLibrary"] = false },
                            ["WizardsWardrobe"] = { ["title"] = "Wizard's Wardrobe", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = false, ["isLibrary"] = false },
                            ["Dustman"] = { ["title"] = "Dustman", ["version"] = "5.0", ["enabled"] = true, ["state"] = "loaded", ["outOfDate"] = true, ["isLibrary"] = false },
                            ["MissingLibAddon"] = { ["title"] = "Missing Lib Addon", ["enabled"] = true, ["state"] = "missing", ["outOfDate"] = false, ["isLibrary"] = false, ["missing"] = { [1] = "LibLazyCrafting" } },
                        },
                        ["errors"] =
                        {
                            [1] = { ["addon"] = "WizardsWardrobe", ["at"] = 1793288692, ["count"] = 12, ["message"] = "user:/AddOns/WizardsWardrobe/ui.lua:212: attempt to index a nil value" },
                        },
                        ["guilds"] =
                        {
                            ["761817"] = { ["name"] = "Alphabet Mafia", ["members"] = 437, ["server"] = "NA Megaserver" },
                        },
                        ["enabledBy"] =
                        {
                            ["8796093036412335"] = { ["at"] = 1793288692, ["disabled"] = { } },
                            ["8798292071293572"] = { ["at"] = 1793288000, ["disabled"] = { [1] = "WizardsWardrobe" } },
                        },
                    },
                },
            },
        }

        """))
        // LibGuildStore's data addons, three folders deep (the most the game loads), so their files belong to an installed addon.
        for name in ["GS00Data", "GS16Data", "GS17Data"] {
            all.append((libs.appending(path: "\(name)/\(name).txt"), "## Title: \(name)\n## SavedVariables: \(name)SavedVariables\n"))
        }
        for (url, text) in all {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func writeCompanion(in addons: URL) {
        let folder = addons.appending(path: CompanionData.folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = "## Title: ESO Mac Minion\n## Author: solaegis\n## Version: 0.1.0\n## APIVersion: 101051\n"
            + "## SavedVariables: EsoMacMinion_Data\n## Description: MacMinion companion.\n"
        try? text.write(to: folder.appending(path: "\(CompanionData.folderName).txt"), atomically: true, encoding: .utf8)
    }

    private static func writeAddon(_ dir: String, version: String, author: String, in addons: URL) {
        let folder = addons.appending(path: dir, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = "## Title: \(dir)\n## Author: \(author)\n## Version: \(version)\n## APIVersion: 101048\n"
            + "## SavedVariables: \(dir.filter { $0.isLetter || $0.isNumber })_SavedVars\n\(dependencies[dir] ?? "")\n\(dir).lua\n"
        try? text.write(to: folder.appending(path: "\(dir).txt"), atomically: true, encoding: .utf8)
    }

    private static func makeZip(_ s: Sample, in zips: URL, version: String? = nil) -> URL? {
        let tag = version.map { "-\($0.filter { $0.isLetter || $0.isNumber })" } ?? ""
        let staging = zips.appending(path: "src-\(s.id)\(tag)", directoryHint: .isDirectory)
        for dir in s.dirs { writeAddon(dir, version: version ?? s.version, author: s.author, in: staging) }
        let zip = zips.appending(path: "\(s.id)\(tag).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", staging.path, zip.path]
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? zip : nil
    }
}
