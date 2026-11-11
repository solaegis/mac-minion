import Foundation
import Testing
@testable import MacMinionKit

private func parse(_ text: String) -> SVDocument { SVDocument.parse(Data(text.utf8)) }

@Test func parsesTheSerializersLua() throws {
    let doc = parse("""
    PCHAT_OPTS =
    {
        ["NA Megaserver"] = 
        {
            ["@SOLAEGIS"] = 
            {
                ["8796093036412335"] = 
                {
                    ["version"] = 1,
                    ["$LastCharacterName"] = "Masisi",
                    ["scale"] = 0.8500000238,
                    ["offset"] = -12,
                    ["big"] = 1.5e+20,
                    ["enabled"] = true,
                    ["muted"] = false,
                    ["link"] = "|H1:item:96175:4:22:0|h|h",
                    ["quote"] = "say \\"hi\\"\\n\\tback\\\\slash \\065",
                    [1] = "first",
                    [2] = "second",
                },
            },
        },
    }
    Other = { 10, 20, name = "x", [true] = "yes", }; -- a comment
    """)
    #expect(doc.error == nil)
    #expect(doc.variables.map(\.key) == [.string("PCHAT_OPTS"), .string("Other")])
    let char = try #require(doc["PCHAT_OPTS"]?.table?.value(at: [.string("NA Megaserver"), .string("@SOLAEGIS"), .string("8796093036412335")])?.table)
    #expect(char.count == 11)
    #expect(char["$LastCharacterName"]?.string == "Masisi")
    if case .number(let n) = char["scale"] { #expect(abs(n - 0.85) < 0.0001) } else { Issue.record("scale") }
    if case .integer(-12) = char["offset"] {} else { Issue.record("offset") }
    if case .number(let n) = char["big"] { #expect(n == 1.5e20) } else { Issue.record("big") }
    if case .bool(false) = char["muted"] {} else { Issue.record("muted") }
    #expect(char["quote"]?.string == "say \"hi\"\n\tback\\slash A")
    #expect(char[.integer(2)]?.string == "second")
    let other = try #require(doc["Other"]?.table)
    #expect(other.entries.map(\.key) == [.integer(1), .integer(2), .string("name"), .bool(true)])
}

@Test func keepsByteSpansForSizes() throws {
    let text = "V =\n{\n    [\"a\"] = \"xyz\",\n    [\"b\"] = { [1] = 2 },\n}\n"
    let doc = parse(text)
    let table = try #require(doc["V"]?.table)
    let bytes = Array(text.utf8)
    func slice(_ r: Range<Int>) -> String { String(decoding: bytes[r], as: UTF8.self) }
    #expect(slice(table.entries[0].span) == "[\"a\"] = \"xyz\"")
    #expect(slice(table.entries[1].span) == "[\"b\"] = { [1] = 2 }")
    #expect(slice(table.span).hasPrefix("{") && slice(table.span).hasSuffix("}"))
    #expect(doc.variables[0].span.count == text.count - 1)
}

@Test func reportsWhereAFileBreaksAndKeepsWhatCameBefore() throws {
    // The game quit while writing: the file stops inside a string.
    let cut = parse("V =\n{\n    [\"ok\"] = 1,\n    [\"inner\"] = \n    {\n        [\"name\"] = \"Mas")
    let error = try #require(cut.error)
    #expect(error.endedEarly && error.line == 6)
    #expect(error.path == [.string("V"), .string("inner"), .string("name")])
    let partial = try #require(cut["V"]?.table)
    if case .integer(1) = partial["ok"] {} else { Issue.record("kept what came before") }
    #expect(partial["inner"]?.table != nil)

    // A stray character in the middle.
    let broken = parse("V =\n{\n    [\"a\"] = 1,\n    [\"b\"] = @,\n}\n")
    let e = try #require(broken.error)
    #expect(!e.endedEarly && e.line == 4 && e.column == 13)
    #expect(e.description.contains("line 4") && e.description.contains("V › b"))

    #expect(parse("").variables.isEmpty && parse("").error == nil)
}

/// A read-only check against a real folder, run by hand:
///   MM_REAL_SV=~/Documents/Elder\ Scrolls\ Online/live/SavedVariables swift test -c release --filter parsesARealFolder
@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_REAL_SV"] != nil))
func parsesARealFolder() throws {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MM_REAL_SV"]!)
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "lua" }
    var slowest = (name: "", seconds: 0.0), total = 0.0, entries = 0
    func count(_ v: LuaValue) -> Int { v.table.map { $0.entries.reduce($0.count) { $0 + count($1.value) } } ?? 0 }
    for url in files {
        let start = Date()
        let doc = try SVDocument.read(url)
        let seconds = Date().timeIntervalSince(start)
        total += seconds
        if seconds > slowest.seconds { slowest = (url.lastPathComponent, seconds) }
        #expect(doc.error == nil, "\(url.lastPathComponent): \(doc.error?.description ?? "")")
        entries += doc.variables.reduce(0) { $0 + 1 + count($1.value) }
        #expect(!doc.variables.isEmpty || doc.byteCount == 0, "\(url.lastPathComponent) has no variables")
    }
    print("REAL \(entries) entries; \(files.count) files in \(String(format: "%.2f", total)) s; slowest \(slowest.name) \(String(format: "%.2f", slowest.seconds)) s")
}
