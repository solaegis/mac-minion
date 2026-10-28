import Foundation
import MacMinionKit

/// Sample data for snapshots and the self-test: APP_SEED=1 (or --selftest) with
/// APP_STORE in /tmp builds an AddOns folder and a small catalog in the store,
/// with zips on disk so installs and updates run without the network.
@MainActor
enum SeedData {
    struct Sample {
        let id: Int, name: String, author: String, category: Int, version: String
        let dirs: [String], downloads: Int, daysAgo: Double
        /// Installed version, nil when not installed. "manifest" means found on disk only.
        var installed: String?
        var ignored = false
    }

    static let samples: [Sample] = [
        Sample(id: 7, name: "LibAddonMenu-2.0", author: "sirinsidiator", category: 53, version: "2.0 r43",
               dirs: ["LibAddonMenu-2.0"], downloads: 6_330_822, daysAgo: 3, installed: "2.0 r42"),
        Sample(id: 57, name: "HarvestMap", author: "Shinni", category: 17, version: "3.16.5",
               dirs: ["HarvestMap", "HarvestMapData"], downloads: 2_904_113, daysAgo: 12, installed: "3.16.5"),
        Sample(id: 1605, name: "WritWorthy", author: "ziggr", category: 18, version: "7.5.4",
               dirs: ["WritWorthy"], downloads: 1_120_448, daysAgo: 1, installed: "7.5.2"),
        Sample(id: 97, name: "Dustman", author: "Garkin, Ayantir", category: 18, version: "5.4.1",
               dirs: ["Dustman"], downloads: 986_200, daysAgo: 40, installed: "manifest"),
        Sample(id: 1146, name: "LibCustomMenu", author: "votan", category: 53, version: "7.3.1",
               dirs: ["LibCustomMenu"], downloads: 2_210_007, daysAgo: 8, installed: "7.3.0", ignored: true),
        Sample(id: 1360, name: "Master Merchant 3.0", author: "Sharlikran", category: 17, version: "3.8.21",
               dirs: ["MasterMerchant"], downloads: 3_402_116, daysAgo: 2),
        Sample(id: 695, name: "AwesomeGuildStore", author: "sirinsidiator", category: 17, version: "1.12.4",
               dirs: ["AwesomeGuildStore"], downloads: 4_118_930, daysAgo: 6),
        Sample(id: 1536, name: "Lazy Writ Crafter", author: "Dolgubon", category: 18, version: "4.2.1",
               dirs: ["DolgubonsLazyWritCreator"], downloads: 3_877_451, daysAgo: 20),
        Sample(id: 2163, name: "Inventory Insight", author: "manavortex, Baertram", category: 17, version: "3.93",
               dirs: ["IIfA"], downloads: 1_654_002, daysAgo: 90),
        Sample(id: 1245, name: "Bandits User Interface", author: "Hoft", category: 17, version: "4.12",
               dirs: ["BanditsUserInterface"], downloads: 1_998_113, daysAgo: 30),
    ]

    static let categories = [
        AddonCategory(id: 23, title: "Graphic & Plug-ins", parentIDs: [0]),
        AddonCategory(id: 17, title: "Graphic UI Mods", parentIDs: [0, 23]),
        AddonCategory(id: 18, title: "Character Advancement", parentIDs: [0, 23]),
        AddonCategory(id: 53, title: "Libraries", parentIDs: [0]),
    ]

    static var requested: Bool {
        ProcessInfo.processInfo.environment["APP_SEED"] == "1" || SelfTest.requested
    }

    static func insertIfRequested(into model: AppModel) async {
        guard requested else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a folder in /tmp")
            return
        }
        let fm = FileManager.default
        let addons = model.addonsFolder
        let zips = Store.directory.appending(path: "zips", directoryHint: .isDirectory)
        try? fm.createDirectory(at: addons, withIntermediateDirectories: true)
        try? fm.createDirectory(at: zips, withIntermediateDirectories: true)

