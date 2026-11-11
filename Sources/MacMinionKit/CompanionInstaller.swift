import Foundation

/// Copies the bundled ESO Mac Minion addon into AddOns. Call only while the game is closed.
public enum CompanionInstaller {
    /// `source` is the `EsoMacMinion` folder (manifest plus Lua). Replaces an older copy of the same folder.
    public static func install(from source: URL, into addons: URL) throws {
        let name = CompanionData.folderName
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appending(path: "\(name).txt").path)
                || fm.fileExists(atPath: source.appending(path: "\(name).addon").path) else {
            throw InstallError.companionMissing
        }
        let work = fm.temporaryDirectory.appending(path: "MacMinion-companion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let staged = work.appending(path: name, directoryHint: .isDirectory)
        try fm.copyItem(at: source, to: staged)
        try fm.createDirectory(at: addons, withIntermediateDirectories: true)
        let dest = addons.appending(path: name, directoryHint: .isDirectory)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: staged, to: dest)
    }

    public static func isPresent(in addons: URL) -> Bool {
        let folder = addons.appending(path: CompanionData.folderName, directoryHint: .isDirectory)
        return Manifest.read(folder: folder) != nil
    }
}
