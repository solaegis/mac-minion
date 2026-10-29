import Foundation
import Testing
@testable import MacMinionKit

@Test func decodesCatalogEntry() throws {
    let json = """
    [{"UID":"7","UICATID":"53","UIVersion":"2.0 r43","UIDate":1778599485000,"UIName":"LibAddonMenu-2.0",
      "UIAuthorName":"sirinsidiator","UIDownloadTotal":"6330822","UIDownloadMonthly":"25382","UIFavoriteTotal":"3101",
      "UICompatibility":[{"version":"12.0.0","name":"Season Zero Pt.2"}],"UIDir":["LibAddonMenu-2.0"],
      "UIIMG_Thumbs":["https://cdn-eso.mmoui.com/preview/tiny/pvw3588.jpg"],"UIIMGs":null,"UISiblings":null}]
    """
    let addons = try MMOUIClient.decodeCatalog(Data(json.utf8))
    #expect(addons.count == 1)
    let a = try #require(addons.first)
    #expect(a.id == 7 && a.categoryID == 53 && a.downloads == 6_330_822)
    #expect(a.dirs == ["LibAddonMenu-2.0"])
    #expect(a.images.isEmpty && a.thumbnails.count == 1)
    #expect(Int(a.date.timeIntervalSince1970) == 1_778_599_485)
}

@Test func parsesManifest() {
    let m = Manifest.parse("""
    ## Title: |cFF0000HarvestMap|r
    ## Author: Shinni
    ## Version: 3.16.5
    ## IsLibrary: true
    ## DependsOn: LibAddonMenu-2.0>=30 LibMapPins-1.0
    Main/HarvestMap.lua
    """)
    #expect(m.title == "HarvestMap")
    #expect(m.version == "3.16.5")
    #expect(m.isLibrary)
    #expect(m.dependsOn == ["LibAddonMenu-2.0", "LibMapPins-1.0"])
}

@Test func plainTextFromBBCode() {
    let s = BBCode.plainText("[B]Hi[/B]\r\n[LIST][*]one[*]two[/LIST] [URL=\"https://x.y\"]site[/URL]")
    #expect(s == "Hi\n• one\n• two site (https://x.y)")
}

@Test("Versions compare loosely", arguments: [("2.0 r43", "2.0r43", true), ("v1.2", "1.2", true), ("1.2", "1.3", false)])
func versions(_ a: String, _ b: String, _ same: Bool) {
    #expect(VersionText.same(a, b) == same)
}

private func addon(_ id: Int, _ dirs: [String], version: String = "1", downloads: Int = 0) -> CatalogAddon {
    CatalogAddon(id: id, categoryID: 1, version: version, date: .now, name: "A\(id)", author: "x", downloads: downloads, dirs: dirs)
}

@Test func matchesFoldersToCatalog() {
    let catalog = [addon(1, ["Alpha"]), addon(2, ["Beta", "BetaData"]), addon(3, ["Beta"], downloads: 9_999), addon(4, ["Gamma"], version: "2")]
    let folders: [String: Manifest?] = ["Alpha": nil, "Beta": nil, "BetaData": nil, "Gamma": nil, "MyOwn": Manifest(title: "Mine")]
    let records = [4: InstallRecord(id: 4, version: "1", dirs: ["Gamma"])]
    let r = AddonMatcher.match(folders: folders, catalog: catalog, records: records)
    #expect(Set(r.installed.map(\.id)) == [1, 2, 4], "the entry covering more folders wins over the popular one")
    #expect(r.unmatched.map(\.title) == ["Mine"])
    #expect(r.installed.first { $0.id == 4 }?.status == .updateAvailable)
    #expect(r.installed.first { $0.id == 1 }?.status == .versionUnknown)
}

@Test func unreadableFolderIsNotEmpty() {
    #expect(AddonMatcher.scan(URL(fileURLWithPath: "/no/such/AddOns")) == nil)
}

@Test func manifestVersionCountsAsUpToDate() {
    let r = AddonMatcher.match(folders: ["Alpha": Manifest(version: "1")], catalog: [addon(1, ["Alpha"])], records: [:])
    #expect(r.installed.first?.status == .upToDate)
}

