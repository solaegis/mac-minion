import Foundation

/// The public ESOUI feeds Minion uses (`api.mmoui.com/v3`). No login.
public struct MMOUIClient: Sendable {
    public static let base = URL(string: "https://api.mmoui.com/v3/game/ESO/")!
    let base: URL
    let session: URLSession

    public init(base: URL = MMOUIClient.base, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    public func catalogData() async throws -> Data {
        try await get(base.appending(path: "filelist.json"))
    }

    public func categoriesData() async throws -> Data {
        try await get(base.appending(path: "categorylist.json"))
    }

    public func details(for id: Int) async throws -> AddonDetails {
        let data = try await get(base.appending(path: "filedetails/\(id).json"))
        guard let first = try JSONDecoder().decode([AddonDetails].self, from: data).first else {
            throw FeedError.notFound(id)
        }
        return first
    }

    public static func decodeCatalog(_ data: Data) throws -> [CatalogAddon] {
        try JSONDecoder().decode([CatalogAddon].self, from: data)
    }

    public static func decodeCategories(_ data: Data) throws -> [AddonCategory] {
        try JSONDecoder().decode([AddonCategory].self, from: data)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("MacMinion", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.http(http.statusCode, url)
        }
        return data
    }
}

public enum FeedError: LocalizedError, Equatable {
    case http(Int, URL)
    case notFound(Int)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let url): "ESOUI answered \(code) for \(url.lastPathComponent)."
        case .notFound(let id): "ESOUI has no addon with id \(id)."
        }
    }
}
