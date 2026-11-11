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