@Test func ignoredIsNotAnUpdate() {
    let records = [1: InstallRecord(id: 1, version: "0", dirs: ["Alpha"], ignored: true)]
    let r = AddonMatcher.match(folders: ["Alpha": nil], catalog: [addon(1, ["Alpha"])], records: records)
    #expect(r.installed.first?.status == .ignored)
}

@Test func importsMinionXML() throws {
    let path = Data("/Users/me/AddOns".utf8).base64EncodedString()
    let xml = """
    <minion><games><game game-id="ESO" addon-path="\(path)">
      <auto-updated><addon date="10.12.2025 7:00AM" title="T" version="1"/><addon date="11.04.2025 5:25PM" title="T" version="2"/><addon date="bad" title="U" version="1"/></auto-updated>
      <addons><addon md5="abc" ui-version="1.32" uid="2079"><dirs><dir>LibFeedback</dir></dirs></addon></addons>
    </game></games></minion>
    """
    let game = try #require(MinionImport.parse(Data(xml.utf8)))
    #expect(game.addonPath == "/Users/me/AddOns")
    #expect(game.records[2079] == InstallRecord(id: 2079, version: "1.32", md5: "abc", dirs: ["LibFeedback"]))
    #expect(game.records.count == 1)
    #expect(game.history.map(\.version) == ["1", "2"], "the log is read in order and bad dates are skipped")
    #expect(game.history.last?.previousVersion == "1")
    #expect(game.history.allSatisfy { $0.fromMinion && $0.kind == .update })
}

@Test func weeklyCountsFillEmptyWeeks() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 28)))
    func event(_ daysAgo: Double, _ kind: HistoryEvent.Kind = .update) -> HistoryEvent {
        HistoryEvent(date: now.addingTimeInterval(-daysAgo * 86_400), addonID: nil, name: "A", version: nil, kind: kind)
    }
    let weeks = Usage.weekly([event(0), event(1), event(14), event(0, .remove)], weeks: 4, now: now, calendar: cal)
    #expect(weeks.map(\.count) == [0, 1, 0, 2])
}

@Test func mostUpdatedAndShortNames() {
    let e = ["B", "A", "B", "C", "A", "B"].map { HistoryEvent(date: .now, addonID: nil, name: $0, version: nil, kind: .update) }
    #expect(Usage.mostUpdated(e, limit: 2).map(\.name) == ["B", "A"])
    #expect(Usage.shortName("pChat (Chat customization & help)") == "pChat")
    #expect(Usage.shortName("(odd)") == "(odd)")
}

@Test func oldStateFilesStillLoad() throws {
    let state = try JSONDecoder().decode(SavedState.self, from: Data(#"{"records":{},"importedFromMinion":true}"#.utf8))
    #expect(state.importedFromMinion && !state.importedMinionHistory && state.history.isEmpty)
}

@Test func categoryDescendants() {
    let all = [AddonCategory(id: 23, title: "UI", parentIDs: [0]), AddonCategory(id: 17, title: "Graphic", parentIDs: [0, 23]),
               AddonCategory(id: 5, title: "Other", parentIDs: [0])]
    #expect(AddonCategory.descendants(of: 23, in: all) == [23, 17])
}

@Test func installSwapsFoldersAndRollsBack() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "mm-test-\(UUID().uuidString)")
    let addons = root.appending(path: "AddOns")
    let src = root.appending(path: "src/Alpha")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try "## Version: 2".write(to: src.appending(path: "Alpha.txt"), atomically: true, encoding: .utf8)
    try fm.createDirectory(at: addons.appending(path: "Alpha"), withIntermediateDirectories: true)
    try "## Version: 1".write(to: addons.appending(path: "Alpha/Alpha.txt"), atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: root) }

    let zip = root.appending(path: "a.zip")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--keepParent", src.path, zip.path]
    try p.run(); p.waitUntilExit()
    let md5 = Installer.md5(try Data(contentsOf: zip))

    let installer = Installer(addons: addons)
    await #expect(throws: InstallError.checksum) {
        _ = try await installer.install(AddonDetails(id: 1, version: "2", md5: "bad", fileName: "a.zip", downloadURL: zip))
    }
    #expect(Manifest.read(folder: addons.appending(path: "Alpha"))?.version == "1", "a bad checksum leaves the old folder")

    let record = try await installer.install(AddonDetails(id: 1, version: "2", md5: md5, fileName: "a.zip", downloadURL: zip))
    #expect(record.dirs == ["Alpha"] && record.version == "2")
    #expect(Manifest.read(folder: addons.appending(path: "Alpha"))?.version == "2")
}

