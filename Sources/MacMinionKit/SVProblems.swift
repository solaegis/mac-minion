import Foundation

/// Something in a SavedVariables file that can make an addon misbehave or the game load slowly.
public struct SVProblem: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case unreadable, endsEarly, empty, missingVariable, unknownVariable, typeMismatch, longList, largeFile,
             unusedFile, copyFile, staleFile, strayItem, didntLoad, luaError, outOfDateAddon, slowLoad, unknownSchema,
             unknownCharacter

        public var title: String {
            switch self {
            case .unreadable: String(localized: "Can't be read", bundle: .module)
            case .endsEarly: String(localized: "Ends early", bundle: .module)
            case .empty: String(localized: "Empty", bundle: .module)
            case .missingVariable: String(localized: "Variable not saved", bundle: .module)
            case .unknownVariable: String(localized: "Variable not declared", bundle: .module)
            case .typeMismatch: String(localized: "Mixed types", bundle: .module)
            case .longList: String(localized: "Long list", bundle: .module)
            case .largeFile: String(localized: "Large file", bundle: .module)
            case .unusedFile: String(localized: "No addon uses it", bundle: .module)
            case .copyFile: String(localized: "Copy", bundle: .module)
            case .staleFile: String(localized: "Not written lately", bundle: .module)
            case .strayItem: String(localized: "Not the game's", bundle: .module)
            case .didntLoad: String(localized: "Didn't load", bundle: .module)
            case .luaError: String(localized: "Lua errors", bundle: .module)
            case .outOfDateAddon: String(localized: "Out of date", bundle: .module)
            case .slowLoad: String(localized: "Slow to load", bundle: .module)
            case .unknownSchema: String(localized: "Newer companion data", bundle: .module)
            case .unknownCharacter: String(localized: "Unknown character", bundle: .module)
            }
        }

        /// Whole files or folders not in use, which Clean Up can move to the Trash.
        public var isFileNotInUse: Bool { [.unusedFile, .copyFile, .staleFile, .strayItem].contains(self) }
    }

    public enum Severity: Int, Sendable, Comparable {
        case note, warning, error
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public let file: String
    /// Where in the file, variable first; empty for the whole file.
    public let path: [LuaKey]
    public let kind: Kind
    public let severity: Severity
    /// One or two sentences: what is wrong and what it means.
    public let message: String
    /// For a file not in use: the file or folder to move to the Trash, and its size.
    public var url: URL?
    public var bytes: Int64 = 0
    /// For a companion problem (Didn't load, Out of date, Slow to load, Lua errors): the addon folder it's about,
    /// as the game names it. Nil when the game didn't say which addon. Not part of `id`.
    public var addon: String?
    /// For an unknown character: the character ID no file names. Not part of `id`.
    public var character: String?

    public var id: String { "\(file)|\(kind.rawValue)|\(path.map(\.description).joined(separator: "\u{1F}"))" }
}

public enum SVProblems {
    /// Data kept for a character ID that no file names, likely a deleted character: one problem per file
    /// that holds it, with how much it takes there.
    public static func unknownCharacters(_ usage: SVUsage) -> [SVProblem] {
        usage.characters.filter(\.flagged).flatMap { character in
            character.byFile.map { place in
                let size = Int64(place.bytes).formatted(.byteCount(style: .file))
                var problem = SVProblem(file: place.file, path: [.string(character.id)], kind: .unknownCharacter, severity: .warning,
                                        message: String(localized: "Keeps \(size) for character \(character.id), which no file names.", bundle: .module))
                problem.character = character.id
                problem.bytes = Int64(place.bytes)
                return problem
            }
        }
    }

    /// Checks every file, each on its own core: by file name, then errors first within a file.
    public static func checkAll(documents: [String: SVDocument], declarations: [String: [String]]) async -> [SVProblem] {
        let problems = await withTaskGroup(of: [SVProblem].self) { group in
            for (file, doc) in documents {
                group.addTask { check(file: file, document: doc, declared: declarations[String(file.dropLast(4)).lowercased()]) }
            }
            var all: [SVProblem] = []
            for await found in group { all += found }
            return all
        }
        return inDisplayOrder(problems)
    }

    /// By file name, then errors first within a file, keeping each file's own order: the same whatever order
    /// files were checked in, as long as each file's problems are together.
    public static func inDisplayOrder(_ problems: [SVProblem]) -> [SVProblem] {
        problems.enumerated().sorted { a, b in
            if a.element.file != b.element.file { return a.element.file.localizedStandardCompare(b.element.file) == .orderedAscending }
            if a.element.severity != b.element.severity { return a.element.severity > b.element.severity }
            return a.offset < b.offset // each file's problems arrive together, in the check's own order
        }.map(\.element)
    }

