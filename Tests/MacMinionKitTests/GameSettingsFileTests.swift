import Foundation
import Testing
@testable import MacMinionKit

private let user = "SET MouseSensitivityFirstPerson \"0.85000002\"\r\nSET InvertMouseY \"1\"\r\nSET BACKGROUND_FPS_LIMIT \"60\"\r\n"
    + "SET PlayerWaypointIconColor \"ffa4ecee\"\r\nSET LastRealm \"NA Megaserver\"\r\nSET ScreenshotFormat.2 \"PNG\"\r\n; a comment\r\n"
private let addOns = "#Version 101051\n#AcknowledgedOutOfDateAddonsVersion 101051\n#AddOnsEnabled 1\n#Default\npChat 1\nMasterMerchant 0\n"
    + "#NA Megaserver-Spymaster Walsingham\nLibPrice 1\n"

@Test func settingsFieldsGetAnEditorThatFitsTheirValue() {
    let file = GameSettingsFile.parse(Data(user.utf8), kind: .user)
    let types = Dictionary(uniqueKeysWithValues: file.fields.map { ($0.key, $0.type) })
    #expect(types["MouseSensitivityFirstPerson"] == .decimal)
    #expect(types["InvertMouseY"] == .toggle)
    #expect(types["BACKGROUND_FPS_LIMIT"] == .integer)
    #expect(types["PlayerWaypointIconColor"] == .color)
    #expect(types["ScreenshotFormat.2"] == .text)
    if case .choice(let options)? = types["LastRealm"] { #expect(options.map(\.value) == ["NA Megaserver", "EU Megaserver", "PTS"]) }
    else { Issue.record("LastRealm isn't a choice") }
    #expect(GameSettingsFile.type(key: "RESOLUTION", value: "5120x1440") == .size)
    #expect(file.fields.count == 6)
}

@Test func savingRewritesOnlyChangedLinesWithTheirOwnEndings() {
    let file = GameSettingsFile.parse(Data(user.utf8), kind: .user)
    let fps = file.fields.first { $0.key == "BACKGROUND_FPS_LIMIT" }!
    let out = String(decoding: file.applying([fps.id: "30"]), as: UTF8.self)
    #expect(out == user.replacingOccurrences(of: "BACKGROUND_FPS_LIMIT \"60\"", with: "BACKGROUND_FPS_LIMIT \"30\""))
    // Nothing changed: the bytes come back the same.
    #expect(file.applying([:]) == Data(user.utf8))
}

@Test func addOnSettingsReadsHeadersAndEachCharactersAddons() {
    let file = GameSettingsFile.parse(Data(addOns.utf8), kind: .addOns)
    #expect(file.fields.filter { $0.section == nil }.map(\.key) == ["Version", "AcknowledgedOutOfDateAddonsVersion", "AddOnsEnabled"])
    #expect(file.fields.filter { $0.section == "NA Megaserver-Spymaster Walsingham" }.map(\.key) == ["LibPrice"])
    if case .choice(let options)? = file.fields.first?.type { #expect(options.first { $0.value == "101051" }?.title.contains("12.1.0") == true) }
    else { Issue.record("Version isn't a choice") }
    let merchant = file.fields.first { $0.key == "MasterMerchant" }!, version = file.fields[0]
    let out = String(decoding: file.applying([merchant.id: "1", version.id: "101052"]), as: UTF8.self)
    #expect(out == addOns.replacingOccurrences(of: "MasterMerchant 0", with: "MasterMerchant 1")
        .replacingOccurrences(of: "#Version 101051", with: "#Version 101052"))
}
