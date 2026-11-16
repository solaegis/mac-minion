import Foundation
import Testing
@testable import MacMinionKit

private let file = "#Version 101051\n#AcknowledgedOutOfDateAddonsVersion 101051\n#AddOnsEnabled 1\n#Default\npChat 1\nMasterMerchant 0\n"
    + "#NA Megaserver-Masisi\nHarvestMap 1\nWritWorthy 1\n#EU Megaserver-Masisi\nHarvestMap 0\n#NA Megaserver-Spymaster Walsingham\nLibPrice 1\n"

private func parse(_ text: String) -> GameSettingsFile { GameSettingsFile.parse(Data(text.utf8), kind: .addOns) }
private func write(_ text: String, _ changes: [String: [String: Bool]]) -> String {
    String(decoding: parse(text).settingAddOns(changes), as: UTF8.self)
}

@Test func addOnChoicesReadEachBlockAndFallBackToDefault() {
    let choices = AddOnChoices(parse(file))
    #expect(AddOnChoices.header(server: "NA Megaserver", name: "Spymaster Walsingham") == "NA Megaserver-Spymaster Walsingham")
    #expect(choices.effective(for: "NA Megaserver-Masisi").choices == ["HarvestMap": true, "WritWorthy": true])
    #expect(choices.effective(for: "NA Megaserver-Masisi").fromDefault == false)
    // Same name on two megaservers stays apart.
    #expect(choices.effective(for: "EU Megaserver-Masisi").choices == ["HarvestMap": false])
    let nobody = choices.effective(for: "NA Megaserver-Nobody")
    #expect(nobody.fromDefault && nobody.choices == ["pChat": true, "MasterMerchant": false])
    let rows = choices.compare("NA Megaserver-Masisi", "EU Megaserver-Masisi")
    #expect(rows.map(\.addon) == ["HarvestMap", "WritWorthy"])
    #expect(rows.allSatisfy { $0.differs })
}

@Test func settingAddOnsKeepsTheFileWhenNothingChanges() {
    #expect(write(file, [:]) == file)
    #expect(write(file, ["NA Megaserver-Masisi": ["HarvestMap": true]]) == file)
}

@Test func settingAddOnsChangesALineInPlace() {
    let out = write(file, ["EU Megaserver-Masisi": ["HarvestMap": true]])
    #expect(out == file.replacingOccurrences(of: "#EU Megaserver-Masisi\nHarvestMap 0", with: "#EU Megaserver-Masisi\nHarvestMap 1"))
}

@Test func settingAddOnsAddsAMissingAddonToTheEndOfItsBlock() {
    let out = write(file, ["EU Megaserver-Masisi": ["WritWorthy": true]])
    #expect(out == file.replacingOccurrences(of: "#EU Megaserver-Masisi\nHarvestMap 0\n", with: "#EU Megaserver-Masisi\nHarvestMap 0\nWritWorthy 1\n"))
    // The last block, in a file with no final line break.
    let bare = String(file.dropLast())
    #expect(write(bare, ["NA Megaserver-Spymaster Walsingham": ["pChat": false]]) == file + "pChat 0\n")
}

@Test func settingAddOnsCreatesAMissingBlockFromDefault() {
    let out = write(file, ["NA Megaserver-Alpha Top": ["MasterMerchant": true, "HarvestMap": true]])
    #expect(out == file + "#NA Megaserver-Alpha Top\npChat 1\nMasterMerchant 1\nHarvestMap 1\n")
    #expect(AddOnChoices(parse(out)).effective(for: "NA Megaserver-Alpha Top").fromDefault == false)
}

@Test func settingAddOnsKeepsCRLFEndings() {
    let crlf = file.replacingOccurrences(of: "\n", with: "\r\n")
    let out = write(crlf, ["EU Megaserver-Masisi": ["HarvestMap": true, "pChat": false]])
    #expect(out == crlf.replacingOccurrences(of: "#EU Megaserver-Masisi\r\nHarvestMap 0\r\n",
                                             with: "#EU Megaserver-Masisi\r\nHarvestMap 1\r\npChat 0\r\n"))
}
