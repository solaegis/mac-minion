import Foundation

/// What takes space in SavedVariables: totals by character, account, server, and file, and the
/// biggest tables across all files. Read-only; sizes are the bytes each entry takes in its file.
public struct SVUsage: Sendable {
    public struct Bucket: Sendable, Identifiable, Equatable {
        public enum Kind: String, Sendable { case file, character, account, server, table }

        public let kind: Kind
        /// The character ID, account, server, file name, or (for a table) file + path.
        public let id: String
        public let title: String
        /// "yours", "Unknown character", or the file and path of a table.
        public let detail: String?
        public let bytes: Int
        /// How many files hold it.
        public let files: Int
        /// For a table: its file and key path, to open it.
        public let file: String?
        public let path: [LuaKey]
        /// A character no file names, or an account that isn't yours.
        public let flagged: Bool
        /// For a character or account: bytes in each file that holds it, largest first.
        public var byFile: [(file: String, bytes: Int)] = []
        /// For a character: the servers its data sits under ("Default" only when nothing else).
        public var servers: [String] = []

        public static func == (a: Bucket, b: Bucket) -> Bool {
            a.kind == b.kind && a.id == b.id && a.bytes == b.bytes && a.files == b.files && a.detail == b.detail && a.flagged == b.flagged
        }
    }

    public let totalBytes: Int
    public let files: [Bucket]
    public let characters: [Bucket]
    /// Your accounts first, then accounts other people's data is filed under.
    public let accounts: [Bucket]
    public let servers: [Bucket]
    public let biggest: [Bucket]

    /// How many tables `biggest` keeps.
    public static let biggestCount = 40

    public static func build(documents: [String: SVDocument], names: SVNameIndex) -> SVUsage {
        var tally = Tally()
        for (file, doc) in documents { tally.merge(Tally(file: file, document: doc)) }
        return finish(tally, names: names)
    }

    /// What one file or several add up to, before names: merged in any order.
    public struct Tally: Sendable {
        var characters: [String: (bytes: Int, files: Set<String>)] = [:]
        var accounts: [String: (bytes: Int, files: Set<String>)] = [:]
        var perFile: [String: [String: Int]] = [:]          // character or account -> file -> bytes
        var characterServers: [String: Set<String>] = [:]
        var servers: [String: (bytes: Int, files: Set<String>)] = [:]
        var tables: [Bucket] = []
        var fileBuckets: [Bucket] = []
        var totalBytes = 0

        public init() {}

        public init(file: String, document doc: SVDocument) {
            func add(_ map: inout [String: (bytes: Int, files: Set<String>)], _ key: String, _ bytes: Int, _ file: String) {
                map[key, default: (0, [])].bytes += bytes
                map[key]!.files.insert(file)
            }
            /// Walks a table; returns nothing, but records totals and the tables that hold their own weight.
            func walk(_ entry: LuaEntry, parentPath: [LuaKey], file: String) {
                let bytes = entry.span.count
                let level = SVLevel.of(entry.key, at: parentPath)
                if case .string(let k) = entry.key {
                    if level == .profile { add(&servers, k, bytes, file) }
                    if CharacterID.isID(k) || level == .character {
                        add(&characters, k, bytes, file)
                        perFile[k, default: [:]][file, default: 0] += bytes
                        if parentPath.count >= 2, SVLevel.of(parentPath[1], at: [parentPath[0]]) == .profile {
                            characterServers[k, default: []].insert(parentPath[1].description)
                        }
                    }
                    // Accounts with data under them: your own at the ZO_SavedVars level, others anywhere.
                    if k.hasPrefix("@"), entry.value.table != nil {
                        add(&accounts, k, bytes, file)
                        perFile[k, default: [:]][file, default: 0] += bytes
                    }
                }
                guard let table = entry.value.table else { return }
                let path = parentPath + [entry.key]
                // A table counts when no single child table holds almost all of it; otherwise that child is the one to look at.
                let biggestChild = table.entries.lazy.filter { $0.value.table != nil }.map(\.span.count).max() ?? 0
                if bytes >= 1_024, Double(biggestChild) < Double(bytes) * 0.75 {
                    tables.append(Bucket(kind: .table, id: file + "|" + path.map(\.description).joined(separator: "\u{1F}"),
                                         title: path.last?.description ?? file, detail: ([file] + path.map(\.description)).joined(separator: " › "),
                                         bytes: bytes, files: 1, file: file, path: path, flagged: false))
                }
                for child in table.entries { walk(child, parentPath: path, file: file) }
            }
            for variable in doc.variables { walk(variable, parentPath: [], file: file) }
            // Only the biggest tables are shown: a file's own top ones are all that can make the list.
            tables = Array(tables.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }.prefix(SVUsage.biggestCount))
            fileBuckets = [Bucket(kind: .file, id: file, title: file, detail: nil, bytes: doc.byteCount, files: 1,
                                  file: file, path: [], flagged: false)]
            totalBytes = doc.byteCount
        }

