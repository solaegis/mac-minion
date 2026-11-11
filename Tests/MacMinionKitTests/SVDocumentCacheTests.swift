import Foundation
import Testing
@testable import MacMinionKit

private func writeSV(_ folder: URL, name: String, body: String) throws -> URL {
    let url = folder.appending(path: name)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func documentCacheMissThenHit() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svdoc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try writeSV(folder, name: "A.lua", body: "A_SV = { [\"x\"] = 1 }\n")
    let cache = SVDocumentCache(capacity: 4)
    let stamp = SVDocumentCache.Stamp(url: url)

    #expect(cache.get("A.lua", stamp: stamp) == nil)
    let first = cache.document(named: "A.lua", at: url, stamp: stamp)
    #expect(first?.variables.count == 1)
    let second = cache.get("A.lua", stamp: stamp)
    #expect(second?.byteCount == first?.byteCount)
    #expect(cache.count == 1)
}

@Test func documentCacheRereadsWhenStampChanges() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svdoc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try writeSV(folder, name: "A.lua", body: "A_SV = { [\"x\"] = 1 }\n")
    let cache = SVDocumentCache(capacity: 4)
    let old = cache.document(named: "A.lua", at: url)!
    #expect(old.variables.first?.value.table?.count == 1)

    try "A_SV = { [\"x\"] = 1, [\"y\"] = 2 }\n".write(to: url, atomically: true, encoding: .utf8)
    let fresh = cache.document(named: "A.lua", at: url)!
    #expect(fresh.variables.first?.value.table?.count == 2)
    #expect(cache.count == 1)
}

@Test func documentCacheEvictsOldestUnpinned() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svdoc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = SVDocumentCache(capacity: 2)
    for name in ["A.lua", "B.lua", "C.lua"] {
        let url = try writeSV(folder, name: name, body: "\(name.dropLast(4))_SV = { [\"n\"] = \"\(name)\" }\n")
        _ = cache.document(named: name, at: url)
    }
    #expect(cache.count == 2)
    #expect(cache.get("A.lua") == nil)
    #expect(cache.get("B.lua") != nil)
    #expect(cache.get("C.lua") != nil)
}

@Test func documentCachePinnedSurvivesEviction() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svdoc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = SVDocumentCache(capacity: 2)
    let a = try writeSV(folder, name: "A.lua", body: "A_SV = { [\"n\"] = \"A\" }\n")
    let b = try writeSV(folder, name: "B.lua", body: "B_SV = { [\"n\"] = \"B\" }\n")
    let c = try writeSV(folder, name: "C.lua", body: "C_SV = { [\"n\"] = \"C\" }\n")
    _ = cache.document(named: "A.lua", at: a)
    cache.pin("A.lua")
    _ = cache.document(named: "B.lua", at: b)
    _ = cache.document(named: "C.lua", at: c)
    #expect(cache.get("A.lua") != nil, "pinned A stays")
    #expect(cache.get("B.lua") == nil, "oldest unpinned B goes")
    #expect(cache.get("C.lua") != nil)
    #expect(cache.count == 2)
}

@Test func documentCacheRetainDropsStaleAndMissing() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "svdoc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try writeSV(folder, name: "A.lua", body: "A_SV = { [\"n\"] = \"A\" }\n")
    let b = try writeSV(folder, name: "B.lua", body: "B_SV = { [\"n\"] = \"B\" }\n")
    let cache = SVDocumentCache(capacity: 4)
    let stampA = SVDocumentCache.Stamp(url: a)
    let stampB = SVDocumentCache.Stamp(url: b)
    _ = cache.document(named: "A.lua", at: a, stamp: stampA)
    _ = cache.document(named: "B.lua", at: b, stamp: stampB)
    try "B_SV = { [\"n\"] = \"B2\" }\n".write(to: b, atomically: true, encoding: .utf8)
    let newB = SVDocumentCache.Stamp(url: b)
    cache.retain(matching: ["A.lua": stampA, "B.lua": newB])
    #expect(cache.get("A.lua", stamp: stampA) != nil)
    #expect(cache.get("B.lua") == nil)
    cache.retain(matching: ["A.lua": stampA])
    #expect(cache.count == 1)
}

/// Twice Find-style recovery on a large real file: cold parse vs cache hit.
///   MM_REAL_SV=<SavedVariables> swift test -c release --filter benchmarksTheDocumentCache
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func benchmarksTheDocumentCache() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        .filter { $0.pathExtension == "lua" }
    let biggest = try urls.max { a, b in
        (try a.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            < (try b.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }!
    func ms(_ t: CFAbsoluteTime) -> Int { Int((CFAbsoluteTimeGetCurrent() - t) * 1000) }

    var t = CFAbsoluteTimeGetCurrent()
    let cold1 = try SVDocument.read(biggest)
    let cold1ms = ms(t)
    t = CFAbsoluteTimeGetCurrent()
    let cold2 = try SVDocument.read(biggest)
    let cold2ms = ms(t)
    print("BENCH doc-cache cold parse \(biggest.lastPathComponent): \(cold1ms) ms then \(cold2ms) ms (no cache)")

    let cache = SVDocumentCache(capacity: 4)
    t = CFAbsoluteTimeGetCurrent()
    let warmed = cache.document(named: biggest.lastPathComponent, at: biggest)!
    let warmFill = ms(t)
    t = CFAbsoluteTimeGetCurrent()
    let hit = cache.document(named: biggest.lastPathComponent, at: biggest)!
    let hitMs = ms(t)
    print("BENCH doc-cache fill \(warmFill) ms, hit \(hitMs) ms, bytes \(hit.byteCount)")
    #expect(cold1.byteCount == cold2.byteCount && warmed.byteCount == hit.byteCount)
    #expect(hitMs < cold2ms || hitMs <= 5, "cache hit should skip the second parse")
}
