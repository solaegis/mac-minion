import Foundation

/// Puts files from a backup back into the game folder. Always saves what is there first (under
/// `safetyRoot`, see `MinionBackup.saveBeforeRestore`), so a restore can itself be undone.
/// Runs off the main actor: unpacking and copying a whole AddOns backup takes a while.
public struct BackupRestore: Sendable {
    public let gameFolder: URL
    public let safetyRoot: URL

    public init(gameFolder: URL, safetyRoot: URL) {
        self.gameFolder = gameFolder
        self.safetyRoot = safetyRoot
    }

    public var addonsFolder: URL { gameFolder.appending(path: "AddOns", directoryHint: .isDirectory) }

    public enum Scope: Sendable, Equatable {
        /// Save what is there, put nothing back.
        case saveOnly
        /// Every file in the backup zip. Addon folders it holds replace the installed ones whole.
        case everything(from: URL)
        /// One file, as a path under the game folder: "SavedVariables/X.lua". Other files stay as they are.
        case file(String, from: URL)
    }

    public struct Result: Sendable {
        /// Where what was there before is saved.
        public let safety: URL
        public let restored: Int
    }

    public enum Failure: Error {
        /// Nothing changed: what is there now couldn't be saved first.
        case couldNotSaveFirst(any Error)
        /// The restore started and stopped part way; what was there before is in `safety`.
        case stopped(any Error, safety: URL)
        /// The backup doesn't hold the one file asked for. Nothing was put back.
        case notInBackup(safety: URL)
    }

    /// Saves what is there, then puts `scope` back. Calls `restoring` once the save is done
    /// and files are about to change.
    @concurrent
    public func run(_ scope: Scope, addonIDs: [Int],
                    restoring: @Sendable () async -> Void = {}) async throws(Failure) -> Result {
        let safety: URL
        do {
            safety = try MinionBackup.saveBeforeRestore(gameFolder: gameFolder, addonIDs: addonIDs, root: safetyRoot)
        } catch {
            throw .couldNotSaveFirst(error)
        }
        guard scope != .saveOnly else { return Result(safety: safety, restored: 0) }
        await restoring()
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "MacMinion-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        do {
            let files: [(source: URL, destination: URL)]
            switch scope {
            case .saveOnly:
                files = []
            case .everything(let zip):
                files = try MinionBackup.unpack(zip, into: work, gameFolder: gameFolder)
                // A full AddOns backup replaces whole addon folders, so files from a newer version don't linger.
                for folder in Self.replacedAddonFolders(files.map(\.destination), gameFolder: gameFolder)
                where fm.fileExists(atPath: addonsFolder.appending(path: folder).path) {
                    try fm.trashItem(at: addonsFolder.appending(path: folder), resultingItemURL: nil)
                }
            case .file(let relative, let zip):
                guard let source = try MinionBackup.unpack(relative, from: zip, into: work) else {
                    throw Failure.notInBackup(safety: safety)
                }
                files = [(source, gameFolder.appending(path: relative))]
            }
            for f in files {
                try fm.createDirectory(at: f.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: f.destination.path) { try fm.removeItem(at: f.destination) }
                try fm.copyItem(at: f.source, to: f.destination)
            }
            return Result(safety: safety, restored: files.count)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .stopped(error, safety: safety)
        }
    }

    /// The addon folders a set of restored files replaces: "AddOns/<folder>/…" with at least one level below.
    static func replacedAddonFolders(_ destinations: [URL], gameFolder: URL) -> Set<String> {
        Set(destinations.compactMap { url -> String? in
            let rel = url.path.dropFirst(gameFolder.path.count + 1).split(separator: "/")
            return rel.count > 2 && rel[0] == "AddOns" ? String(rel[1]) : nil
        })
    }
}