        var records: [Int: InstallRecord] = [:]
        var details: [Int: AddonDetails] = [:]
        for s in samples {
            if let v = s.installed {
                let shown = v == "manifest" ? s.version : v
                for dir in s.dirs { writeAddon(dir, version: shown, author: s.author, in: addons) }
                if v != "manifest" { records[s.id] = InstallRecord(id: s.id, version: v, dirs: s.dirs, ignored: s.ignored) }
            }
            if let zip = makeZip(s, in: zips) {
                details[s.id] = AddonDetails(
                    id: s.id, version: s.version, md5: Installer.md5((try? Data(contentsOf: zip)) ?? Data()),
                    fileName: zip.lastPathComponent, downloadURL: zip,
                    description: "[B]\(s.name)[/B] by \(s.author).\r\n\r\nSample text for snapshots.\r\n[LIST][*]Works offline[*]Installs from a local zip[/LIST]",
                    changelog: "\(s.version)\r\n- updated for Season One\r\n- fixed a rare error on login")
            }
        }
        // A folder no catalog entry lists, like an addon you build yourself.
        writeAddon("EsoVendorJunk", version: "1.4.0", author: "solaegis", in: addons)

        let catalog = samples.map { s in
            CatalogAddon(id: s.id, categoryID: s.category, version: s.version,
                         date: .now.addingTimeInterval(-s.daysAgo * 86_400), name: s.name, author: s.author,
                         infoURL: URL(string: "https://www.esoui.com/downloads/info\(s.id).html"),
                         downloads: s.downloads, downloadsMonthly: s.downloads / 120, favorites: s.downloads / 1_500,
                         compatibility: [GameVersion(version: "12.1.0", name: "Season One")], dirs: s.dirs)
        }
        await model.load(catalog: catalog, categories: categories, details: details, records: records, history: sampleHistory)
    }

    /// Half a year of updates: libraries and busy addons often, others now and then. The older half came from Minion.
    static var sampleHistory: [HistoryEvent] {
        let cadence: [(String, Int, Double)] = [  // name, id, days between updates
            ("LibAddonMenu-2.0", 7, 21), ("HarvestMap", 57, 9), ("WritWorthy", 1605, 6),
            ("Dustman", 97, 45), ("LibCustomMenu", 1146, 30),
        ]
        var events: [HistoryEvent] = []
        for (offset, (name, id, every)) in cadence.enumerated() {
            var day = Double(offset) * 2 + 1
            var minor = 40
            while day < 180 {
                events.append(HistoryEvent(date: .now.addingTimeInterval(-day * 86_400), addonID: id, name: name,
                                           version: "1.\(minor + 1)", previousVersion: "1.\(minor)",
                                           kind: .update, fromMinion: day > 60))
                minor -= 1
                day += every
            }
        }
        events.append(HistoryEvent(date: .now.addingTimeInterval(-3 * 3_600), addonID: 1360, name: "Master Merchant 3.0",
                                   version: "3.8.21", kind: .install))
        events.append(HistoryEvent(date: .now.addingTimeInterval(-26 * 3_600), addonID: 1360, name: "Master Merchant 3.0",
                                   version: "3.8.20", kind: .remove))
        return events
    }

    private static func writeAddon(_ dir: String, version: String, author: String, in addons: URL) {
        let folder = addons.appending(path: dir, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = "## Title: \(dir)\n## Author: \(author)\n## Version: \(version)\n## APIVersion: 101048\n\n\(dir).lua\n"
        try? text.write(to: folder.appending(path: "\(dir).txt"), atomically: true, encoding: .utf8)
    }

    private static func makeZip(_ s: Sample, in zips: URL) -> URL? {
        let staging = zips.appending(path: "src-\(s.id)", directoryHint: .isDirectory)
        for dir in s.dirs { writeAddon(dir, version: s.version, author: s.author, in: staging) }
        let zip = zips.appending(path: "\(s.id).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", staging.path, zip.path]
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? zip : nil
    }
}
