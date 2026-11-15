import Foundation

extension SVEdit {
    /// What writing changes into SavedVariables files did: each changed file's bytes before and after (for
    /// undo), how many changes went in, and why any file was left as it was.
    public struct FileEdits: Sendable {
        public var before: [URL: Data] = [:]
        public var after: [URL: Data] = [:]
        public var changed = 0
        /// In file-name order: (file name, why it wasn't changed).
        public var failures: [(file: String, why: String)] = []
    }

    /// Reads each file, applies its changes, and writes it back atomically, in file-name order. A file that
    /// can't be read, changed, or written is left as it was; the others still change. Runs off the main actor.
    @concurrent
    public static func apply(toFiles byFile: [URL: [Change]]) async -> FileEdits {
        var out = FileEdits()
        for (url, changes) in byFile.sorted(by: { $0.key.lastPathComponent < $1.key.lastPathComponent }) {
            do {
                let stamp = try SavedVariablesWrite.Stamp.read(url: url)
                let changed = try apply(changes, to: stamp.data)
                let allowed = Set(changes.map { LuaCompare.AllowedPath.exact($0.path) })
                try SavedVariablesWrite.write(changed, to: url, previouslyRead: stamp, allowed: allowed)
                out.before[url] = stamp.data
                out.after[url] = changed
                out.changed += changes.count
            } catch {
                let why: String
                if let failure = error as? Failure {
                    why = failure.description
                } else if let refusal = error as? SavedVariablesWrite.Refusal {
                    why = refusal.description
                } else {
                    why = error.localizedDescription
                }
                out.failures.append((url.lastPathComponent, why))
            }
        }
        return out
    }
}

extension SettingsMatrix {
    /// The edits that copy these settings from `from` to `to`, by addon file. Settings `from` doesn't have,
    /// or that have no place to go for `to`, are left out.
    public func copyChanges(_ rows: [(file: String, key: String)], from: String, to: String) -> [String: [SVEdit.Change]] {
        var byFile: [String: [SVEdit.Change]] = [:]
        for row in rows {
            guard let value = addon(row.file)?.characters[from]?[row.key]?.value,
                  let path = target(file: row.file, key: row.key, from: from, to: to) else { continue }
            byFile[row.file, default: []].append(SVEdit.Change(path: path, value: value))
        }
        return byFile
    }

    /// One Compare radio choice: copy `from`'s value to the other character, or remove the other's key when
    /// `from` has no key for this setting.
    public struct CloneOp: Hashable, Sendable {
        public let file: String
        public let key: String
        public let from: String
        public let to: String

        public init(file: String, key: String, from: String, to: String) {
            self.file = file
            self.key = key
            self.from = from
            self.to = to
        }
    }

    /// Whether this op would delete `to`'s key (source has no setting).
    public func cloneOpDeletes(_ op: CloneOp) -> Bool {
        addon(op.file)?.characters[op.from]?[op.key] == nil
            && addon(op.file)?.characters[op.to]?[op.key] != nil
    }

    /// Edits for Compare Clone: copy when the source has the setting; remove when it doesn't and the other does.
    public func cloneChanges(_ ops: [CloneOp]) -> [String: [SVEdit.Change]] {
        var byFile: [String: [SVEdit.Change]] = [:]
        for op in ops {
            let fileAddon = addon(op.file)
            if let value = fileAddon?.characters[op.from]?[op.key]?.value,
               let path = target(file: op.file, key: op.key, from: op.from, to: op.to) {
                byFile[op.file, default: []].append(SVEdit.Change(path: path, value: value))
            } else if fileAddon?.characters[op.from]?[op.key] == nil,
                      let path = fileAddon?.characters[op.to]?[op.key]?.path {
                byFile[op.file, default: []].append(.remove(path: path))
            }
        }
        return byFile
    }
}
