import Foundation

/// One place every MacMinion Lua SavedVariables write goes through: re-parse, path check, stale-file
/// check, one-file `.macminion.bak`, then atomic replace. Refuses without touching the target when
/// any check fails.
public enum SavedVariablesWrite {
    public enum Refusal: Error, Equatable, LocalizedError, CustomStringConvertible {
        /// The new bytes do not parse as SavedVariables Lua.
        case parseFailed(String)
        /// Keys or values outside the intended edit paths changed.
        case unintendedChanges
        /// Size, modification date, or bytes changed since the bytes we edited were read.
        case fileChangedSinceRead
        /// Could not write the backup or the file.
        case io(String)

        public var description: String {
            switch self {
            case .parseFailed(let why):
                String(localized: "The new SavedVariables text doesn't parse: \(why)", bundle: .module)
            case .unintendedChanges:
                String(localized: "The edit would change keys MacMinion wasn't asked to change.", bundle: .module)
            case .fileChangedSinceRead:
                String(localized: "The file changed on disk since it was read, so nothing was written.", bundle: .module)
            case .io(let why):
                String(localized: "Couldn't write the SavedVariables file: \(why)", bundle: .module)
            }
        }

        public var errorDescription: String? { description }
    }

    /// What we read before editing: bytes plus size and modification date for the stale check.
    public struct Stamp: Equatable, Sendable {
        public let data: Data
        public let size: Int64
        public let modificationDate: Date?

        public init(data: Data, size: Int64, modificationDate: Date?) {
            self.data = data
            self.size = size
            self.modificationDate = modificationDate
        }

        public static func read(url: URL) throws -> Stamp {
            let data = try Data(contentsOf: url)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
            let date = attrs[.modificationDate] as? Date
            return Stamp(data: data, size: size, modificationDate: date)
        }

        /// True when the file on disk still matches this stamp (bytes, size, and mtime).
        public func matchesFile(at url: URL) -> Bool {
            guard let current = try? Stamp.read(url: url) else { return false }
            return current.size == size
                && current.modificationDate == modificationDate
                && current.data == data
        }
    }

    /// Suffix for the single rotating backup kept next to the file.
    public static let backupSuffix = ".macminion.bak"

    /// Writes `newData` to `url` only when it parses, only allowed paths differ from `stamp.data`,
    /// and the file on disk still matches `stamp`. Rotates `url` + `backupSuffix` first.
    public static func write(
        _ newData: Data,
        to url: URL,
        previouslyRead stamp: Stamp,
        allowed: Set<LuaCompare.AllowedPath>
    ) throws {
        let newDoc = SVDocument.parse(newData)
        if let error = newDoc.error {
            throw Refusal.parseFailed(error.description)
        }
        let oldDoc = SVDocument.parse(stamp.data)
        if oldDoc.error != nil {
            // Editing a file we already refused to treat as a tree shouldn't happen; still refuse.
            throw Refusal.parseFailed(String(localized: "The original file doesn't parse.", bundle: .module))
        }
        if !LuaCompare.onlyAllowedPathsDiffer(old: oldDoc, new: newDoc, allowed: allowed) {
            throw Refusal.unintendedChanges
        }
        guard stamp.matchesFile(at: url) else { throw Refusal.fileChangedSinceRead }
        do {
            try rotateBackup(of: url, previousBytes: stamp.data)
            try newData.write(to: url, options: .atomic)
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.io(error.localizedDescription)
        }
    }

    /// Same checks without an allowlist: used when putting back exact undo bytes (must parse; may
    /// differ arbitrarily from stamp only if `allowed` says so). Prefer the allowlist overload.
    public static func writeUndo(
        _ newData: Data,
        to url: URL,
        expecting: Data
    ) throws {
        let newDoc = SVDocument.parse(newData)
        if let error = newDoc.error {
            throw Refusal.parseFailed(error.description)
        }
        let onDisk = try Data(contentsOf: url)
        guard onDisk == expecting else { throw Refusal.fileChangedSinceRead }
        let stamp = try Stamp.read(url: url)
        guard stamp.data == expecting else { throw Refusal.fileChangedSinceRead }
        do {
            try rotateBackup(of: url, previousBytes: expecting)
            try newData.write(to: url, options: .atomic)
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.io(error.localizedDescription)
        }
    }

    static func rotateBackup(of url: URL, previousBytes: Data) throws {
        let bak = url.appendingPathExtension("macminion.bak")
        // Prefer `name.lua.macminion.bak` — appendingPathExtension on `foo.lua` yields `foo.lua.macminion.bak` only
        // if we use a custom path. `appendingPathExtension` replaces? No — `file.lua` + ext `macminion.bak` → `file.lua.macminion.bak`.
        let fm = FileManager.default
        if fm.fileExists(atPath: bak.path) {
            try? fm.removeItem(at: bak)
        }
        try previousBytes.write(to: bak, options: .atomic)
    }

    /// Backup URL beside a SavedVariables file: `Name.lua.macminion.bak`.
    public static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("macminion.bak")
    }
}
