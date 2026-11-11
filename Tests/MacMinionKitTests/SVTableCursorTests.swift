import Foundation
import Testing
@testable import MacMinionKit

private let doc = SVDocument.parse(Data("""
W = { ["NA Megaserver"] = { ["@ME"] = { ["8796093036412335"] = { ["budget"] = 50, ["color"] = { ["r"] = 1 } } } } }
A = 1
""".utf8))
private let me: [LuaKey] = [.string("W"), .string("NA Megaserver"), .string("@ME")]
private let masisi = me + [.string("8796093036412335")]

@Test func theCursorShowsTheVariablesThenTheTableOpened() throws {
    var cursor = SVTableCursor(roots: SVNode.roots(doc))
    #expect(cursor.rows.map(\.key) == [.string("A"), .string("W")])
    cursor.focus = masisi
    #expect(cursor.rows.map(\.key) == [.string("budget"), .string("color")])
    cursor.focus = me + [.string("nobody")]
    #expect(cursor.rows.map(\.key) == [.string("A"), .string("W")], "a path that isn't there shows the variables")
    cursor.focus = masisi
    cursor.roots = SVNode.roots(doc)
    #expect(cursor.rows.count == 2, "new roots keep the table open")
}

@Test func openAndEnclosingWorkLikeFolders() throws {
    var cursor = SVTableCursor(roots: SVNode.roots(doc), focus: masisi)
    let budget = try #require(cursor.rows.first)
    let openedValue = cursor.open(budget)
    #expect(!openedValue, "a value isn't a table")
    #expect(cursor.focus == masisi)
    let color = try #require(cursor.rows.last)
    let openedTable = cursor.open(color)
    #expect(openedTable)
    #expect(cursor.focus == masisi + [.string("color")] && cursor.rows.map(\.key) == [.string("r")])
    let selected = cursor.enclosing()
    #expect(selected == color.id, "going up selects the table that was open")
    #expect(cursor.focus == masisi)
    cursor.focus = []
    let atTop = cursor.enclosing()
    #expect(atTop == nil)
}

@Test func findsARowShownOrOpenedUnderOne() throws {
    let cursor = SVTableCursor(roots: SVNode.roots(doc), focus: me)
    let shown = try #require(cursor.rows.first)
    #expect(cursor.node(shown.id) === shown)
    let deep = SVNode.id(masisi + [.string("color"), .string("r")])
    #expect(cursor.node(deep)?.path == masisi + [.string("color"), .string("r")])
    #expect(cursor.node(SVNode.id([.string("A")])) == nil, "rows above the table shown aren't found")
    #expect(cursor.node(nil) == nil)
}

@Test func luaPathsQuoteStringsAndEscape() {
    #expect([LuaKey]().luaPath == "")
    #expect(([.string("P"), .string("NA \"Mega\\server\""), .integer(1)] as [LuaKey]).luaPath == #"P["NA \"Mega\\server\""][1]"#)
}
