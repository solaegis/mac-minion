import Foundation

/// A thumbs up or down on any addon. Down keeps it out of every suggestion and AI search; both
/// tell the AI what the player likes.
public enum Rating: String, Codable, Sendable, CaseIterable {
    case up, down
}

/// The player's taste, as the prompts state it.
public struct Taste: Sendable, Equatable {
    public var liked: [String]
    public var disliked: [String]

    public init(liked: [String] = [], disliked: [String] = []) {
        self.liked = liked
        self.disliked = disliked
    }

    /// Lines for a prompt, or empty when nothing is rated.
    public var promptLines: String {
        var lines: [String] = []
        if !liked.isEmpty { lines.append("The player gave a thumbs up to: \(liked.joined(separator: ", ")). Favor addons like these.") }
        if !disliked.isEmpty {
            lines.append("The player gave a thumbs down to: \(disliked.joined(separator: ", ")). Avoid addons like these.")
        }
        return lines.joined(separator: "\n")
    }
}
