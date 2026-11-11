import Foundation

/// Where the Inspector is in a SavedVariables file: the file's top-level rows, the table opened (`focus`,
/// a path from the variable down), and the rows that table shows. Opening and going up work like folders.
public struct SVTableCursor {
    /// The file's variables.
    public var roots: [SVNode] = [] { didSet { refresh() } }
    /// The table shown; empty shows the variables. A path that isn't in `roots` shows the variables.
    public var focus: [LuaKey] = [] { didSet { refresh() } }
    /// The rows of the table shown.
    public private(set) var rows: [SVNode] = []
    private var index: [SVNode.ID: SVNode] = [:]

    public init(roots: [SVNode] = [], focus: [LuaKey] = []) {
        self.roots = roots
        self.focus = focus
        refresh()
    }

    private mutating func refresh() {
        var shown = roots
        for key in focus {
            guard let next = shown.first(where: { $0.key == key })?.children else { shown = roots; break }
            shown = next
        }
        rows = shown
        index = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A row by its ID: one shown, or one opened under a row shown.
    public func node(_ id: SVNode.ID?) -> SVNode? {
        guard let id else { return nil }
        if let row = index[id] { return row }
        // A row opened under one on screen: start from the row on screen it sits under.
        let parts = id.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard let first = rows.first, parts.count > first.path.count,
              let top = index[parts.prefix(first.path.count).joined(separator: "\u{1F}")] else { return nil }
        func find(_ node: SVNode) -> SVNode? {
            if node.id == id { return node }
            guard id.hasPrefix(node.id + "\u{1F}") else { return nil }
            for child in node.children ?? [] { if let found = find(child) { return found } }
            return nil
        }
        return find(top)
    }

    /// Shows only `node`'s entries. False, and no change, when `node` isn't a table.
    @discardableResult
    public mutating func open(_ node: SVNode) -> Bool {
        guard node.children != nil else { return false }
        focus = node.path
        return true
    }

    /// Goes up to the table around the one shown. Returns the ID of the row that was open, to select it;
    /// nil, and no change, at the top.
    public mutating func enclosing() -> SVNode.ID? {
        guard let left = focus.last else { return nil }
        focus.removeLast()
        return SVNode.id(focus + [left])
    }
}

extension Array where Element == LuaKey {
    /// `PCHAT_OPTS["NA Megaserver"]["@SOLAEGIS"][1]`, ready to paste into Lua.
    public var luaPath: String {
        guard let first else { return "" }
        return first.description + dropFirst().map { key in
            switch key {
            case .string(let s): "[\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"]"
            default: "[\(key.description)]"
            }
        }.joined()
    }
}
