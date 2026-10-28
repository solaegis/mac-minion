import Foundation

/// One entry of the ESOUI catalog (`filelist.json`).
public struct CatalogAddon: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let categoryID: Int
    public let version: String
    public let date: Date
    public let name: String
    public let author: String
    public let infoURL: URL?
    public let downloads: Int
    public let downloadsMonthly: Int
    public let favorites: Int
    public let compatibility: [GameVersion]
    public let dirs: [String]
    public let thumbnails: [URL]
    public let images: [URL]

    public init(id: Int, categoryID: Int, version: String, date: Date, name: String, author: String,
                infoURL: URL? = nil, downloads: Int = 0, downloadsMonthly: Int = 0, favorites: Int = 0,
                compatibility: [GameVersion] = [], dirs: [String], thumbnails: [URL] = [], images: [URL] = []) {
        self.id = id; self.categoryID = categoryID; self.version = version; self.date = date
        self.name = name; self.author = author; self.infoURL = infoURL; self.downloads = downloads
        self.downloadsMonthly = downloadsMonthly; self.favorites = favorites
        self.compatibility = compatibility; self.dirs = dirs; self.thumbnails = thumbnails; self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case id = "UID", categoryID = "UICATID", version = "UIVersion", date = "UIDate", name = "UIName"
        case author = "UIAuthorName", infoURL = "UIFileInfoURL", downloads = "UIDownloadTotal"
        case downloadsMonthly = "UIDownloadMonthly", favorites = "UIFavoriteTotal"
        case compatibility = "UICompatibility", dirs = "UIDir", thumbnails = "UIIMG_Thumbs", images = "UIIMGs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        categoryID = (try? c.flexibleInt(.categoryID)) ?? 0
        version = (try? c.flexibleString(.version)) ?? ""
        date = Date(timeIntervalSince1970: Double((try? c.flexibleInt(.date)) ?? 0) / 1000)
        name = (try? c.flexibleString(.name)) ?? "Untitled"
        author = (try? c.flexibleString(.author)) ?? ""
        infoURL = (try? c.flexibleString(.infoURL)).flatMap(URL.init(string:))
        downloads = (try? c.flexibleInt(.downloads)) ?? 0
        downloadsMonthly = (try? c.flexibleInt(.downloadsMonthly)) ?? 0
        favorites = (try? c.flexibleInt(.favorites)) ?? 0
        compatibility = (try? c.decodeIfPresent([GameVersion].self, forKey: .compatibility)) ?? []
        dirs = (try? c.decodeIfPresent([String].self, forKey: .dirs)) ?? []
        thumbnails = ((try? c.decodeIfPresent([String].self, forKey: .thumbnails)) ?? []).compactMap(URL.init(string:))
        images = ((try? c.decodeIfPresent([String].self, forKey: .images)) ?? []).compactMap(URL.init(string:))
    }
}

public struct GameVersion: Codable, Sendable, Hashable {
    public let version: String
    public let name: String

    public init(version: String, name: String) {
        self.version = version
        self.name = name
    }
}

/// `filedetails/<uid>.json`: what an install needs, plus the long texts.
public struct AddonDetails: Decodable, Sendable {
    public let id: Int
    public let version: String
    public let md5: String
    public let fileName: String
    public let downloadURL: URL
    public let description: String
    public let changelog: String

    public init(id: Int, version: String, md5: String, fileName: String, downloadURL: URL,
                description: String = "", changelog: String = "") {
        self.id = id; self.version = version; self.md5 = md5; self.fileName = fileName
        self.downloadURL = downloadURL; self.description = description; self.changelog = changelog
    }

    enum CodingKeys: String, CodingKey {
        case id = "UID", version = "UIVersion", md5 = "UIMD5", fileName = "UIFileName"
        case downloadURL = "UIDownload", description = "UIDescription", changelog = "UIChangeLog"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        version = (try? c.flexibleString(.version)) ?? ""
        md5 = ((try? c.flexibleString(.md5)) ?? "").lowercased()
        fileName = (try? c.flexibleString(.fileName)) ?? "addon.zip"
        guard let url = URL(string: try c.flexibleString(.downloadURL)) else {
            throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: c, debugDescription: "bad download URL")
        }
        downloadURL = url
        description = (try? c.flexibleString(.description)) ?? ""
        changelog = (try? c.flexibleString(.changelog)) ?? ""
    }
}

/// `categorylist.json`.
public struct AddonCategory: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let iconURL: URL?
    public let fileCount: Int
    public let parentIDs: [Int]

    public init(id: Int, title: String, iconURL: URL? = nil, fileCount: Int = 0, parentIDs: [Int] = []) {
        self.id = id; self.title = title; self.iconURL = iconURL; self.fileCount = fileCount; self.parentIDs = parentIDs
    }

    /// Category 53 holds the libraries other addons depend on.
    public static let librariesID = 53

    enum CodingKeys: String, CodingKey {
        case id = "UICATID", title = "UICATTitle", iconURL = "UICATICON", fileCount = "UICATFileCount", parentIDs = "UICATParentIDs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        title = (try? c.flexibleString(.title)) ?? ""
        iconURL = (try? c.flexibleString(.iconURL)).flatMap(URL.init(string:))
        fileCount = (try? c.flexibleInt(.fileCount)) ?? 0
        parentIDs = ((try? c.decodeIfPresent([String].self, forKey: .parentIDs)) ?? []).compactMap { Int($0) }
    }

    /// The ids of this category and every category under it.
    public static func descendants(of id: Int, in all: [AddonCategory]) -> Set<Int> {
        var out: Set<Int> = [id]
        var changed = true
        while changed {
            changed = false
            for c in all where !out.contains(c.id) && c.parentIDs.contains(where: out.contains) {
                out.insert(c.id)
                changed = true
            }
        }
        return out
    }
}

/// The feeds return numbers as strings in some places and as numbers in others.
extension KeyedDecodingContainer {
    func flexibleString(_ key: Key) throws -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int64.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(d) }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "missing \(key.stringValue)"))
    }

    func flexibleInt(_ key: Key) throws -> Int {
        if let i = try? decode(Int64.self, forKey: key) { return Int(i) }
        if let s = try? decode(String.self, forKey: key), let i = Int64(s.trimmingCharacters(in: .whitespaces)) { return Int(i) }
        if let d = try? decode(Double.self, forKey: key) { return Int(d) }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "missing \(key.stringValue)"))
    }
}
