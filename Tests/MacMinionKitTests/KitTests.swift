import Foundation
import Testing
@testable import MacMinionKit

@Test func decodesCatalogEntry() throws {
    let json = """
    [{"UID":"7","UICATID":"53","UIVersion":"2.0 r43","UIDate":1778599485000,"UIName":"LibAddonMenu-2.0",
      "UIAuthorName":"sirinsidiator","UIDownloadTotal":"6330822","UIDownloadMonthly":"25382","UIFavoriteTotal":"3101",
      "UICompatibility":[{"version":"12.0.0","name":"Season Zero Pt.2"}],"UIDir":["LibAddonMenu-2.0"],
      "UIIMG_Thumbs":["https://cdn-eso.mmoui.com/preview/tiny/pvw3588.jpg"],"UIIMGs":null,"UISiblings":null}]
    """
    let addons = try MMOUIClient.decodeCatalog(Data(json.utf8))
    #expect(addons.count == 1)
    let a = try #require(addons.first)
    #expect(a.id == 7 && a.categoryID == 53 && a.downloads == 6_330_822)
    #expect(a.dirs == ["LibAddonMenu-2.0"])
    #expect(a.images.isEmpty && a.thumbnails.count == 1)
    #expect(Int(a.date.timeIntervalSince1970) == 1_778_599_485)
}

@Test func parsesManifest() {
    let m = Manifest.parse("""
    ## Title: |cFF0000HarvestMap|r
    ## Author: Shinni
    ## Version: 3.16.5
    ## IsLibrary: true
    ## DependsOn: LibAddonMenu-2.0>=30 LibMapPins-1.0
    Main/HarvestMap.lua
    """)
    #expect(m.title == "HarvestMap")
    #expect(m.version == "3.16.5")
    #expect(m.isLibrary)
    #expect(m.dependsOn == ["LibAddonMenu-2.0", "LibMapPins-1.0"])
}

@Test func plainTextFromBBCode() {
    let s = BBCode.plainText("[B]Hi[/B]\r\n[LIST][*]one[*]two[/LIST] [URL=\"https://x.y\"]site[/URL]")
    #expect(s == "Hi\n• one\n• two site (https://x.y)")
}

@Test("Versions compare loosely", arguments: [("2.0 r43", "2.0r43", true), ("v1.2", "1.2", true), ("1.2", "1.3", false)])
func versions(_ a: String, _ b: String, _ same: Bool) {
    #expect(VersionText.same(a, b) == same)
}

private func addon(_ id: Int, _ dirs: [String], version: String = "1", downloads: Int = 0) -> CatalogAddon {
    CatalogAddon(id: id, categoryID: 1, version: version, date: .now, name: "A\(id)", author: "x", downloads: downloads, dirs: dirs)
}

@Test func matchesFoldersToCatalog() {
    let catalog = [addon(1, ["Alpha"]), addon(2, ["Beta", "BetaData"]), addon(3, ["Beta"], downloads: 9_999), addon(4, ["Gamma"], version: "2")]
    let folders: [String: Manifest?] = ["Alpha": nil, "Beta": nil, "BetaData": nil, "Gamma": nil, "MyOwn": Manifest(title: "Mine")]
    let records = [4: InstallRecord(id: 4, version: "1", dirs: ["Gamma"])]
    let r = AddonMatcher.match(folders: folders, catalog: catalog, records: records)
    #expect(Set(r.installed.map(\.id)) == [1, 2, 4], "the entry covering more folders wins over the popular one")
    #expect(r.unmatched.map(\.title) == ["Mine"])
    #expect(r.installed.first { $0.id == 4 }?.status == .updateAvailable)
    #expect(r.installed.first { $0.id == 1 }?.status == .versionUnknown)
}

@Test func manifestVersionCountsAsUpToDate() {
    let r = AddonMatcher.match(folders: ["Alpha": Manifest(version: "1")], catalog: [addon(1, ["Alpha"])], records: [:])
    #expect(r.installed.first?.status == .upToDate)
}

@Test func ignoredIsNotAnUpdate() {
    let records = [1: InstallRecord(id: 1, version: "0", dirs: ["Alpha"], ignored: true)]
    let r = AddonMatcher.match(folders: ["Alpha": nil], catalog: [addon(1, ["Alpha"])], records: records)
    #expect(r.installed.first?.status == .ignored)
}

@Test func importsMinionXML() throws {
    let path = Data("/Users/me/AddOns".utf8).base64EncodedString()
    let xml = """
    <minion><games><game game-id="ESO" addon-path="\(path)">
      <auto-updated><addon date="x" title="T" version="1"/></auto-updated>
      <addons><addon md5="abc" ui-version="1.32" uid="2079"><dirs><dir>LibFeedback</dir></dirs></addon></addons>
    </game></games></minion>
    """
    let game = try #require(MinionImport.parse(Data(xml.utf8)))
    #expect(game.addonPath == "/Users/me/AddOns")
    #expect(game.records[2079] == InstallRecord(id: 2079, version: "1.32", md5: "abc", dirs: ["LibFeedback"]))
    #expect(game.records.count == 1)
}

@Test func categoryDescendants() {
    let all = [AddonCategory(id: 23, title: "UI", parentIDs: [0]), AddonCategory(id: 17, title: "Graphic", parentIDs: [0, 23]),
               AddonCategory(id: 5, title: "Other", parentIDs: [0])]
    #expect(AddonCategory.descendants(of: 23, in: all) == [23, 17])
}

@Test func installSwapsFoldersAndRollsBack() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "mm-test-\(UUID().uuidString)")
    let addons = root.appending(path: "AddOns")
    let src = root.appending(path: "src/Alpha")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try "## Version: 2".write(to: src.appending(path: "Alpha.txt"), atomically: true, encoding: .utf8)
    try fm.createDirectory(at: addons.appending(path: "Alpha"), withIntermediateDirectories: true)
    try "## Version: 1".write(to: addons.appending(path: "Alpha/Alpha.txt"), atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: root) }

    let zip = root.appending(path: "a.zip")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--keepParent", src.path, zip.path]
    try p.run(); p.waitUntilExit()
    let md5 = Installer.md5(try Data(contentsOf: zip))

    let installer = Installer(addons: addons)
    await #expect(throws: InstallError.checksum) {
        _ = try await installer.install(AddonDetails(id: 1, version: "2", md5: "bad", fileName: "a.zip", downloadURL: zip))
    }
    #expect(Manifest.read(folder: addons.appending(path: "Alpha"))?.version == "1", "a bad checksum leaves the old folder")

    let record = try await installer.install(AddonDetails(id: 1, version: "2", md5: md5, fileName: "a.zip", downloadURL: zip))
    #expect(record.dirs == ["Alpha"] && record.version == "2")
    #expect(Manifest.read(folder: addons.appending(path: "Alpha"))?.version == "2")
}