@Test func bentoPacksDensely() {
    // A 2x2 hero, then small cards: they fill the two columns beside it before starting a new row.
    let (slots, rows) = BentoPacker.place([.large, .small, .small, .small, .small, .small], columns: 4)
    #expect(slots.map { [$0.column, $0.row] } == [[0, 0], [2, 0], [3, 0], [2, 1], [3, 1], [0, 2]])
    #expect(rows == 3)
}

@Test func bentoShrinksWideCardsOnNarrowGrids() {
    let (slots, rows) = BentoPacker.place([.wide, .small], columns: 1)
    #expect(slots.map(\.span) == [.small, .small])
    #expect(rows == 2)
}

@Test func bentoFillsGapsLeftByWideCards() {
    // Three columns: wide, wide leaves a gap at the end of row 0 that the next small card takes.
    let (slots, _) = BentoPacker.place([.wide, .wide, .small], columns: 3)
    #expect(slots.map { [$0.column, $0.row] } == [[0, 0], [0, 1], [2, 0]])
}

@Test func changelogSinceInstalled() {
    let log = "2.0 r43\n- fixed a crash\n\n2.0 r42 (consoles only)\n- console thing\n\n2.0 r41\n- old"
    #expect(ChangelogText.since("2.0 r42", in: log, limit: 10_000) == .init(text: "2.0 r43\n- fixed a crash", shortened: false))
    #expect(ChangelogText.since("9.9", in: log, limit: 10_000).text == log, "an unknown version keeps everything")
    #expect(ChangelogText.since("2.0 r43", in: log, limit: 10_000).text == "2.0 r43\n- fixed a crash",
            "on the latest version, only the latest entry")
    #expect(ChangelogText.since("2.0 r4", in: log, limit: 10_000).text == log, "2.0 r4 is not 2.0 r43")
    let short = ChangelogText.since(nil, in: log, limit: 30)
    #expect(short.shortened && short.text == "2.0 r43\n- fixed a crash")
}

@Test func recommendsAGeneralModelThatFits() throws {
    let tags = #"{"models":[{"name":"nomic-embed-text:latest","size":274000000,"details":{"family":"nomic-bert","parameter_size":"137M"}},{"name":"phi4:latest","size":9100000000,"details":{"family":"phi3","parameter_size":"14.7B","context_length":16384}},{"name":"llama3.3:70b","size":42500000000,"details":{"family":"llama","parameter_size":"70.6B"}},{"name":"qwen2.5-coder:14b","size":9000000000,"details":{"family":"qwen2","parameter_size":"14.8B"}},{"name":"gemma4:latest","size":9500000000,"details":{"family":"","parameter_size":""}}]}"#
    let models = try OllamaModel.decodeTags(Data(tags.utf8))
    #expect(models.first { $0.name == "gemma4:latest" }.map { Int($0.billions) } == 15, "no parameter_size: estimated from the file size")
    func host(_ gb: UInt64, free: UInt64) -> HostProfile {
        HostProfile(chip: "Apple M2 Ultra", memoryBytes: gb << 30, availableBytes: free << 30, performanceCores: 16)
    }
    let pick = try #require(ModelAdvisor.recommend(models.filter { !$0.isEmbedding }, host: host(192, free: 120)))
    #expect(pick.model == "gemma4:latest" && pick.reason.contains("Apple M2 Ultra"))
    #expect(ModelAdvisor.rank(models, host: host(16, free: 12)).map(\.name) == ["gemma4:latest", "phi4:latest"],
            "coding and embedding models never; llama 70B doesn't fit in 16 GB")
    #expect(ModelAdvisor.rank(models, host: host(8, free: 6)).isEmpty, "nothing here fits in 8 GB with room to spare")
    // Free memory now: 9.3 GB free fits phi4 (9.1 GB) but not gemma4 (9.5 GB).
    let tight = HostProfile(chip: "Apple M2", memoryBytes: 16 << 30, availableBytes: 9_300_000_000, performanceCores: 4)
    #expect(ModelAdvisor.recommend(models, host: tight)?.model == "phi4:latest")
    // A measured slow model loses to a comfortable one.
    let slow = ["gemma4:latest": ModelSpeed(tokensPerSecond: 6, loadSeconds: 1), "phi4:latest": ModelSpeed(tokensPerSecond: 40, loadSeconds: 1)]
    #expect(ModelAdvisor.recommend(models, host: host(192, free: 120), speeds: slow)?.model == "phi4:latest")
}

