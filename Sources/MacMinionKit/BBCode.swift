import Foundation

/// ESOUI descriptions and changelogs are BBCode. Shown as plain text.
public enum BBCode {
    public static func plainText(_ source: String) -> String {
        var s = source.replacingOccurrences(of: "\r\n", with: "\n")
        // [url=https://x]label[/url] -> label (https://x)
        s = s.replacingOccurrences(of: #"\[url=\"?([^\]\"]+)\"?\](.*?)\[/url\]"#, with: "$2 ($1)",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\[\*\]"#, with: "\n• ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[/?[a-zA-Z]+(=[^\]]*)?\]"#, with: "", options: .regularExpression)
        // One line per list item, with no blank line before it.
        s = s.replacingOccurrences(of: #"\n\s*\n• "#, with: "\n• ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
