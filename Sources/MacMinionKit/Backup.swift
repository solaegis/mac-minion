import Foundation

/// One backup in Minion's layout:
///   <backup-dir>/minion-backups/<game id>/<yyyy-MM-dd>.zip          settings and SavedVariables
///   <backup-dir>/minion-backups/<game id>/<yyyy-MM-dd>-addons.txt   installed ESOUI ids: "7,57,1360,"
///   <backup-dir>/initial-backup/<game id>.zip                        the whole AddOns folder, made once
/// Zip entries are absolute paths with a leading slash. MacMinion reads and writes the same files, so
/// either app can restore the other's backups.
public struct Backup: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case snapshot, initial }

    public var id: String { zip?.path ?? addonList?.path ?? name }
    public let kind: Kind
    /// "2026-09-14", or "Initial" for the initial backup.
    public let name: String
    public let date: Date?
    public let zip: URL?
    public let addonList: URL?
    public let bytes: Int64

    public var addonIDs: [Int] { addonList.map(MinionBackup.readAddonList) ?? [] }
}

public enum MinionBackup {
    public static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `<backup-dir>/minion-backups/<game id>`.
    public static func snapshotFolder(backupDir: URL, gameID: String) -> URL {
        backupDir.appending(path: "minion-backups/\(gameID)", directoryHint: .isDirectory)
    }

    public static func initialZip(backupDir: URL, gameID: String) -> URL {
        backupDir.appending(path: "initial-backup/\(gameID).zip")
    }

    /// Snapshots newest first, then the initial backup.
    public static func list(backupDir: URL, gameID: String) -> [Backup] {
        let fm = FileManager.default
        let folder = snapshotFolder(backupDir: backupDir, gameID: gameID)
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        var days = Set<String>()
        for name in names {
            if name.hasSuffix("-addons.txt") { days.insert(String(name.dropLast("-addons.txt".count))) }
            else if name.hasSuffix(".zip") { days.insert(String(name.dropLast(4))) }
        }
        var out: [Backup] = days.compactMap { day in
            guard let date = dayFormat.date(from: day) else { return nil }
            let zip = folder.appending(path: "\(day).zip")
            let list = folder.appending(path: "\(day)-addons.txt")
            let hasZip = fm.fileExists(atPath: zip.path), hasList = fm.fileExists(atPath: list.path)
            return Backup(kind: .snapshot, name: day, date: date, zip: hasZip ? zip : nil, addonList: hasList ? list : nil,
                          bytes: hasZip ? size(zip) : 0)
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let initial = initialZip(backupDir: backupDir, gameID: gameID)
        if fm.fileExists(atPath: initial.path) {
            let date = (try? initial.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            out.append(Backup(kind: .initial, name: "Initial", date: date, zip: initial, addonList: nil, bytes: size(initial)))
        }
        return out
    }

    static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// "7,57,1360," -> [7, 57, 1360].
    public static func readAddonList(_ url: URL) -> [Int] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Int($0) }
    }

    /// Minion's rule for what a snapshot holds, relative to the game folder (`.../live`):
    /// AddOnSettings.txt*, UserSettings.txt*, and everything under SavedVariables.
    public static func belongsInSnapshot(_ relative: String) -> Bool {
        relative.hasPrefix("SavedVariables/")
            || (!relative.contains("/") && (relative.hasPrefix("AddOnSettings.txt") || relative.hasPrefix("UserSettings.txt")))
    }

    /// Writes today's snapshot (replacing one from earlier today, as Minion does) and its addon list.
    @discardableResult
    public static func create(gameFolder: URL, addonIDs: [Int], backupDir: URL, gameID: String, date: Date = .now) throws -> Backup {
        let fm = FileManager.default
        let folder = snapshotFolder(backupDir: backupDir, gameID: gameID)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let day = dayFormat.string(from: date)
        var entries: [ZipWriter.Entry] = []
        let base = gameFolder.standardizedFileURL.path
        if let walker = fm.enumerator(at: gameFolder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) {
            for case let url as URL in walker {
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base + "/") else { continue }
                let relative = String(path.dropFirst(base.count + 1))
                // Don't walk AddOns: thousands of files, none of them backed up here.
                if relative == "AddOns" || relative == "Logs" || relative == "Screenshots" { walker.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true, belongsInSnapshot(relative), let data = try? Data(contentsOf: url) else { continue }
                entries.append(.init(name: path, data: data, modified: values?.contentModificationDate ?? date))
            }
        }
        let zip = folder.appending(path: "\(day).zip")
        try ZipWriter.write(entries.sorted { $0.name < $1.name }, to: zip)
        let list = folder.appending(path: "\(day)-addons.txt")
        try addonIDs.map { "\($0)," }.joined().write(to: list, atomically: true, encoding: .utf8)
        return Backup(kind: .snapshot, name: day, date: dayFormat.date(from: day), zip: zip, addonList: list, bytes: size(zip))
    }

    /// Unpacks a backup zip and maps each file back into `gameFolder`, wherever the backup was made
    /// (another Mac, another user, live or PTS): the path is taken from "AddOns", "SavedVariables",
    /// or a top-level settings file onward. Returns files ready to copy: (unpacked file, destination).
    public static func unpack(_ zip: URL, into work: URL, gameFolder: URL) throws -> [(source: URL, destination: URL)] {
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-qq", zip.path, "-d", work.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        // unzip exits 1 for warnings such as "stripped absolute path spec": the files are still there.
        guard p.terminationStatus <= 1 else { throw BackupError.unzip }
        var out: [(URL, URL)] = []
        guard let walker = fm.enumerator(at: work, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let relative = relativeToGame(url.standardizedFileURL.path.dropFirst(work.standardizedFileURL.path.count + 1))
            else { continue }
            out.append((url, gameFolder.appending(path: relative)))
        }
        return out
    }

    /// "Users/me/Documents/Elder Scrolls Online/live/SavedVariables/X.lua" -> "SavedVariables/X.lua".
    static func relativeToGame(_ path: Substring) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if let i = parts.lastIndex(where: { $0 == "SavedVariables" || $0 == "AddOns" }), i < parts.count - 1 {
            return parts[i...].joined(separator: "/")
        }
        if let last = parts.last, last.hasPrefix("AddOnSettings.txt") || last.hasPrefix("UserSettings.txt") { return last }
        return nil
    }
}

public enum BackupError: LocalizedError {
    case unzip
    public var errorDescription: String? { "The backup couldn't be unpacked." }
}