@Test func readsBenchmarkTimings() throws {
    let speed = try AIClient.parseTimings(Data(#"{"eval_count":44,"eval_duration":1000000000,"load_duration":500000000}"#.utf8))
    #expect(speed.tokensPerSecond == 44 && speed.loadSeconds == 0.5)
    let host = HostProfile.current()
    #expect(host.memoryBytes > 0 && host.availableBytes > 0 && host.availableBytes <= host.memoryBytes)
}

@Test func suggestionCandidatesSkipInstalledAndLibraries() {
    func a(_ id: Int, _ cat: Int, _ monthly: Int) -> CatalogAddon {
        CatalogAddon(id: id, categoryID: cat, version: "1", date: .now, name: "A\(id)", author: "x", downloadsMonthly: monthly, dirs: ["A\(id)"])
    }
    let catalog = [a(1, 17, 900), a(2, 17, 800), a(3, 53, 5_000), a(4, 18, 700), a(5, 18, 10), a(6, 17, 1)]
    #expect(!AddonRecommender.candidates(catalog: catalog, installed: [6], folders: ["A1"]).contains { $0.id == 1 },
            "a fork that installs into a folder on disk is left out")
    let picked = AddonRecommender.candidates(catalog: catalog, installed: [6], limit: 3)
    #expect(!picked.contains { $0.id == 3 || $0.id == 6 }, "no libraries, nothing installed")
    #expect(picked.map(\.id) == [1, 2, 4], "the installed addon's category first, then the most popular")
}

@Test func parsesSuggestions() {
    let answer = """
    Here are my picks:
    1360 | Adds price history to the guild store, next to AwesomeGuildStore.
    • 42 - Not a candidate.
    [695]: Better guild store filters.
    1360 | Repeat.
    """
    let s = AddonRecommender.parse(answer, candidates: [1360, 695])
    #expect(s.map(\.id) == [1360, 695])
    #expect(s.first?.reason == "Adds price history to the guild store, next to AwesomeGuildStore.")
}

@Test func promptGroupsInstalledAddonsWithWhatTheyDo() {
    let p = AddonRecommender.prompt(
        installed: [.init(id: 1, name: "Wizard's Wardrobe", category: "Action Bar Mods", blurb: "Saves gear and skill setups."),
                    .init(id: 2, name: "AUI", category: "Graphic UI Mods", blurb: "")],
        candidates: [.init(id: 1812, name: "AlphaGear 2", category: "Action Bar Mods", blurb: "Gear, skill, and build sets.", monthly: 900)])
    #expect(p.contains("Action Bar Mods:\n- Wizard's Wardrobe: Saves gear and skill setups."))
    #expect(p.contains("Graphic UI Mods:\n- AUI"))
    #expect(p.contains("1812: AlphaGear 2 [Action Bar Mods, 900 downloads this month] Gear, skill, and build sets."))
    #expect(p.contains("second gear or build manager"))
}

@Test func blurbsAreShortPlainText() {
    let long = "[B]HarvestMap[/B] shows resource nodes on the map and compass. It records what you gather. [URL=https://x.y]Docs[/URL] More text follows here that goes on and on and on for a long while to pass the limit."
    let b = AddonRecommender.blurb(long, limit: 100)
    #expect(b == "HarvestMap shows resource nodes on the map and compass. It records what you gather.")
    #expect(AddonRecommender.blurb("Short one, long enough to keep.") == "Short one, long enough to keep.")
    let noisy = "The addon for TTC needs localization help! Help translate it.\nShows Tamriel Trade Centre price info in item tooltips."
    #expect(AddonRecommender.blurb(noisy) == "Shows Tamriel Trade Centre price info in item tooltips.")
    #expect(Manifest.parse("## Description: Remind you time to refresh your actions.").description == "Remind you time to refresh your actions.")
}

@Test func parsesArchivedVersions() {
    let html = """
    <div class="title">Archived Files (2)</div><table><tr><td class="thead">x</td></tr>
    <tr><td class="alt1"><div class="smallfont"><img src="zip.gif" />&nbsp;<a href="/downloads/getfile.php?s=abc&amp;id=7&amp;aid=53953">LibAddonMenu-2.0</a></div></td>
    <td class="alt1"><div class="smallfont">2.0 r43</div></td><td class="alt1"><div class="smallfont">50kB</div></td>
    <td class="alt1"><div class="smallfont">sirinsidiator</div></td><td class="alt1"><div class="smallfont">10/28/25 01:49 PM</div></td></tr>
    <tr><td class="alt2"><div class="smallfont"><a href="/downloads/getfile.php?id=7&amp;aid=51481">LibAddonMenu-2.0</a></div></td>
    <td class="alt2"><div class="smallfont">2.0 r40</div></td><td class="alt2"><div class="smallfont">51kB</div></td>
    <td class="alt2"><div class="smallfont">sirinsidiator</div></td><td class="alt2"><div class="smallfont">05/30/25 10:28 AM</div></td></tr>
    </table><a href="getfile.php?id=7&amp;aid=999">not archived</a>
    """
    let v = ESOUIArchive.parse(html)
    #expect(v == [ArchivedVersion(aid: 53953, version: "2.0 r43", size: "50kB", date: "10/28/25 01:49 PM"),
                  ArchivedVersion(aid: 51481, version: "2.0 r40", size: "51kB", date: "05/30/25 10:28 AM")])
    #expect(ESOUIArchive.downloadURL(id: 7, aid: 51481).absoluteString == "https://www.esoui.com/downloads/getfile.php?id=7&aid=51481")
}