    /// Lists with at least this many entries are reported: logs and histories that keep growing.
    public static let longList = 5_000
    /// Files at least this big are reported: the game reads every one at each login and reload.
    public static let largeFile = 5_000_000
    /// At most this many mixed-type keys per file, so one odd addon doesn't drown the list.
    public static let mixedTypesPerFile = 10

    /// Checks one file. `declared` is what the owning addon's manifest declares (nil when no installed addon owns it).
    public static func check(file: String, document doc: SVDocument, declared: [String]?) -> [SVProblem] {
        var problems: [SVProblem] = []
        func add(_ path: [LuaKey], _ kind: SVProblem.Kind, _ severity: SVProblem.Severity, _ message: String) {
            problems.append(SVProblem(file: file, path: path, kind: kind, severity: severity, message: message))
        }
        let size = doc.byteCount.formatted(.byteCount(style: .file))

        if let error = doc.error {
            if error.endedEarly {
                add(error.path, .endsEarly, .error, String(localized: "The file stops at line \(error.line), column \(error.column), as when the game quits while saving. The addon may lose its settings at the next login; a backup can bring them back.", bundle: .module))
            } else {
                add(error.path, .unreadable, .error, String(localized: "\(error.message) at line \(error.line), column \(error.column). The game can't read the file, so the addon starts with its defaults.", bundle: .module))
            }
        }
        if doc.byteCount == 0 || (doc.variables.isEmpty && doc.error == nil) {
            add([], .empty, .note, String(localized: "The file has nothing in it. The game rewrites it when the addon next saves.", bundle: .module))
        }
        if doc.byteCount >= largeFile {
            add([], .largeFile, .note, String(localized: "\(size). The game reads every SavedVariables file at each login and reload, so big ones slow loading screens.", bundle: .module))
        }

        if let declared {
            let saved = Set(doc.variables.compactMap { if case .string(let s) = $0.key { s } else { nil } })
            // Addons often still declare older names they no longer write, so one missing name is normal;
            // a file with none of them means the addon saves under names it doesn't declare.
            if doc.error == nil, !saved.isEmpty, saved.isDisjoint(with: declared) {
                add([], .missingVariable, .warning,
                    String(localized: "The addon declares \(declared.joined(separator: ", ")) but the file has none of them, so the game never loads what's here.", bundle: .module))
            }
            for variable in doc.variables {
                guard case .string(let name) = variable.key, !declared.contains(name) else { continue }
                add([variable.key], .unknownVariable, .warning,
                    String(localized: "The addon no longer declares \(name), so the game never loads it. Left by an older version: \(variable.span.count.formatted(.byteCount(style: .file))) it could do without.", bundle: .module))
            }
        }

        // Long lists, and keys whose type differs by character, account, server, or list item. Each shape
        // (the path with characters, accounts, servers, and list positions made alike) is an Int, so the
        // million entries of a big folder don't each build a string.
        struct ShapeKey: Hashable { let parent: Int; let key: String }
        var shapeIDs: [ShapeKey: Int] = [:]
        var shapeParts: [ShapeKey] = []
        func intern(_ parent: Int, _ key: String) -> Int {
            let k = ShapeKey(parent: parent, key: key)
            if let id = shapeIDs[k] { return id }
            shapeParts.append(k)
            shapeIDs[k] = shapeParts.count - 1
            return shapeParts.count - 1
        }
        func joined(_ id: Int) -> String {
            var keys: [String] = [], at = id
            while at >= 0 { keys.append(shapeParts[at].key); at = shapeParts[at].parent }
            return keys.reversed().joined(separator: "\u{1F}")
        }
        var shapes: [Int: [String: (count: Int, path: [LuaKey])]] = [:]
        func walk(_ entry: LuaEntry, parentPath: [LuaKey], shape: Int) {
            let level = SVLevel.of(entry.key, at: parentPath)
            var keyShape: String
            switch (level, entry.key) {
            case (.profile?, _), (.account?, _), (.character?, _), (.characterName?, _): keyShape = "*"
            case (_, .integer), (_, .number): keyShape = "#"
            default: keyShape = entry.key.description
            }
            if case .string(let s) = entry.key, CharacterID.isID(s) { keyShape = "*" }
            let here = intern(shape, keyShape)
            let type = entry.value.typeName
            // Positional lists ({ x, y, "name" }) mix types by design; compare named keys only.
            if case .string = entry.key, type != "boolean", type != "nil" {
                if shapes[here]?[type] == nil { shapes[here, default: [:]][type] = (0, parentPath + [entry.key]) }
                shapes[here]![type]!.count += 1
            }
            guard let table = entry.value.table else { return }
            let path = parentPath + [entry.key]
            let numbered = table.entries.allSatisfy { if case .integer = $0.key { true } else { false } }
            if table.count >= longList, numbered {
                add(path, .longList, .warning, String(localized: "A list of \(table.count.formatted()) entries (\(table.span.count.formatted(.byteCount(style: .file)))). Logs and histories like this grow every session; look in the addon's settings for a limit or a way to clear it.", bundle: .module))
            }
            for child in table.entries { walk(child, parentPath: path, shape: here) }
        }
        for variable in doc.variables { walk(variable, parentPath: [], shape: -1) }

        var mixed = 0
        let mixedShapes = shapes.filter { $0.value.count > 1 }.map { (key: joined($0.key), types: $0.value) }
        for (_, types) in mixedShapes.sorted(by: { $0.key < $1.key }) where mixed < mixedTypesPerFile {
            let sorted = types.sorted { $0.value.count > $1.value.count }
            guard let common = sorted.first, let odd = sorted.last else { continue }
            let key = odd.value.path.last?.description ?? ""
            add(odd.value.path, .typeMismatch, .warning,
                String(localized: "“\(key)” is a \(odd.key) here but a \(common.key) in \(String(localized: "\(common.value.count) other places", bundle: .module)). An addon that expects a \(common.key) can fail on this one.", bundle: .module))
            mixed += 1
        }
        return problems.sorted { ($0.severity, $1.file) > ($1.severity, $0.file) }
    }
}

