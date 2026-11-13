import Foundation
import Testing
@testable import MacMinionKit

/// Times each stage the Game Folder's read runs, on a copy of a real SavedVariables folder, by hand:
///   MM_REAL_SV=/tmp/copy/SavedVariables MM_ADDONS=<AddOns> swift test -c release --filter benchmarksTheGameFolderRead
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func benchmarksTheGameFolderRead() async throws {
    let env = ProcessInfo.processInfo.environment
    let folder = URL(fileURLWithPath: env["MM_REAL_SV"]!)
    let addons = URL(fileURLWithPath: env["MM_ADDONS"] ?? folder.deletingLastPathComponent().appending(path: "AddOns").path)
    func rss() -> Int {
        var info = mach_task_basic_info(), count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return Int(info.resident_size) / 1_048_576
    }
    var last = Date()
    func lap(_ name: String) { print(String(format: "BENCH %-28@ %6.2f s  rss %5d MB", name, Date().timeIntervalSince(last), rss())); last = Date() }
    print("BENCH start rss \(rss()) MB")
    // The read as the app runs it (InspectorView.readInspectorData): parse on every core, names, then the rest at once.
    do {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
        let t0 = Date()
        let docs = await withTaskGroup(of: (String, SVDocument?).self) { group in
            for url in urls { group.addTask { (url.lastPathComponent, try? SVDocument.read(url)) } }
            var docs: [String: SVDocument] = [:]
            for await (n, d) in group { docs[n] = d }
            return docs
        }
        let (names, index) = await Task.detached { (SVNameIndex.build(documents: docs, addons: addons), SavedVariablesAudit.index(addons)) }.value
        async let refs = SVReferenceIndex.buildConcurrently(documents: docs, names: names)
        async let problems = SVProblems.checkAll(documents: docs, declarations: index.savers.mapValues(\.variables))
        async let usage = Task.detached { SVUsage.build(documents: docs, names: names) }.value
        _ = await Task.detached { SettingsMatrix.build(documents: docs, names: names) }.value
        let firstPages = Date().timeIntervalSince(t0)
        _ = await (refs, problems, usage)
        print(String(format: "BENCH pipeline: Characters and Addons after %.2f s, everything after %.2f s", firstPages, Date().timeIntervalSince(t0)))
        last = Date()
    }
    var docs: [String: SVDocument] = [:]
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    for url in urls { docs[url.lastPathComponent] = try SVDocument.read(url) }
    lap("parse")
    _ = await withTaskGroup(of: SVDocument?.self) { group in
        for url in urls { group.addTask { try? SVDocument.read(url) } }
        var n = 0
        for await _ in group { n += 1 }
        return n
    }
    lap("parse, every core")
    func count(_ v: LuaValue) -> Int { v.table.map { $0.entries.reduce($0.count) { $0 + count($1.value) } } ?? 0 }
    let entries = docs.values.reduce(0) { $0 + $1.variables.reduce(0) { $0 + 1 + count($1.value) } }
    print("BENCH entries \(entries), \(MemoryLayout<LuaEntry>.stride) B per entry stride, \(MemoryLayout<LuaValue>.stride) B per value")
    let names = SVNameIndex.build(documents: docs, addons: addons); lap("names")
    let decl = SavedVariablesAudit.declarations(addons); lap("declarations")
    _ = docs.flatMap { SVProblems.check(file: $0.key, document: $0.value, declared: decl[String($0.key.dropLast(4)).lowercased()]?.variables) }; lap("problems")
    let refs = SVReferenceIndex.build(documents: docs, names: names); lap("references")
    let parallel = await SVReferenceIndex.buildConcurrently(documents: docs, names: names); lap("references, every core")
    #expect(parallel.files == refs.files && parallel.hits == refs.hits, "the parallel index matches the serial one")
    let serialProblems = docs.sorted { $0.key < $1.key }.flatMap { SVProblems.check(file: $0.key, document: $0.value, declared: decl[String($0.key.dropLast(4)).lowercased()]?.variables) }
    let parallelProblems = await SVProblems.checkAll(documents: docs, declarations: decl.mapValues(\.variables)); lap("problems, every core")
    #expect(Set(parallelProblems.map(\.id)) == Set(serialProblems.map(\.id)))
    _ = await Task.detached { SavedVariablesAudit.index(addons) }.value; lap("one walk of AddOns")
    print("BENCH refs \(refs.targetCount) targets, \(refs.hitCount) hits")
    _ = SVUsage.build(documents: docs, names: names); lap("usage")
    _ = SettingsMatrix.build(documents: docs, names: names); lap("matrix")
    let manifests = SavedVariablesAudit.index(addons).manifests
    var homes: [String: SettingsMatrix.Home] = [:]
    for file in docs.keys.sorted() { SettingsMatrix.mergeHomes(&homes, SettingsMatrix.homes(in: docs[file]!)) }
    lap("manifests and homes (not the graph's cost)")
    let graphParts = docs.mapValues(SVGraph.FilePart.init(document:)); lap("graph parts (pass one, per file)")
    let graph = SVGraph.build(.init(parts: graphParts, addons: manifests, names: names, homes: homes, snapshot: nil)); lap("graph")
    print("BENCH graph \(graph.nodes.count) nodes, \(graph.provenance.count) edges")
    _ = SavedVariablesAudit.topFolders(addons); lap("topFolders")
    let folders = SavedVariablesAudit.saverFolders(addons)
    for file in docs.keys { if let f = folders[String(file.dropLast(4)).lowercased()] { _ = SVSourceNames.read(folder: f) } }
    lap("sourceNames")
    // What the app keeps once the documents are gone: the indexes only.
    let kept = { () -> (SVNameIndex, SVReferenceIndex, SVUsage, SettingsMatrix) in
        (names, refs, SVUsage.build(documents: docs, names: names), SettingsMatrix.build(documents: docs, names: names))
    }()
    let biggest = docs.max(by: { $0.value.byteCount < $1.value.byteCount })?.key
    docs = [:]
    lap("drop documents (kept indexes)")
    _ = kept
    // The scan that runs each time the app becomes active, on the real game folder (read only).
    let game = addons.deletingLastPathComponent()
    _ = GameFolderScan.scan(game); lap("scan game folder")
    _ = SavedVariablesAudit.run(game: game, addons: addons); lap("audit SavedVariables")
    // The Inspector opens the biggest file: parse again, then the roots.
    if let big = env["MM_BENCH_FILE"] ?? biggest {
        let doc = try SVDocument.read(folder.appending(path: big)); lap("inspect parse \(big.prefix(14))")
        let roots = SVNode.roots(doc); lap("inspect roots")
        // The largest table in the file, as the tree shows it when opened.
        var widest: SVNode?
        func find(_ nodes: [SVNode], depth: Int) {
            for n in nodes where n.value.table != nil {
                if (n.value.table?.count ?? 0) > (widest?.value.table?.count ?? 0) { widest = n }
                if depth < 8 { find(n.children ?? [], depth: depth + 1) }
            }
        }
        find(roots, depth: 0); lap("walk to the widest table")
        if let w = widest {
            let rows = w.children ?? []; lap("children of \(rows.count) rows")
            _ = rows.map(\.id); lap("ids of every row (one render)")
            let target = rows.last!.id
            _ = rows.first { $0.id == target }; lap("find the last row by id")
            _ = rows.map(\.level); lap("level of every row")
            _ = SVReadable.sheet(rows.map { LuaEntry(key: $0.key, value: $0.value, span: $0.span) }, at: w.path, title: "x", names: names); lap("settings sheet")
        }
    }
}

