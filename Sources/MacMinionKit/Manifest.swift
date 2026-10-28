import Foundation

/// The `## Key: value` header of an ESO addon manifest (`<Folder>/<Folder>.txt`).
public struct Manifest: Sendable, Hashable {
    public var title: String?
    public var version: String?
    public var author: String?
    public var isLibrary = false
    public var dependsOn: [String] = []

    public init(title: String? = nil, version: String? = nil, author: String? = nil, isLibrary: Bool = false) {
        self.title = title; self.version = version; self.author = author; self.isLibrary = isLibrary
    }

    public static func parse(_ text: String) -> Manifest {
        var m = Manifest()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("##"), let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.index(line.startIndex, offsetBy: 2)..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = stripColors(String(line[line.index(after: colon)...])).trimmingCharacters(in: .whitespaces)
            switch key {
            case "title": m.title = value
            case "version": m.version = value
            case "author": m.author = value
            case "islibrary": m.isLibrary = value.lowercased() == "true"
            case "dependson": m.dependsOn = value.split(separator: " ").map { String($0.split(separator: ">")[0]) }
            default: break
            }
        }
        return m
    }

    /// Reads `<folder>/<name>.txt`, or `<name>.addon` for newer addons.
    public static func read(folder: URL) -> Manifest? {
        let name = folder.lastPathComponent
        for ext in ["txt", "addon"] {
            let file = folder.appending(path: "\(name).\(ext)")
            if let data = try? Data(contentsOf: file) {
                return parse(String(decoding: data, as: UTF8.self))
            }
        }
        return nil
    }

    /// ESO color codes: `|cFF0000text|r`.
    public static func stripColors(_ text: String) -> String {
        text.replacingOccurrences(of: #"\|c[0-9A-Fa-f]{6}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "|r", with: "")
    }
}