@Test func tasteGoesIntoPrompts() {
    let taste = Taste(liked: ["HarvestMap"], disliked: ["AlphaGear 2"])
    #expect(taste.promptLines.contains("thumbs up to: HarvestMap") && taste.promptLines.contains("thumbs down to: AlphaGear 2"))
    #expect(Taste().promptLines.isEmpty)
    let p = AddonRecommender.prompt(installed: [], candidates: [], taste: taste)
    #expect(p.contains("Avoid addons like these."))
}

@Test func aiSearchPlanAndCandidates() {
    let plan = AddonSearch.parsePlan("keywords: writ, crafting, Daily\ncategories: 18, 99x", query: "auto craft my writs")
    #expect(plan.keywords.prefix(3) == ["writ", "crafting", "daily"])
    #expect(plan.keywords.contains("writs") && plan.keywords.contains("craft") && !plan.keywords.contains("my"),
            "the request's own words count; short ones don't")
    #expect(plan.categories == [18, 99])
    func a(_ id: Int, _ name: String, _ cat: Int, _ monthly: Int) -> CatalogAddon {
        CatalogAddon(id: id, categoryID: cat, version: "1", date: .now, name: name, author: "x", downloadsMonthly: monthly, dirs: [name])
    }
    let catalog = [a(1, "Lazy Writ Crafter", 18, 30_000), a(2, "WritWorthy", 18, 9_000), a(3, "HarvestMap", 17, 50_000),
                   a(4, "Dustman", 18, 100), a(5, "Writ Helper", 18, 10)]
    let found = AddonSearch.candidates(catalog: catalog, plan: plan, blurbs: [4: "junks items after crafting"], excluded: [5])
    #expect(found.map(\.id) == [1, 2, 4], "name hits first, then a description hit; excluded and unrelated addons left out")
}