/// SavedVariables files, and items beside AddOns, that nothing uses: what Clean Up offers to move to the Trash.
public enum SVFileProblems {
    /// A file an installed addon saves to, written this many days before the newest SavedVariables file, is stale:
    /// the game rewrites the file of every addon that loads, so that addon hasn't loaded on any character since.
    public static let staleDays = 90

    public static func check(files: [SavedVariablesFile], strays: [GameFolderItem]) -> [SVProblem] {
        let newest = files.filter { if case .addon = $0.owner { true } else { $0.owner == .game } }.compactMap(\.modified).max()
        var problems: [SVProblem] = []
        func add(_ name: String, _ kind: SVProblem.Kind, _ message: String, _ url: URL, _ bytes: Int64) {
            problems.append(SVProblem(file: name, path: [], kind: kind, severity: .note, message: message, url: url, bytes: bytes))
        }
        for file in files {
            let size = file.bytes.formatted(.byteCount(style: .file))
            switch file.owner {
            case .none:
                add(file.name, .unusedFile, String(localized: "No installed addon saves to this file, so the game never loads it: left by an addon you removed. \(size).", bundle: .module), file.url, file.bytes)
            case .copy:
                add(file.name, .copyFile, String(localized: "A copy or backup the game never reads, like one saved before an edit. \(size).", bundle: .module), file.url, file.bytes)
            case .addon(let addon):
                guard let newest, let modified = file.modified else { continue }
                let days = Int(newest.timeIntervalSince(modified) / 86_400)
                guard days >= staleDays else { continue }
                add(file.name, .staleFile, String(localized: "Written \(days) days before your newest SavedVariables file. The game rewrites the file of every addon that loads, so \(addon) hasn't loaded on any character since. Moving it to the Trash resets \(addon)'s settings if you turn it back on. \(size).", bundle: .module), file.url, file.bytes)
            case .game, .other:
                continue
            }
        }
        for item in strays {
            let size = item.bytes.formatted(.byteCount(style: .file))
            add(item.name, .strayItem, item.isFolder
                ? String(localized: "A folder beside AddOns that the game doesn't make or read, like a copy saved before an edit. \(size).", bundle: .module)
                : String(localized: "A file beside AddOns that the game doesn't make or read, like a copy saved before an edit. \(size).", bundle: .module),
                item.url, item.bytes)
        }
        return problems.sorted { $0.file.localizedStandardCompare($1.file) == .orderedAscending }
    }
}

extension SVProblem {
    /// This problem, about `addon`.
    func with(addon: String?) -> SVProblem {
        var copy = self
        copy.addon = addon
        return copy
    }
}
