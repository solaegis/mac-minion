import SwiftUI

/// Card surfaces. Neutral cards use the system's secondary background so they
/// pick up light and dark mode; accent cards use Palette.accentWash.
extension View {
    /// A neutral card: secondary background, hairline border, `radius` corners.
    func cardSurface(_ radius: CGFloat = Radius.card, selected: Bool = false) -> some View {
        background(.background.secondary, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.separator),
                                  lineWidth: selected ? 2 : 1)
            }
    }

    /// A card that belongs to the accent (the AI summary).
    func accentSurface(_ radius: CGFloat = Radius.tile) -> some View {
        background(Palette.accentWash, in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.accentEdge) }
    }
}
