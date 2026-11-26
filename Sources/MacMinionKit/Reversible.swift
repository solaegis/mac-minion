import Foundation

/// Why an undo or redo left the files as they were.
public enum ReversalError: LocalizedError, Equatable {
    /// These files changed after the action (ESO, an editor, or another app wrote them), so putting back the
    /// old bytes would lose those changes.
    case changedSince([String])
    /// Something is in the way: a file or folder with this name is back where the item would return.
    case occupied([String])
    /// What undo needs is gone: emptied from the Trash, or a stash cleared at launch.
    case missing([String])

    public var errorDescription: String? {
        switch self {
        case .changedSince(let names):
            String(localized: "\(names.joined(separator: ", ")) changed since, so nothing was put back.", bundle: .kit)
        case .occupied(let names):
            String(localized: "\(names.joined(separator: ", ")) is in the way, so nothing was put back.", bundle: .kit)
        case .missing(let names):
            String(localized: "\(names.joined(separator: ", ")) is no longer there to put back.", bundle: .kit)
        }
    }
}

/// Byte snapshots of small files (settings, SavedVariables) for undo.
public enum FileSnapshot {
    /// Writes `bytes` to each file, but only when every file still holds `expecting`: a file the game or
    /// another app changed since is never overwritten. Checks all files first, writes via temps, and on any
    /// failure restores already-written URLs so either all change or none.
    public static func write(_ bytes: [URL: Data], expecting: [URL: Data]) throws {
        let changed = bytes.keys.filter { url in (try? Data(contentsOf: url)) != expecting[url] }
        guard changed.isEmpty else { throw ReversalError.changedSince(changed.map(\.lastPathComponent).sorted()) }
        let missingExpect = bytes.keys.filter { expecting[$0] == nil }
        guard missingExpect.isEmpty else {
            throw ReversalError.changedSince(missingExpect.map(\.lastPathComponent).sorted())
        }
        var written: [(url: URL, previous: Data)] = []
        do {
            for (url, data) in bytes.sorted(by: { $0.key.path < $1.key.path }) {
                let previous = expecting[url]!
                if url.pathExtension.lowercased() == "lua" {
                    try SavedVariablesWrite.writeUndo(data, to: url, expecting: previous)
                } else {
                    try data.write(to: url, options: .atomic)
                }
                written.append((url, previous))
            }
        } catch {
            for (url, previous) in written.reversed() {
                if url.pathExtension.lowercased() == "lua" {
                    try? SavedVariablesWrite.writeUndo(previous, to: url, expecting: (try? Data(contentsOf: url)) ?? previous)
                } else {
                    try? previous.write(to: url, options: .atomic)
                }
            }
            throw error
        }
    }
}

/// An item moved to the Trash, and where it was.
public struct TrashedItem: Sendable, Hashable {
    public let original: URL
    public let trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original
        self.trashed = trashed
    }
}

/// Moves to the Trash that can be put back.
public enum TrashMove {
    /// Moves one item to the Trash and says where it went.
    public static func trash(_ url: URL) throws -> TrashedItem {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return TrashedItem(original: url, trashed: (resulting as URL?) ?? url)
    }

    /// Moves items back from the Trash. Checks first that each is still in the Trash and nothing has taken its
    /// place, so either all come back or none do. Mid-loop failure puts already-restored items back in the Trash.
    public static func putBack(_ items: [TrashedItem]) throws {
        let fm = FileManager.default
        let gone = items.filter { !fm.fileExists(atPath: $0.trashed.path) }
        guard gone.isEmpty else { throw ReversalError.missing(gone.map(\.original.lastPathComponent).sorted()) }
        let taken = items.filter { fm.fileExists(atPath: $0.original.path) }
        guard taken.isEmpty else { throw ReversalError.occupied(taken.map(\.original.lastPathComponent).sorted()) }
        var restored: [TrashedItem] = []
        do {
            for item in items {
                try fm.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: item.trashed, to: item.original)
                restored.append(item)
            }
        } catch {
            for item in restored.reversed() {
                try? fm.moveItem(at: item.original, to: item.trashed)
            }
            throw error
        }
    }

    /// Moves items that were put back to the Trash again (redo), returning where they went this time.
    public static func trashAgain(_ items: [TrashedItem], using trash: (URL) throws -> TrashedItem = trash) throws -> [TrashedItem] {
        let missing = items.filter { !FileManager.default.fileExists(atPath: $0.original.path) }
        guard missing.isEmpty else { throw ReversalError.missing(missing.map(\.original.lastPathComponent).sorted()) }
        return try items.map { try trash($0.original) }
    }
}

/// Swaps addon folders between AddOns and a holding folder, so an install or update can be undone without
/// downloading again.
public enum FolderExchange {
    /// Moves `takeOut` from `addons` into `holding`, then `putIn` from `source` into `addons`. Checks first
    /// that every folder is where it should be; if a move fails part way, puts back what already moved.
    public static func exchange(in addons: URL, takeOut: [String], to holding: URL, putIn: [String], from source: URL) throws {
        let fm = FileManager.default
        func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
        let missingOut = takeOut.filter { !exists(addons.appending(path: $0)) }
        let missingIn = putIn.filter { !exists(source.appending(path: $0)) }
        guard missingOut.isEmpty, missingIn.isEmpty else { throw ReversalError.missing((missingOut + missingIn).sorted()) }
        let blocked = putIn.filter { !takeOut.contains($0) && exists(addons.appending(path: $0)) }
            + takeOut.filter { exists(holding.appending(path: $0)) }
        guard blocked.isEmpty else { throw ReversalError.occupied(blocked.sorted()) }
        try fm.createDirectory(at: holding, withIntermediateDirectories: true)
        try fm.createDirectory(at: addons, withIntermediateDirectories: true)
        var movedOut: [String] = [], movedIn: [String] = []
        do {
            for dir in takeOut {
                try fm.moveItem(at: addons.appending(path: dir), to: holding.appending(path: dir))
                movedOut.append(dir)
            }
            for dir in putIn {
                try fm.moveItem(at: source.appending(path: dir), to: addons.appending(path: dir))
                movedIn.append(dir)
            }
        } catch {
            for dir in movedIn { try? fm.moveItem(at: addons.appending(path: dir), to: source.appending(path: dir)) }
            for dir in movedOut { try? fm.moveItem(at: holding.appending(path: dir), to: addons.appending(path: dir)) }
            throw error
        }
    }

    /// The folders in `folder`, by name, without hidden files.
    public static func folders(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }
}
