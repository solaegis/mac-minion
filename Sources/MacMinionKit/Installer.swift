import CryptoKit
import Foundation

/// Downloads an addon zip, checks it, and swaps its folders into AddOns.
/// Nothing in AddOns changes until the zip is verified and unpacked.
public struct Installer: Sendable {
    public let addons: URL
    let session: URLSession

    public init(addons: URL, session: URLSession = .shared) {
        self.addons = addons
        self.session = session
    }

    /// Installs and returns the record to save.
    public func install(_ details: AddonDetails) async throws -> InstallRecord {
        let work = FileManager.default.temporaryDirectory.appending(path: "MacMinion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let data: Data
        if details.downloadURL.isFileURL {
            data = try Data(contentsOf: details.downloadURL)
        } else {
            var request = URLRequest(url: details.downloadURL, timeoutInterval: 120)
            request.setValue("MacMinion", forHTTPHeaderField: "User-Agent")
            let (body, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw InstallError.download(http.statusCode)
            }
            data = body
        }
        let md5 = Self.md5(data)
        if !details.md5.isEmpty, md5 != details.md5 { throw InstallError.checksum }

        let zip = work.appending(path: "addon.zip")
        try data.write(to: zip)
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        try Self.unzip(zip, to: unpacked)

        let dirs = try FileManager.default.contentsOfDirectory(atPath: unpacked.path).filter { name in
            var isDir: ObjCBool = false
            return !name.hasPrefix(".") && name != "__MACOSX"
                && FileManager.default.fileExists(atPath: unpacked.appending(path: name).path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
        guard !dirs.isEmpty else { throw InstallError.empty }

        try swap(dirs, from: unpacked, backup: work.appending(path: "old", directoryHint: .isDirectory))
        return InstallRecord(id: details.id, version: details.version, md5: md5, dirs: dirs)
    }

    /// Moves the current folders aside, moves the new ones in, and puts the old ones back if any step fails.
    func swap(_ dirs: [String], from source: URL, backup: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        try fm.createDirectory(at: addons, withIntermediateDirectories: true)
        var movedAside: [String] = []
        var movedIn: [String] = []
        do {
            for dir in dirs where fm.fileExists(atPath: addons.appending(path: dir).path) {
                try fm.moveItem(at: addons.appending(path: dir), to: backup.appending(path: dir))
                movedAside.append(dir)
            }
            for dir in dirs {
                try fm.moveItem(at: source.appending(path: dir), to: addons.appending(path: dir))
                movedIn.append(dir)
            }
        } catch {
            for dir in movedIn { try? fm.removeItem(at: addons.appending(path: dir)) }
            for dir in movedAside { try? fm.moveItem(at: backup.appending(path: dir), to: addons.appending(path: dir)) }
            throw error
        }
    }

    /// Moves the addon's folders to the Trash. SavedVariables stay.
    public func remove(_ dirs: [String]) throws {
        for dir in dirs {
            let url = addons.appending(path: dir)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
    }

    public static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func unzip(_ zip: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dest.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw InstallError.unzip }
    }
}

public enum InstallError: LocalizedError, Equatable {
    case download(Int), checksum, unzip, empty

    public var errorDescription: String? {
        switch self {
        case .download(let code): "The download failed (\(code))."
        case .checksum: "The download didn't match its checksum."
        case .unzip: "The zip couldn't be unpacked."
        case .empty: "The zip has no addon folders."
        }
    }
}
