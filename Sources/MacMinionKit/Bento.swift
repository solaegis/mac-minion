import Foundation

/// A bento card's size in grid cells.
public struct BentoSpan: Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public static let small = BentoSpan(1, 1)
    public static let wide = BentoSpan(2, 1)
    public static let tall = BentoSpan(1, 2)
    public static let large = BentoSpan(2, 2)
}

/// Places bento cards on a grid of columns, densely: each card takes the first
/// free spot that fits, scanning rows top to bottom, so small cards fill the
/// gaps next to big ones. Cards wider than the grid shrink to fit.
public enum BentoPacker {
    public struct Slot: Sendable, Hashable {
        public let column: Int
        public let row: Int
        public let span: BentoSpan
    }

    public static func place(_ spans: [BentoSpan], columns: Int) -> (slots: [Slot], rows: Int) {
        let columns = max(1, columns)
        var taken: [[Bool]] = []
        var slots: [Slot] = []
        func free(_ c: Int, _ r: Int, _ s: BentoSpan) -> Bool {
            for row in r..<(r + s.height) {
                guard row < taken.count else { continue }
                for col in c..<(c + s.width) where taken[row][col] { return false }
            }
            return true
        }
        for requested in spans {
            let span = BentoSpan(min(requested.width, columns), requested.height)
            var row = 0
            search: while true {
                for col in 0...(columns - span.width) where free(col, row, span) {
                    while taken.count < row + span.height { taken.append(Array(repeating: false, count: columns)) }
                    for r in row..<(row + span.height) { for c in col..<(col + span.width) { taken[r][c] = true } }
                    slots.append(Slot(column: col, row: row, span: span))
                    break search
                }
                row += 1
            }
        }
        return (slots, taken.count)
    }
}