        public mutating func merge(_ other: Tally) {
            func join(_ a: inout [String: (bytes: Int, files: Set<String>)], _ b: [String: (bytes: Int, files: Set<String>)]) {
                for (k, v) in b { a[k, default: (0, [])].bytes += v.bytes; a[k]!.files.formUnion(v.files) }
            }
            join(&characters, other.characters)
            join(&accounts, other.accounts)
            join(&servers, other.servers)
            for (k, files) in other.perFile { perFile[k, default: [:]].merge(files, uniquingKeysWith: +) }
            for (k, s) in other.characterServers { characterServers[k, default: []].formUnion(s) }
            tables = Array((tables + other.tables).sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }.prefix(SVUsage.biggestCount))
            fileBuckets += other.fileBuckets
            totalBytes += other.totalBytes
        }
    }

    public static func finish(_ tally: Tally, names: SVNameIndex) -> SVUsage {
        let characters = tally.characters, accounts = tally.accounts, perFile = tally.perFile
        let characterServers = tally.characterServers, servers = tally.servers, tables = tally.tables, fileBuckets = tally.fileBuckets

        func sorted(_ map: [String: (bytes: Int, files: Set<String>)], _ make: (String, Int, Int) -> Bucket) -> [Bucket] {
            map.map { make($0.key, $0.value.bytes, $0.value.files.count) }.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }
        }
        func breakdown(_ id: String) -> [(file: String, bytes: Int)] {
            (perFile[id] ?? [:]).map { ($0.key, $0.value) }.sorted { ($0.bytes, $1.file) > ($1.bytes, $0.file) }
        }
        let characterBuckets = sorted(characters) { id, bytes, files in
            let name = names.characters[id]?.name
            var bucket = Bucket(kind: .character, id: id, title: name ?? (id.contains("^") ? String(id.split(separator: "^")[0]) : id),
                                detail: name == nil && CharacterID.isID(id) ? SVName.unknownCharacter : (name == nil ? nil : id),
                                bytes: bytes, files: files, file: nil, path: [], flagged: name == nil && CharacterID.isID(id))
            bucket.byFile = breakdown(id)
            let servers = characterServers[id] ?? []
            bucket.servers = (servers.count > 1 ? servers.subtracting(["Default"]) : servers).sorted()
            return bucket
        }
        let accountBuckets = sorted(accounts) { id, bytes, files in
            let yours = names.ownAccounts.contains(id)
            var bucket = Bucket(kind: .account, id: id, title: id, detail: yours ? String(localized: "yours", bundle: .module) : String(localized: "someone else's", bundle: .module),
                                bytes: bytes, files: files, file: nil, path: [], flagged: !yours)
            bucket.byFile = breakdown(id)
            return bucket
        }.sorted { a, b in a.flagged != b.flagged ? !a.flagged : a.bytes > b.bytes }
        let serverBuckets = sorted(servers) { id, bytes, files in
            Bucket(kind: .server, id: id, title: id, detail: id == "Default" ? String(localized: "no profile: shared across megaservers", bundle: .module) : nil,
                   bytes: bytes, files: files, file: nil, path: [], flagged: false)
        }
        return SVUsage(totalBytes: tally.totalBytes,
                       files: fileBuckets.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) },
                       characters: characterBuckets, accounts: accountBuckets, servers: serverBuckets,
                       biggest: Array(tables.sorted { ($0.bytes, $1.id) > ($1.bytes, $0.id) }.prefix(biggestCount)))
    }
}
