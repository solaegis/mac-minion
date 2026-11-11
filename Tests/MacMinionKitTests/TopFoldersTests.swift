import Foundation
import Testing
@testable import MacMinionKit

@Test func groupsDataAddonsWithTheFolderTheyShipIn() throws {
    let fm = FileManager.default
    let addons = fm.temporaryDirectory.appending(path: "mm-top-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: addons) }
    for path in ["LibGuildStore/LibGuildStore.txt", "LibGuildStore/GS16Data/GS16Data.txt", "pChat/pChat.addon", "Loose/readme.txt"] {
        try fm.createDirectory(at: addons.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: addons.appending(path: path), atomically: true, encoding: .utf8)
    }
    #expect(SavedVariablesAudit.topFolders(addons) == ["libguildstore": "LibGuildStore", "gs16data": "LibGuildStore", "pchat": "pChat"])
}
