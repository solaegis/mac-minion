import SwiftUI

/// Every animation goes through here, so Reduce Motion applies everywhere.
enum Motion {
    /// Hover lift on tiles and cards.
    static let hover = Animation.snappy(duration: 0.15)
    /// Selection ring and small state flips.
    static let quick = Animation.easeOut(duration: 0.12)

    /// The hover scale, or none under Reduce Motion.
    static func hoverScale(_ hovering: Bool, reduceMotion: Bool) -> CGFloat {
        hovering && !reduceMotion ? 1.02 : 1
    }
}