/// The two-pass read against every document at once, on a real folder: the same results, and peak memory.
///   MM_REAL_SV=<copy> MM_ADDONS=<AddOns> MM_READ=twoPass|allAtOnce swift test -c release --filter peakMemoryOfTheRead
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_READ"] != nil))
func peakMemoryOfTheRead() async throws {
    let env = ProcessInfo.processInfo.environment
    let folder = URL(fileURLWithPath: env["MM_REAL_SV"]!), addons = URL(fileURLWithPath: env["MM_ADDONS"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    let declarations = SavedVariablesAudit.index(addons).savers.mapValues(\.variables)
    func peak() -> Int { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Int(u.ru_maxrss) / 1_048_576 }
    func inUse() -> Int { var stats = malloc_statistics_t(); malloc_zone_statistics(nil, &stats); return stats.size_in_use / 1_048_576 }
    let before = peak(), start = Date(), used = inUse()
    if env["MM_READ"] == "twoPass" {
        let read = await SVFolderRead.read(urls, addons: addons, declarations: declarations)
        print("BENCH kept after the read: \(inUse() - used) MB in use")
        withExtendedLifetime(read) {}
    } else {
        var docs: [String: SVDocument] = [:]
        for url in urls { docs[url.lastPathComponent] = try? SVDocument.read(url) }
        let names = SVNameIndex.build(documents: docs, addons: addons)
        _ = SVReferenceIndex.build(documents: docs, names: names)
        _ = await SVProblems.checkAll(documents: docs, declarations: declarations)
        _ = SVUsage.build(documents: docs, names: names)
        _ = SettingsMatrix.build(documents: docs, names: names)
    }
    print(String(format: "BENCH %@: %.2f s, peak %d MB (started at %d MB)", env["MM_READ"]!, Date().timeIntervalSince(start), peak(), before))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_COMPARE"] != nil))
func twoPassReadMatchesReadingEverythingAtOnce() async throws {
    let env = ProcessInfo.processInfo.environment
    let folder = URL(fileURLWithPath: env["MM_REAL_SV"]!), addons = URL(fileURLWithPath: env["MM_ADDONS"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    let declarations = SavedVariablesAudit.index(addons).savers.mapValues(\.variables)
    var docs: [String: SVDocument] = [:]
    for url in urls { docs[url.lastPathComponent] = try? SVDocument.read(url) }
    let names = SVNameIndex.build(documents: docs, addons: addons)
    let read = await SVFolderRead.read(urls, addons: addons, declarations: declarations)
    #expect(read.names.characters.mapValues { "\($0.name)|\($0.source)" } == names.characters.mapValues { "\($0.name)|\($0.source)" })
    #expect(read.names.ownAccounts == names.ownAccounts && read.names.guilds == names.guilds && read.names.guildIDs == names.guildIDs
            && read.names.guildStoreLinks == names.guildStoreLinks && read.names.sets == names.sets)
    let refs = SVReferenceIndex.build(documents: docs, names: names)
    #expect(read.references.files == refs.files && read.references.hits == refs.hits)
    let problems = await SVProblems.checkAll(documents: docs, declarations: declarations)
    #expect(read.problems.map(\.id) == problems.map(\.id))
    let usage = SVUsage.build(documents: docs, names: names)
    #expect(read.usage.totalBytes == usage.totalBytes && read.usage.files == usage.files && read.usage.characters == usage.characters
            && read.usage.accounts == usage.accounts && read.usage.servers == usage.servers && read.usage.biggest == usage.biggest)
    let matrix = SettingsMatrix.build(documents: docs, names: names)
    #expect(read.matrix.addons.map(\.file) == matrix.addons.map(\.file) && read.matrix.characterIDs == matrix.characterIDs)
    for (a, b) in zip(read.matrix.addons, matrix.addons) {
        #expect(a.shared == b.shared && a.characters.mapValues { $0.mapValues(\.text) } == b.characters.mapValues { $0.mapValues(\.text) }, "\(a.file)")
    }
    print("COMPARE \(names.characters.count) characters, \(refs.hitCount) hits, \(problems.count) problems, \(matrix.addons.count) addons")
}

/// Memory the parsed trees use, and how long parsing takes, on a real folder:
///   MM_TREES=1 MM_REAL_SV=<copy> swift test -c release --filter memoryOfParsedTrees
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_TREES"] != nil))
func memoryOfParsedTrees() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    func inUse() -> Int { var stats = malloc_statistics_t(); malloc_zone_statistics(nil, &stats); return stats.size_in_use }
    let bytes = urls.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    let used = inUse(), start = Date()
    let docs = urls.map { try? SVDocument.read($0) }
    let seconds = Date().timeIntervalSince(start)
    print(String(format: "TREES %d MB of files -> %d MB of trees, parsed in %.2f s; LuaEntry %d B, LuaValue %d B, LuaKey %d B",
                 bytes / 1_048_576, (inUse() - used) / 1_048_576, seconds,
                 MemoryLayout<LuaEntry>.stride, MemoryLayout<LuaValue>.stride, MemoryLayout<LuaKey>.stride))
    withExtendedLifetime(docs) {}
}

/// A read, then the same read after one file changes, on a copy of a real folder (the test touches a file in it):
///   MM_INCREMENTAL=1 MM_REAL_SV=<copy> MM_ADDONS=<AddOns> swift test -c release --filter incrementalRead
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_INCREMENTAL"] != nil))
func incrementalRead() async throws {
    let env = ProcessInfo.processInfo.environment
    let folder = URL(fileURLWithPath: env["MM_REAL_SV"]!), addons = URL(fileURLWithPath: env["MM_ADDONS"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    let declarations = SavedVariablesAudit.index(addons).savers.mapValues(\.variables)
    func inUse() -> Int { var stats = malloc_statistics_t(); malloc_zone_statistics(nil, &stats); return stats.size_in_use / 1_048_576 }
    let used = inUse()
    var start = Date()
    let (read, cache) = await SVFolderRead.read(urls, addons: addons, declarations: declarations, cache: .init())
    print(String(format: "BENCH full read %.2f s; kept %d MB with the cache", Date().timeIntervalSince(start), inUse() - used))
    let file = urls.first { $0.lastPathComponent.hasPrefix("AutoResearch") } ?? urls[0]
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    start = Date()
    let (_, after) = await SVFolderRead.read(urls, addons: addons, declarations: declarations, cache: cache)
    print(String(format: "BENCH after %@ changed: %.2f s, parsed %d + %d files", file.lastPathComponent, Date().timeIntervalSince(start), after.parsed.first, after.parsed.second))
    start = Date()
    _ = await SVFolderRead.read(urls, addons: addons, declarations: declarations, cache: after)
    print(String(format: "BENCH nothing changed: %.2f s", Date().timeIntervalSince(start)))
    start = Date(); var lib = SVNameIndex(); lib.finish(roster: nil, addons: addons)
    print(String(format: "BENCH   of which libraries' names: %.2f s", Date().timeIntervalSince(start)))
    start = Date(); _ = SVReferenceIndex.merging(files: read.references.files, parts: [read.references.hits])
    print(String(format: "BENCH   of which merging references: %.2f s", Date().timeIntervalSince(start)))
    withExtendedLifetime(read) {}
}

/// Synthetic ActionDurationReminder-scale sheet: 2 accounts, 40 sections, 125 rows each.
/// Always on so CI times Settings sheet + grouped without a SavedVariables copy.
@Test func benchmarksReadableSheetOfTwoAccounts() {
    var lua = "ADR =\n{\n  [\"Default\"] =\n  {\n"
    for (account, chars) in [
        ("@SOLAEGIS", (1...19).map { "CharA\($0)" }),
        ("@vavasour", (1...19).map { "CharB\($0)" }),
    ] as [(String, [String])] {
        lua += "    [\"\(account)\"] =\n    {\n"
        for name in ["$AccountWide"] + chars {
            lua += "      [\"\(name)\"] =\n      {\n"
            for i in 1...125 { lua += "        [\"setting\(i)\"] = \(i),\n" }
            lua += "      },\n"
        }
        lua += "    },\n"
    }
    lua += "  },\n}\n"
    let doc = SVDocument.parse(Data(lua.utf8))
    let t0 = Date()
    let sections = SVReadable.sheet(doc.variables, at: [], title: "ADR", names: nil)
    let sheetMs = Date().timeIntervalSince(t0) * 1000
    let t1 = Date()
    let groups = SVReadable.grouped(sections)
    let groupMs = Date().timeIntervalSince(t1) * 1000
    print(String(format: "BENCH readable sheet %.1f ms, grouped %.1f ms, %d sections, %d groups",
                 sheetMs, groupMs, sections.count, groups.count))
    #expect(sections.count == 40)
    #expect(groups.count == 2)
    #expect(groups.map(\.title) == ["Default · @SOLAEGIS", "Default · @vavasour"])
    #expect(groups.map(\.sections.count) == [20, 20])
    #expect(groups[0].sections.first?.title == SVLevel.everyCharacter)
    #expect(groups[0].sections.first?.rows.count == 125)
}

/// Times a cold open of the widest table (sort + SVNode children), without warming lazy children during the walk.
///   MM_WIDEST=1 MM_REAL_SV=/tmp/mm-sv-copy swift test -c release --filter benchmarksWidestTableOpen
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_WIDEST"] != nil))
func benchmarksWidestTableOpen() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        .filter { $0.pathExtension == "lua" }
    let biggest = urls.max(by: {
        ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    })!
    let file = ProcessInfo.processInfo.environment["MM_BENCH_FILE"].map { folder.appending(path: $0) } ?? biggest
    let doc = try SVDocument.read(file)
    // Find the widest table by entry counts only — do not touch SVNode.children.
    var widestPath: [LuaKey] = []
    var widestCount = 0
    func walk(_ entries: [LuaEntry], path: [LuaKey], depth: Int) {
        for e in entries {
            guard let t = e.value.table else { continue }
            let next = path + [e.key]
            if t.count > widestCount { widestCount = t.count; widestPath = next }
            if depth < 8 { walk(t.entries, path: next, depth: depth + 1) }
        }
    }
    walk(doc.variables, path: [], depth: 0)
    print("WIDEST \(file.lastPathComponent) path=\(widestPath.luaPath) rows=\(widestCount)")
    let roots = SVNode.roots(doc)
    var cursor = SVTableCursor(roots: roots)
    // Open the parent of the widest table without building the widest children yet.
    guard let last = widestPath.last else { return }
    let parentPath = Array(widestPath.dropLast())
    cursor.focus = parentPath
    // Cold: time building children for the widest row (first .children access).
    let parentRows = cursor.rows
    guard let node = parentRows.first(where: { $0.key == last }) ?? (parentPath.isEmpty ? roots.first(where: { $0.key == last }) : nil) else {
        Issue.record("widest node missing"); return
    }
    let t0 = Date()
    let kids = node.children ?? []
    let ms = Date().timeIntervalSince(t0) * 1000
    print(String(format: "WIDEST children %d rows in %.1f ms", kids.count, ms))
    #expect(kids.count == widestCount)
    // Also time assigning focus to that table via cursor.refresh (uses cached children after first touch).
    let t1 = Date()
    cursor.focus = widestPath
    let refreshMs = Date().timeIntervalSince(t1) * 1000
    print(String(format: "WIDEST refresh after warm %.1f ms, rows %d", refreshMs, cursor.rows.count))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_ADR_ORDER"] != nil))
func actionDurationReminderSectionOrder() throws {
    let path = ProcessInfo.processInfo.environment["MM_ADR_ORDER"]!
    let doc = try SVDocument.read(URL(fileURLWithPath: path))
    let sections = SVReadable.sheet(doc.variables, at: [], title: "ActionDurationReminder", names: nil, source: nil)
    let groups = SVReadable.grouped(sections)
    print("ADR groups: \(groups.map { "\($0.title ?? "nil") [\($0.sections.map(\.title).joined(separator: ", "))]" })")
    #expect(groups.count == 2)
    #expect(groups[0].sections.first?.title == SVLevel.everyCharacter)
    #expect(groups[1].sections.first?.title == SVLevel.everyCharacter)
    // First-seen account order in this file.
    #expect(groups.map(\.title) == ["Default · @vavasour", "Default · @SOLAEGIS"]
            || groups.map(\.title) == ["Default · @SOLAEGIS", "Default · @vavasour"])
}
