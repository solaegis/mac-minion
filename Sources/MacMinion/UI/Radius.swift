import CoreGraphics

/// Corner radii. Inner corners are concentric: inner radius = outer radius - inset.
enum Radius {
    /// Chart bars.
    static let bar: CGFloat = 2
    /// Grid cells and color swatches.
    static let cell: CGFloat = 4
    /// Value cells in Compare, inside a tile.
    static let small: CGFloat = 6
    /// Thumbnails, icon wells, chips.
    static let chip: CGFloat = 8
    /// Stat tiles, the AI card, small bento cards.
    static let tile: CGFloat = 12
    /// Overview cards and bento cards.
    static let card: CGFloat = 16
    /// The Overview banner.
    static let hero: CGFloat = 20
}
