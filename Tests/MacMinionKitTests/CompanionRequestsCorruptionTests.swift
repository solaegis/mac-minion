import Foundation
import Testing
@testable import MacMinionKit

/// ESO-shaped companion fixture: four `$AccountWide` blocks (NA/EU × two accounts), each ending in
/// `errors` with escaped quotes, `\n`, and `<Locals>`, plus optional inline `lookups.requests`.
private enum CorruptionFixture {
    static let globals122 = (1...122).map { String(format: "Addon%03d_SV", $0) }
    static let globals123 = globals122 + ["Addon123_SV"]

    enum LookupsKind { case withRequests, lookupsNoRequests, noLookups }

    /// ~500-byte message with `\"`, newlines (as `\n` escapes), and `<Locals>`.
    static func errorMessage(trailingBackslash: Bool, utf8Extra: Bool) -> String {
        var body = #"user:/AddOns/X/a.lua:1: attempt to index a nil value: stack traceback: [C]: in function "error" "#
        body += #"<Locals> self = { ["name"] = "x", ["t"] = 1 } </Locals> "#
        while body.utf8.count < 480 { body += "pad " }
        body = String(decoding: Data(body.utf8.prefix(500)), as: UTF8.self)
        if trailingBackslash { body += "\\" }
        if utf8Extra { body += " café 日本語" }
        return body
    }

    static func file(
        lookups: LookupsKind = .withRequests,
        lineEnding: String = "\n",
        trailingBackslashInMessage: Bool = false,
        utf8Extra: Bool = false
    ) -> Data {
        let msg = errorMessage(trailingBackslash: trailingBackslashInMessage, utf8Extra: utf8Extra)
        let block = lookupsBlock(lookups, globals122)
        var text = """
EsoMacMinion_Data =
{
    ["NA Megaserver"] =
    {
        ["@SOLAEGIS"] =
        {
\(accountWide(lookupsBlock: block, message: msg))
        },
        ["@vavasour"] =
        {
\(accountWide(lookupsBlock: block, message: msg))
        },
    },
    ["EU Megaserver"] =
    {
        ["@SOLAEGIS"] =
        {
\(accountWide(lookupsBlock: block, message: msg))
        },
        ["@vavasour"] =
        {
\(accountWide(lookupsBlock: block, message: msg))
        },
    },
}
"""
        if lineEnding == "\r\n" {
            text = text.replacingOccurrences(of: "\n", with: "\r\n")
        }
        return Data(text.utf8)
    }

    private static func lookupsBlock(_ kind: LookupsKind, _ globals: [String]) -> String {
        let sv = globals.enumerated().map { "[\($0.offset + 1)] = \"\($0.element)\"" }.joined(separator: ", ")
        switch kind {
        case .withRequests:
            return """
                            ["lookups"] = {
                                ["requests"] = { ["svGlobals"] = { \(sv), }, },
                                ["answers"] = {},
                            },
"""
        case .lookupsNoRequests:
            return """
                            ["lookups"] = {
                                ["answers"] = {},
                            },
"""
        case .noLookups:
            return ""
        }
    }

    private static func accountWide(lookupsBlock: String, message: String) -> String {
        """
                    ["$AccountWide"] =
                    {
                        ["schema"] = 1,
\(lookupsBlock)                        ["errors"] =
                        {
                            [1] =
                            {
                                ["addon"] = "WizardsWardrobe",
                                ["at"] = 1793288692,
                                ["count"] = 1,
                                ["message"] = \(quoteLua(message)),
                            },
                        },
                    },
"""
    }

    static func quoteLua(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }
}

@Test func applyLengthensSvGlobalsKeepsErrorsClosersIntact() throws {
    let input = CorruptionFixture.file(lookups: .withRequests)
    let before = SVDocument.parse(input)
    #expect(before.error == nil, "fixture must parse: \(before.error?.message ?? "")")
    let updated = try #require(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123, to: input))
    let after = SVDocument.parse(updated)
    #expect(after.error == nil, "parse error after apply: \(after.error?.message ?? "")")
    let root = try #require(after[CompanionData.variable]?.table)
    for server in ["NA Megaserver", "EU Megaserver"] {
        for account in ["@SOLAEGIS", "@vavasour"] {
            let wide = try #require(root[server]?.table?[account]?.table?["$AccountWide"]?.table)
            #expect(wide["errors"]?.table?[.integer(1)]?.table?["message"]?.string != nil)
            let list = wide["lookups"]?.table?["requests"]?.table?["svGlobals"]?.table?.entries.compactMap(\.value.string)
            #expect(list == CorruptionFixture.globals123)
        }
    }
    let text = String(decoding: updated, as: UTF8.self)
    #expect(!text.contains("\n[1] =\n") && !text.hasPrefix("[1] ="))
}

@Test func applyInsertPathsAndCRLFAndUTF8KeepClosers() throws {
    for kind in [CorruptionFixture.LookupsKind.lookupsNoRequests, .noLookups] {
        let updated = try #require(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123,
                                                          to: CorruptionFixture.file(lookups: kind)))
        #expect(SVDocument.parse(updated).error == nil)
    }
    let crlf = try #require(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123,
                                                    to: CorruptionFixture.file(lookups: .withRequests, lineEnding: "\r\n")))
    #expect(SVDocument.parse(crlf).error == nil)
    let utf8 = try #require(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123,
                                                    to: CorruptionFixture.file(lookups: .withRequests, utf8Extra: true)))
    #expect(SVDocument.parse(utf8).error == nil)
}

@Test func trailingBackslashInClippedMessageStillParsesOrRefusesWrite() throws {
    let input = CorruptionFixture.file(lookups: .withRequests, trailingBackslashInMessage: true)
    let doc = SVDocument.parse(input)
    if doc.error != nil {
        #expect(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123, to: input) == nil)
    } else {
        let updated = try #require(CompanionRequests.apply(svGlobals: CorruptionFixture.globals123, to: input))
        #expect(SVDocument.parse(updated).error == nil)
    }
}

/// Nov 2026 incident: damage was outside `lookups.requests` (errors closers lost). `apply` on the
/// described shape does not produce that; this test locks the “output must parse and keep errors” rule.
@Test func applyRefusesIfSplicesWouldBreakParse() {
    // Truncated file: apply must return nil, never partial splices.
    let broken = Data("EsoMacMinion_Data = { [\"NA Megaserver\"] = {".utf8)
    #expect(CompanionRequests.apply(svGlobals: ["X"], to: broken) == nil)
}
