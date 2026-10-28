import Foundation

/// An older release from an addon's ESOUI page ("Archived Files").
public struct ArchivedVersion: Sendable, Hashable, Identifiable, Codable {
    public var id: Int { aid }
    /// ESOUI's archive id, used in the download link.
    public let aid: Int
    public let version: String
    public let size: String
    public let date: String

    public init(aid: Int, version: String, size: String = "", date: String = "") {
        self.aid = aid; self.version = version; self.size = size; self.date = date
    }
}

/// Reads the archived releases from an ESOUI addon page. ESOUI's API lists only the latest release,
/// so older ones come from the page's "Archived Files" table, newest first. They have no checksum.
public enum ESOUIArchive {
    public static func pageURL(_ id: Int) -> URL { URL(string: "https://www.esoui.com/downloads/info\(id).html")! }

    public static func downloadURL(id: Int, aid: Int) -> URL {
        URL(string: "https://www.esoui.com/downloads/getfile.php?id=\(id)&aid=\(aid)")!
    }

    public static func versions(for id: Int, session: URLSession = .shared) async throws -> [ArchivedVersion] {
        var request = URLRequest(url: pageURL(id), timeoutInterval: 30)
        request.setValue("MacMinion", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw FeedError.http(http.statusCode, pageURL(id)) }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Each archive row: a getfile link with `aid=`, then cells for version, size, uploader, date.
    public static func parse(_ html: String) -> [ArchivedVersion] {
        guard let start = html.range(of: "Archived Files") else { return [] }
        let table = html[start.upperBound...]
        let end = table.range(of: "</table>").map { table[..<$0.lowerBound] } ?? table
        var out: [ArchivedVersion] = []
        for row in end.components(separatedBy: "</tr>") {
            guard let aidMatch = row.firstMatch(of: /aid=(\d+)/), let aid = Int(aidMatch.1) else { continue }
            let cells = row.matches(of: /<div class="smallfont">(.*?)<\/div>/).map { cell in
                String(cell.1).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespaces)
            }
            guard cells.count >= 5, !cells[1].isEmpty else { continue }
            out.append(ArchivedVersion(aid: aid, version: cells[1], size: cells[2], date: cells[4]))
        }
        return out
    }
}
