import Foundation
import Testing
@testable import MacMinionKit

@Test func placesCharactersFromAMegaserverNamespaceAndFromIIfAsShortCodes() {
    let text = """
    EsoVendorJunkSettings = { ["Default"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = {
        ["EU Megaserver"] = { ["perCharacterData"] = { ["8798292071266932"] = { ["_initialized"] = true } } },
        ["NA Megaserver"] = { ["perCharacterData"] = { ["8796093036412335"] = { ["_initialized"] = true } } },
    } } } }
    IIFA_DATABASE = { ["@vavasour"] = { ["servers"] = { ["NA"] = { ["CharIdToName"] = { ["8796093080202515"] = "Alpha Top" } } } } }
    """
    let homes = SettingsMatrix.homes(in: SVDocument.parse(Data(text.utf8)))
    #expect(homes["8798292071266932"] == SettingsMatrix.Home(account: "@SOLAEGIS", server: "EU Megaserver"))
    #expect(homes["8796093036412335"] == SettingsMatrix.Home(account: "@SOLAEGIS", server: "NA Megaserver"))
    #expect(homes["8796093080202515"] == SettingsMatrix.Home(account: "@vavasour", server: "NA Megaserver"))
}

@Test func aRealMegaserverWinsOverTheDefaultProfile() {
    let text = """
    A = { ["Default"] = { ["@SOLAEGIS"] = { ["8798292071266932"] = { ["x"] = 1 } } } }
    B = { ["Default"] = { ["@SOLAEGIS"] = { ["$AccountWide"] = { ["EU Megaserver"] = { ["8798292071266932"] = { ["y"] = 1 } } } } } }
    """
    #expect(SettingsMatrix.homes(in: SVDocument.parse(Data(text.utf8)))["8798292071266932"]?.server == "EU Megaserver")
}

/// A name-keyed table on EU isn't the NA character of that name, even when theirs is the only ID known.
@Test func aNameOnOneMegaserverIsNotTheSameNameOnTheOther() {
    let docs = ["A.lua": SVDocument.parse(Data("""
    A = { ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["8796093036412335"] = { ["$LastCharacterName"] = "Masisi", ["x"] = 1 } } } }
    B = { ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["Masisi"] = { ["y"] = 2 } } },
          ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["Masisi"] = { ["z"] = 3 } } } }
    """.utf8))]
    let matrix = SettingsMatrix.build(documents: docs, names: SVNameIndex.build(documents: docs, addons: nil))
    let na = matrix.addons.first?.characters["8796093036412335"] ?? [:]
    #expect(na.keys.contains("Z"), "the NA name table is NA Masisi's")
    #expect(!na.keys.contains("Y"), "the EU name table is someone else's")
}

/// Storage of a character known only by name is kept per account and megaserver.
@Test func usageKeepsSameNamedCharactersApart() {
    let docs = ["A.lua": SVDocument.parse(Data("""
    A = { ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["Masisi^Mf"] = { ["x"] = 1 } } },
          ["EU Megaserver"] = { ["@SOLAEGIS"] = { ["Masisi^Mf"] = { ["x"] = 1 } } } }
    """.utf8))]
    let usage = SVUsage.build(documents: docs, names: SVNameIndex())
    let masisis = usage.characters.filter { $0.title == "Masisi" }
    #expect(masisis.count == 2)
    #expect(Set(masisis.compactMap(\.detail)) == ["@SOLAEGIS · NA", "@SOLAEGIS · EU"])
    #expect(masisis.allSatisfy { $0.servers.count == 1 })
}
