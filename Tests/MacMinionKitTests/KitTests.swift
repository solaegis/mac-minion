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

@Test func claudeRequestShape() throws {
    let client = AIClient(config: AIConfig(provider: .claude, claudeModel: .opus, claudeKey: "sk-test"))
    let r = try client.makeRequest(system: "S", prompt: "P")
    #expect(r.url == AIClient.anthropicURL)
    #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
    let body = try #require(JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
    #expect(body["model"] as? String == "claude-opus-5-5")
    #expect(body["system"] as? String == "S")
    #expect(body["fallbacks"] as? String == "default")
    #expect(body["temperature"] == nil)

    let haiku = AIClient(config: AIConfig(provider: .claude, claudeModel: .haiku, claudeKey: "k"))
    let hr = try haiku.makeRequest(system: "S", prompt: "P")
    let hb = try #require(JSONSerialization.jsonObject(with: hr.httpBody ?? Data()) as? [String: Any])
    #expect(hb["fallbacks"] == nil && hr.value(forHTTPHeaderField: "anthropic-beta") == nil, "Haiku 5.5 has no server-side fallback")
}

@Test func ollamaRequestShape() throws {
    let client = AIClient(config: AIConfig(provider: .ollama, ollamaModel: "llama3.2"))
    let r = try client.makeRequest(system: "S", prompt: "P")
    #expect(r.url?.absoluteString == "http://localhost:11434/api/chat")
    let body = try #require(JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
    #expect(body["model"] as? String == "llama3.2" && body["stream"] as? Bool == false)
    #expect((body["options"] as? [String: Any])?["num_ctx"] as? Int == 16_384)
    #expect(r.timeoutInterval == AIClient.idleTimeout)
}

@Test func parsesAnswers() throws {
    let claude = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"• Fixed a crash"}],"stop_reason":"end_turn","stop_details":null}"#
    #expect(try AIClient.parseClaude(Data(claude.utf8)) == "• Fixed a crash")
    let refusal = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":null,"explanation":"no"}}"#
    #expect(throws: AIError.refused("no")) { try AIClient.parseClaude(Data(refusal.utf8)) }
    let ollama = #"{"model":"x","message":{"role":"assistant","content":"hi"},"done":true}"#
    #expect(try AIClient.parseOllama(Data(ollama.utf8)) == "hi")
    #expect(AIClient.errorMessage(Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)) == "invalid x-api-key")
}

@Test func unconfiguredProvidersExplainWhy() {
    #expect(AIConfig(provider: .claude).problem == "Add a Claude API key in Settings.")
    #expect(AIConfig(provider: .ollama).problem == "Choose an Ollama model in Settings.")
    #expect(AIConfig(provider: .ollama, ollamaModel: "m").problem == nil)
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

@Test func parsesStreams() throws {
    #expect(try AIClient.ollamaChunk(#"{"message":{"role":"assistant","content":"• Fix"},"done":false}"#) == "• Fix")
    #expect(try AIClient.ollamaChunk(#"{"done":true}"#) == nil)
    #expect(throws: AIError.http(0, "model not found")) { try AIClient.ollamaChunk(#"{"error":"model not found"}"#) }
    #expect(try AIClient.claudeEvent(#"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi"}}"#) == "Hi")
    #expect(try AIClient.claudeEvent("event: ping") == nil)
    #expect(try AIClient.claudeEvent(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"x"}}"#) == nil)
    #expect(throws: AIError.refused("no")) {
        try AIClient.claudeEvent(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"stop_details":{"explanation":"no"}}"#)
    }
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
    let pick = try #require(ModelAdvisor.recommend(models.filter { !$0.isEmbedding }, memoryBytes: 192 << 30))
    #expect(pick.model == "gemma4:latest")
    #expect(ModelAdvisor.rank(models, memoryBytes: 16 << 30).map(\.name) == ["gemma4:latest", "phi4:latest"],
            "coding and embedding models never; llama 70B doesn't fit in 16 GB")
    #expect(ModelAdvisor.rank(models, memoryBytes: 8 << 30).isEmpty, "nothing here fits in 8 GB with room to spare")
}
