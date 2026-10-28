import Foundation

/// Matches the folders in AddOns to catalog entries.
public enum AddonMatcher {
    public struct Result: Sendable {
        public var installed: [InstalledAddon]
        public var unmatched: [UnmatchedFolder]
        /// Records to save: known ones still on disk, plus new ones found by folder name.
        public var records: [Int: InstallRecord]
    }

    /// Top-level folders of the AddOns folder, with their manifests. Nil when the folder can't be read
    /// (missing, or macOS privacy denied it), so callers never mistake "can't look" for "nothing installed".
    public static func scan(_ addons: URL) -> [String: Manifest?]? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: addons.path) else { return nil }
        var out: [String: Manifest?] = [:]
        for name in names where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            let url = addons.appending(path: name, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            out[name] = Manifest.read(folder: url)
        }
        return out
    }

    /// Addon folders bundled inside other addons (`AddOns/SuperStar/libs/LibSkillsFactory`), up to three
    /// levels down, as ESO loads them: a folder counts when it has its own `<name>.txt` or `<name>.addon`.
    public static func nested(_ addons: URL, depth: Int = 3) -> Set<String> {
        let fm = FileManager.default
        var found = Set<String>()
        func walk(_ dir: URL, _ level: Int) {
            guard level <= depth, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in names where !name.hasPrefix(".") {
                let url = dir.appending(path: name, directoryHint: .isDirectory)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if level > 1, ["txt", "addon"].contains(where: { fm.fileExists(atPath: url.appending(path: "\(name).\($0)").path) }) {
                    found.insert(name)
                }
                walk(url, level + 1)
            }
        }
        walk(addons, 1)
        return found
    }

    public static func match(folders: [String: Manifest?], catalog: [CatalogAddon], records: [Int: InstallRecord]) -> Result {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var claimed = Set<String>()
        var kept: [Int: InstallRecord] = [:]

        // 1. Known installs whose main folder still exists.
        for record in records.values.sorted(by: { $0.id < $1.id }) {
            guard byID[record.id] != nil, let first = record.dirs.first, folders.keys.contains(first) else { continue }
            let present = record.dirs.filter { folders.keys.contains($0) }
            kept[record.id] = InstallRecord(id: record.id, version: record.version, md5: record.md5, dirs: present, ignored: record.ignored)
            claimed.formUnion(present)
        }

        // 2. Unclaimed folders: the catalog entry whose UIDir folders are all present. Most folders, then most downloads.
        var index: [String: [CatalogAddon]] = [:]
        for addon in catalog { for dir in addon.dirs { index[dir, default: []].append(addon) } }
        for folder in folders.keys.sorted() where !claimed.contains(folder) {
            let candidates = (index[folder] ?? []).filter { kept[$0.id] == nil && $0.dirs.allSatisfy { folders.keys.contains($0) } }
            guard let best = candidates.max(by: { ($0.dirs.count, $0.downloads) < ($1.dirs.count, $1.downloads) }) else { continue }
            kept[best.id] = InstallRecord(id: best.id, version: nil, dirs: best.dirs)
            claimed.formUnion(best.dirs)
        }

        let installed = kept.values.compactMap { r -> InstalledAddon? in
            guard let c = byID[r.id] else { return nil }
            return InstalledAddon(catalog: c, record: r, manifest: r.dirs.first.flatMap { folders[$0] ?? nil })
        }.sorted { $0.catalog.name.localizedStandardCompare($1.catalog.name) == .orderedAscending }

        let unmatched = folders.filter { !claimed.contains($0.key) }
            .map { UnmatchedFolder(folder: $0.key, manifest: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return Result(installed: installed, unmatched: unmatched, records: kept)
    }
}
