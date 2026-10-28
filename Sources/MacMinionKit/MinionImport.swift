import Foundation

/// Reads the install records of the Java Minion (`~/.minion/minion.xml`), read-only.
///   <game game-id="ESO" addon-path="<base64 path>"> <addons> <addon uid md5 ui-version> <dirs><dir>…
public enum MinionImport {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".minion/minion.xml")
    }

    public struct Game: Sendable {
        public var addonPath: String?
        public var records: [Int: InstallRecord]
    }

    public static func read(_ url: URL = defaultURL) -> Game? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.game
    }

    public static func parse(_ data: Data) -> Game? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.game
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var game: Game?
        private var inESO = false
        private var inAddons = false
        private var current: InstallRecord?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            text = ""
            switch name {
            case "game" where a["game-id"] == "ESO":
                inESO = true
                let path = a["addon-path"].flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) }
                if game == nil { game = Game(addonPath: path, records: [:]) }
            case "addons" where inESO:
                inAddons = true
            case "addon" where inAddons:
                if let uid = a["uid"].flatMap(Int.init) {
                    current = InstallRecord(id: uid, version: a["ui-version"], md5: a["md5"], dirs: [])
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "dir": current?.dirs.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "addon":
                if let r = current, !r.dirs.isEmpty { game?.records[r.id] = r }
                current = nil
            case "addons": inAddons = false
            case "game": inESO = false
            default: break
            }
        }
    }
}
