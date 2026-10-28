import Foundation

/// What MacMinion knows about one installed addon.
public struct InstallRecord: Codable, Sendable, Hashable {
    public var id: Int
    /// The catalog version that was installed. Nil when found on disk, not installed here.
    public var version: String?
    public var md5: String?
    public var dirs: [String]
    public var ignored = false

    public init(id: Int, version: String?, md5: String? = nil, dirs: [String], ignored: Bool = false) {
        self.id = id; self.version = version; self.md5 = md5; self.dirs = dirs; self.ignored = ignored
    }
}

/// Everything saved to disk between launches.
public struct SavedState: Codable, Sendable {
    public var records: [Int: InstallRecord] = [:]
    public var importedFromMinion = false

    public init(records: [Int: InstallRecord] = [:], importedFromMinion: Bool = false) {
        self.records = records
        self.importedFromMinion = importedFromMinion
    }
}

public enum AddonStatus: String, Sendable, Hashable {
    case upToDate, updateAvailable, ignored, versionUnknown

    public var label: String {
        switch self {
        case .upToDate: "Up to date"
        case .updateAvailable: "Update available"
        case .ignored: "Ignored"
        case .versionUnknown: "Version unknown"
        }
    }
}

/// An installed addon, matched to the catalog.
public struct InstalledAddon: Sendable, Identifiable, Hashable {
    public var id: Int { catalog.id }
    public let catalog: CatalogAddon
    public let record: InstallRecord
    public let manifest: Manifest?

    public var installedVersion: String? { record.version ?? manifest?.version }

    public var status: AddonStatus {
        if record.ignored { return .ignored }
        guard let version = record.version else {
            if let mv = manifest?.version, VersionText.same(mv, catalog.version) { return .upToDate }
            return .versionUnknown
        }
        return VersionText.same(version, catalog.version) ? .upToDate : .updateAvailable
    }
}

/// A folder in AddOns that no catalog entry claims.
public struct UnmatchedFolder: Sendable, Identifiable, Hashable {
    public var id: String { folder }
    public let folder: String
    public let manifest: Manifest?
    public var title: String { manifest?.title.flatMap { $0.isEmpty ? nil : $0 } ?? folder }
}

public enum VersionText {
    /// Versions are free text ("2.0 r43", "v1.2"). Compared without spaces, case or a leading "v".
    public static func same(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased().filter { !$0.isWhitespace }
        if t.hasPrefix("v") { t.removeFirst() }
        return t
    }
}
