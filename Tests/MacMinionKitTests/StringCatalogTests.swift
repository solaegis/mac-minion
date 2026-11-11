import Foundation
import Testing

// The string catalogs are kept by hand. SwiftUI looks a string up by its format key ("%lld downloads",
// "Install %@"), so a key spelled any other way, or a translation with other placeholders, shows English.

private let catalogs = ["Sources/MacMinion/Resources/Localizable.xcstrings", "Sources/MacMinionKit/Resources/Localizable.xcstrings"]

private func repoFile(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: path)
}

/// Every format specifier in a string, as its type, ignoring position ("%2$lld" -> "lld").
private func specifiers(_ text: String) -> [String] {
    text.matches(of: /%(?:\d+\$)?(lld|ld|d|lf|f|@)/).map { String($0.output.1) }.sorted()
}

/// Every translated value of one catalog entry: plain ones and each plural form.
private func values(_ entry: [String: Any]) -> [(language: String, value: String)] {
    let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
    return localizations.flatMap { language, localization -> [(String, String)] in
        var units: [[String: Any]] = []
        if let unit = localization["stringUnit"] as? [String: Any] { units.append(unit) }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        units += plural.values.compactMap { $0["stringUnit"] as? [String: Any] }
        return units.compactMap { $0["value"] as? String }.map { (language, $0) }
    }
}

@Test(arguments: catalogs)
func catalogKeysUseRuntimeFormatSpecifiers(_ path: String) throws {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: repoFile(path))) as? [String: Any]
    let strings = try #require(json?["strings"] as? [String: [String: Any]])
    #expect(strings.keys.filter { $0.contains("%arg") }.sorted() == [], "write %lld for Int and %@ for String, not %arg")
    for (key, entry) in strings {
        for (language, value) in values(entry) {
            #expect(specifiers(value) == specifiers(key), "\(language) for \"\(key)\": \"\(value)\"")
        }
    }
}
