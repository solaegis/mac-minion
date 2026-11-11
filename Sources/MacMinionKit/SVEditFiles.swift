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
                let data = try Data(contentsOf: url)
                let changed = try apply(changes, to: data)
                try changed.write(to: url, options: .atomic)
                out.before[url] = data
                out.after[url] = changed
                out.changed += changes.count
            } catch {
                out.failures.append((url.lastPathComponent, (error as? Failure)?.description ?? error.localizedDescription))
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
}