@Test func findsMissingLibraries() {
    func lib(_ id: Int, _ dir: String, _ cat: Int = AddonCategory.librariesID, downloads: Int = 0) -> CatalogAddon {
        CatalogAddon(id: id, categoryID: cat, version: "1", date: .now, name: dir, author: "x", downloads: downloads, dirs: [dir])
    }
    let catalog = [lib(2275, "LibDebugLogger"), lib(1594, "LibLazyCrafting"), lib(7, "LibAddonMenu-2.0"),
                   lib(93, "pChat", 17), lib(1, "LibStub"), lib(5, "LibChatMessage", downloads: 9),
                   CatalogAddon(id: 6, categoryID: 53, version: "1", date: .now, name: "Bundle", author: "x", downloads: 99,
                                dirs: ["LibChatMessage", "Other"])]
    var harvest = Manifest(title: "HarvestMap")
    harvest.optionalDependsOn = ["LibDebugLogger", "LibAddonMenu-2.0", "pChat", "LibStub", "LibChatMessage", "NotOnESOUI"]
    var writ = Manifest(title: "WritWorthy")
    writ.dependsOn = ["LibLazyCrafting"]
    writ.optionalDependsOn = ["LibDebugLogger"]
    let folders: [String: Manifest?] = ["HarvestMap": harvest, "WritWorthy": writ, "LibAddonMenu-2.0": nil]
    let missing = LibraryAdvisor.missing(folders: folders, catalog: catalog)
    #expect(missing.map(\.folder) == ["LibLazyCrafting", "LibDebugLogger", "LibChatMessage"],
            "required first, then most wanted; installed, obsolete, non-library, and unknown names left out")
    #expect(missing.first?.required == true && missing[1].wantedBy == ["HarvestMap", "WritWorthy"])
    #expect(missing.last?.addon.id == 5, "the entry that installs just that folder wins over a bundle")
    #expect(Manifest.parse("## OptionalDependsOn: LibA>=30 LibB\n## DependsOn: LibC<=2").optionalDependsOn == ["LibA", "LibB"])
    #expect(LibraryAdvisor.missing(folders: folders, nested: ["LibLazyCrafting"], catalog: catalog).first?.folder == "LibDebugLogger",
            "a library bundled inside another addon counts as installed")
}

@Test func findsBundledLibraries() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "mm-nested-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    for path in ["SuperStar/libs/LibSkillsFactory", "CharacterKnowledge/LibExtendedJournal", "Deep/a/b/c/LibTooDeep", "Plain/libs/NoManifest"] {
        try fm.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
    }
    try "".write(to: root.appending(path: "SuperStar/libs/LibSkillsFactory/LibSkillsFactory.txt"), atomically: true, encoding: .utf8)
    try "".write(to: root.appending(path: "CharacterKnowledge/LibExtendedJournal/LibExtendedJournal.addon"), atomically: true, encoding: .utf8)
    try "".write(to: root.appending(path: "Deep/a/b/c/LibTooDeep/LibTooDeep.txt"), atomically: true, encoding: .utf8)
    #expect(AddonMatcher.nested(root) == ["LibSkillsFactory", "LibExtendedJournal"])
}

