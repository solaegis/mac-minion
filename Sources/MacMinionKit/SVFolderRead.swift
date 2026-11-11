import Foundation

/// Everything the Game Folder shows from SavedVariables, read in two passes so only a few files' trees are
/// in memory at once, however big the folder (docs/GAME-FOLDER-PERFORMANCE.md, Phase 3).
///
/// Pass one reads each file for what needs no names: problems, space, where characters live, and the names
/// the file gives. Pass two reads each file again for what needs every name: where each ID appears, and
/// settings per character. Parsing is the cheapest stage, so reading twice costs far less than keeping
/// every tree. Each pass runs on every core; results merge in file order, so they match `build` on all
/// documents at once.
public struct SVFolderRead: Sendable {
    public let names: SVNameIndex
    public let references: SVReferenceIndex
    public let problems: [SVProblem]
    public let usage: SVUsage
    public let matrix: SettingsMatrix
    public let roster: [String: CompanionCharacter]
    public let snapshot: CompanionSnapshot?
    /// Accounts, characters, addons, and the scopes where they meet; empty when no manifests were passed.
    public let graph: SVGraph

    /// Files read at once in each pass: enough to use every core, few enough that only that many trees exist.
    public static var concurrency: Int { max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)) }

    /// Each file's results from the last read, so the next read parses only files that changed.
    public struct Cache: Sendable {
        struct Stamp: Equatable, Sendable { let size: Int; let modified: Date? }
        struct First: Sendable {
            let names: SVNameIndex
            let problems: [SVProblem]
            let tally: SVUsage.Tally
            let homes: [String: SettingsMatrix.Home]
            let roster: [String: CompanionCharacter]?
            let snapshot: CompanionSnapshot?
            let graphPart: SVGraph.FilePart
        }
        struct Second: Sendable {
            let hits: [SVTarget: [SVHit]]
            let addon: SettingsMatrix.Addon?
        }
        var stamps: [String: Stamp] = [:]
        var first: [String: First] = [:]
        var second: [String: Second] = [:]
        var declarations: [String: [String]] = [:]
        var namesFingerprint: Int?
        /// Files parsed in the last read's first and second pass, for tests and the benchmark.
        public internal(set) var parsed: (first: Int, second: Int) = (0, 0)

        public init() {}
    }

    /// `declarations`: each addon's declared variables by lowercased folder name, for the problem checks.
    /// `manifests`: every installed addon's name, variables, and dependencies, for the graph (`AddonIndex.manifests`).
    public static func read(_ files: [URL], addons: URL?, declarations: [String: [String]],
                            manifests: [String: (addon: String, variables: [String], dependsOn: [String])] = [:],
                            report: @escaping @Sendable (String, Double) async -> Void = { _, _ in }) async -> SVFolderRead {
        await read(files, addons: addons, declarations: declarations, manifests: manifests, cache: Cache(), report: report).read
    }

    /// The same read, reusing what `cache` has for files whose size and date are unchanged; returns the new cache.
    public static func read(_ files: [URL], addons: URL?, declarations: [String: [String]],
                            manifests: [String: (addon: String, variables: [String], dependsOn: [String])] = [:], cache old: Cache,
                            report: @escaping @Sendable (String, Double) async -> Void = { _, _ in }) async -> (read: SVFolderRead, cache: Cache) {
        var cache = Cache()
        cache.declarations = declarations
        for var url in files {
            // A URL keeps the values it read before: ask the file again.
            url.removeAllCachedResourceValues()
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            cache.stamps[url.lastPathComponent] = Cache.Stamp(size: values?.fileSize ?? -1, modified: values?.contentModificationDate)
        }
        func unchanged(_ file: String) -> Bool { old.stamps[file] != nil && old.stamps[file] == cache.stamps[file] }
        let sameDeclarations = old.declarations == declarations

        // Pass one: files that changed (or all, when what addons declare changed).
        for url in files where sameDeclarations && unchanged(url.lastPathComponent) {
            cache.first[url.lastPathComponent] = old.first[url.lastPathComponent]
        }
        let toRead = files.filter { cache.first[$0.lastPathComponent] == nil }
        let count = toRead.count
        await report(String(localized: "Reading \(String(localized: "\(count) SavedVariables files", bundle: .module))…", bundle: .module), 0)
        let fresh = await forEach(toRead, report: { done in await report(String(localized: "Reading file \(done) of \(count)…", bundle: .module), 0.5 * Double(done) / Double(max(1, count))) }) { url -> (String, Cache.First)? in
            guard let doc = try? SVDocument.read(url) else { return nil }
            let file = url.lastPathComponent
            return (file, Cache.First(names: SVNameIndex.collect(file: file, document: doc),
                                      problems: SVProblems.check(file: file, document: doc, declared: declarations[String(file.dropLast(4)).lowercased()]),
                                      tally: SVUsage.Tally(file: file, document: doc), homes: SettingsMatrix.homes(in: doc),
                                      roster: CompanionData.isCompanionFile(file) ? CompanionData.roster(doc) : nil,
                                      snapshot: CompanionData.isCompanionFile(file) ? CompanionData.snapshot(doc, file: file) : nil,
                                      graphPart: SVGraph.FilePart(document: doc)))
        }
        for (file, part) in fresh { cache.first[file] = part }

        await report(String(localized: "Matching names to IDs…", bundle: .module), 0.5)
        let readFiles = cache.first.keys.sorted()
        var names = SVNameIndex(), homes: [String: SettingsMatrix.Home] = [:], tally = SVUsage.Tally()
        for file in readFiles {
            let part = cache.first[file]!
            names.merge(part.names)
            SettingsMatrix.mergeHomes(&homes, part.homes)
            tally.merge(part.tally)
        }
        let snapshot = readFiles.compactMap { cache.first[$0]?.snapshot }.max {
            ($0.written ?? .distantPast) < ($1.written ?? .distantPast)
        }
        let roster = snapshot?.characters ?? readFiles.lazy.compactMap { cache.first[$0]?.roster }.first
        names.finish(roster: roster, addons: addons, guilds: snapshot.map { Dictionary($0.guilds.map { ($0.key, $0.value.name) }, uniquingKeysWith: { _, n in n }) } ?? [:])
        var problems = readFiles.flatMap { cache.first[$0]!.problems }
        if let snapshot { problems += CompanionData.problems(from: snapshot) }
        let usage = SVUsage.finish(tally, names: names)
        problems += SVProblems.unknownCharacters(usage)
        problems = SVProblems.inDisplayOrder(problems)
        let graph = SVGraph.build(.init(parts: Dictionary(uniqueKeysWithValues: readFiles.map { ($0, cache.first[$0]!.graphPart) }),
                                        addons: manifests, names: names, homes: homes, snapshot: snapshot))

        // Pass two: references and settings need every name, so they're kept only while the names stay the same.
        cache.namesFingerprint = names.fingerprint
        if old.namesFingerprint == cache.namesFingerprint {
            for file in readFiles where unchanged(file) && fresh.allSatisfy({ $0.0 != file }) { cache.second[file] = old.second[file] }
        }
        let folder = files.first?.deletingLastPathComponent()
        let byName = SettingsMatrix.charactersByName(names)
        let finalNames = names, finalHomes = homes
        let toIndex = readFiles.filter { cache.second[$0] == nil }
        await report(String(localized: "Finding where each ID is used…", bundle: .module), 0.6)
        let indexed = await forEach(toIndex.compactMap { folder?.appending(path: $0) },
                                    report: { done in await report(String(localized: "Finding where each ID is used: file \(done) of \(toIndex.count)…", bundle: .module), 0.6 + 0.4 * Double(done) / Double(max(1, toIndex.count))) }) { url -> (String, Cache.Second)? in
            let file = url.lastPathComponent
            guard let doc = try? SVDocument.read(url) else { return nil }
            return (file, Cache.Second(hits: SVReferenceIndex.hits(in: doc, file: 0, names: finalNames),
                                       addon: SettingsMatrix.addon(file: file, document: doc, names: finalNames, homes: finalHomes, byName: byName)))
        }
        for (file, part) in indexed { cache.second[file] = part }
        cache.parsed = (fresh.count, indexed.count)

        let indexedFiles = readFiles.filter { cache.second[$0] != nil }
        let references = SVReferenceIndex.merging(files: indexedFiles, parts: indexedFiles.map { cache.second[$0]!.hits })
        let matrix = SettingsMatrix.assemble(addons: indexedFiles.compactMap { cache.second[$0]!.addon }, names: names, homes: homes)
        return (SVFolderRead(names: names, references: references, problems: problems, usage: usage, matrix: matrix,
                             roster: roster ?? [:], snapshot: snapshot, graph: graph), cache)
    }

    /// Runs `work` on each URL, at most `concurrency` at a time, and returns what it made (in no order).
    static func forEach<T: Sendable>(_ urls: [URL], report: @escaping @Sendable (Int) async -> Void,
                                     _ work: @escaping @Sendable (URL) -> T?) async -> [T] {
        await withTaskGroup(of: T?.self) { group in
            var next = 0, done = 0, results: [T] = []
            func start() {
                guard next < urls.count else { return }
                let url = urls[next]
                next += 1
                group.addTask { work(url) }
            }
            for _ in 0..<concurrency { start() }
            for await result in group {
                if let result { results.append(result) }
                done += 1
                if done % 8 == 0 { await report(done) }
                start()
            }
            return results
        }
    }
}