@Test func browseFiltersNarrowTheList() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func a(_ id: Int, cat: Int, daysAgo: Double, compat: [String]) -> CatalogAddon {
        CatalogAddon(id: id, categoryID: cat, version: "2", date: now.addingTimeInterval(-daysAgo * 86_400), name: "A\(id)", author: "x",
                     compatibility: compat.map { GameVersion(version: $0, name: "S") }, dirs: ["A\(id)"])
    }
    let fresh = a(1, cat: 17, daysAgo: 3, compat: ["12.1.0"])
    let old = a(2, cat: 53, daysAgo: 400, compat: ["9.3.0"])
    let current = CurrentGame.current(in: [fresh, old])?.version
    #expect(current == "12.1.0")
    func pass(_ f: BrowseFilter, _ addon: CatalogAddon, installed: InstalledAddon? = nil, rating: Rating? = nil, cats: Set<Int>? = nil) -> Bool {
        f.matches(addon, installed: installed, rating: rating, categories: cats, currentGame: current, now: now)
    }
    #expect(!BrowseFilter().isActive && pass(BrowseFilter(), old))
    #expect(pass(BrowseFilter(recency: .week), fresh) && !pass(BrowseFilter(recency: .year), old))
    #expect(pass(BrowseFilter(compatibleOnly: true), fresh) && !pass(BrowseFilter(compatibleOnly: true), old))
    #expect(!pass(BrowseFilter(hideLibraries: true), old))
    #expect(!pass(BrowseFilter(rating: .hideDisliked), fresh, rating: .down) && pass(BrowseFilter(rating: .liked), fresh, rating: .up))
    #expect(!pass(BrowseFilter(category: 17), old, cats: [17, 18]))
    let installed = InstalledAddon(catalog: fresh, record: InstallRecord(id: 1, version: "1", dirs: ["A1"]), manifest: nil)
    #expect(pass(BrowseFilter(status: .updateAvailable), fresh, installed: installed) && !pass(BrowseFilter(status: .upToDate), fresh, installed: installed))
}

@Test func backupsRoundTripInMinionsFormat() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "mm-backup-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let game = root.appending(path: "Elder Scrolls Online/live")
    try fm.createDirectory(at: game.appending(path: "SavedVariables"), withIntermediateDirectories: true)
    try fm.createDirectory(at: game.appending(path: "AddOns/HarvestMap"), withIntermediateDirectories: true)
    try "harvest = 1".write(to: game.appending(path: "SavedVariables/HarvestMap.lua"), atomically: true, encoding: .utf8)
    try "SET X 1".write(to: game.appending(path: "AddOnSettings.txt"), atomically: true, encoding: .utf8)
    try "SET Y 2".write(to: game.appending(path: "UserSettings.txt.bak-1"), atomically: true, encoding: .utf8)
    try "not backed up".write(to: game.appending(path: "AddOns/HarvestMap/HarvestMap.txt"), atomically: true, encoding: .utf8)
    let backupDir = root.appending(path: "minion")
    let day = MinionBackup.dayFormat.date(from: "2026-10-28")!
    let made = try MinionBackup.create(gameFolder: game, addonIDs: [7, 57], backupDir: backupDir, gameID: "ESO-1", date: day)
    #expect(made.zip?.lastPathComponent == "2026-10-28.zip")
    #expect(try String(contentsOf: made.addonList!, encoding: .utf8) == "7,57,", "Minion's id list: commas, trailing comma")

    // The zip names are absolute paths, as Minion writes them, and unzip can read them.
    let listing = Process()
    listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    listing.arguments = ["-Z1", made.zip!.path]
    let pipe = Pipe(); listing.standardOutput = pipe
    try listing.run(); listing.waitUntilExit()
    let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    #expect(names.count == 3 && names.allSatisfy { $0.hasPrefix("/") && !$0.contains("/AddOns/") })

    // Restore maps the files into another game folder (another Mac, user, or PTS).
    let other = root.appending(path: "Other/pts")
    let files = try MinionBackup.unpack(made.zip!, into: root.appending(path: "work"), gameFolder: other)
    #expect(Set(files.map { String($0.destination.path.dropFirst(other.path.count + 1)) })
            == ["SavedVariables/HarvestMap.lua", "AddOnSettings.txt", "UserSettings.txt.bak-1"])

    let listed = MinionBackup.list(backupDir: backupDir, gameID: "ESO-1")
    #expect(listed.map(\.name) == ["2026-10-28"] && listed.first?.addonIDs == [7, 57])
}

@Test func readsMinionsBackupSettings() throws {
    let xml = #"<minion><client><backup-dir>/Users/me/.minion</backup-dir></client><games><game game-id="ESO" unique-game-id="ESO-1"><addons/></game></games></minion>"#
    let game = try #require(MinionImport.parse(Data(xml.utf8)))
    #expect(game.uniqueID == "ESO-1" && game.backupDir == "/Users/me/.minion")
}
