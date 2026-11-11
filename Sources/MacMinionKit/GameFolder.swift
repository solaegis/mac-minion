import Foundation

/// The game folder around AddOns (`.../live`): what each item is, how big, and the copies people keep there.
/// See docs/research/LIVE-FOLDER.md.
public struct GameFolderItem: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case savedVariables, addOnSettings, userSettings, machineSettings, shaderCache, pipelineCache,
             cachedData, titleStorage, guildHistory, logs, errors, screenshots

        /// The file or folder name in the game folder.
        public var fileName: String {
            switch self {
            case .savedVariables: "SavedVariables"
            case .addOnSettings: "AddOnSettings.txt"
            case .userSettings: "UserSettings.txt"
            case .machineSettings: "MachineSettings.txt"
            case .shaderCache: "ShaderCache.cooked"
            case .pipelineCache: "PipelineCache.esopc"
            case .cachedData: "CachedData"
            case .titleStorage: "TitleStorage"
            case .guildHistory: "GuildHistory"
            case .logs: "Logs"
            case .errors: "Errors"
            case .screenshots: "Screenshots"
            }
        }

        public var purpose: String {
            switch self {
            case .savedVariables: String(localized: "Your addons' settings and data, plus some of the game's own", bundle: .module)
            case .addOnSettings: String(localized: "Which addons are on for each character", bundle: .module)
            case .userSettings: String(localized: "Video, audio, and interface settings", bundle: .module)
            case .machineSettings: String(localized: "A few renderer settings for this Mac", bundle: .module)
            case .shaderCache: String(localized: "Compiled shaders; rebuilt on the next login", bundle: .module)
            case .pipelineCache: String(localized: "Compiled graphics pipelines; rebuilt on the next login", bundle: .module)
            case .cachedData: String(localized: "The game's own cache", bundle: .module)
            case .titleStorage: String(localized: "The game's own storage", bundle: .module)
            case .guildHistory: String(localized: "Guild history the game and addons read", bundle: .module)
            case .logs: String(localized: "The game's and the interface's logs", bundle: .module)
            case .errors: String(localized: "Crash reports for ZeniMax", bundle: .module)
            case .screenshots: String(localized: "Your screenshots", bundle: .module)
            }
        }
    }

    /// The name in the game folder, also the id.
    public let name: String
    /// nil for a copy or folder the game doesn't make.
    public let kind: Kind?
    public let url: URL
    public let isFolder: Bool
    public let bytes: Int64
    public let modified: Date?
    public var id: String { name }

    public init(name: String, kind: Kind?, url: URL, isFolder: Bool, bytes: Int64, modified: Date?) {
        self.name = name; self.kind = kind; self.url = url; self.isFolder = isFolder; self.bytes = bytes; self.modified = modified
    }
}

public struct GameFolderScan: Sendable, Equatable {
    /// The game's own items that exist, in the order of `Kind`.
    public let items: [GameFolderItem]
    /// Everything else beside AddOns: `*.bak*` copies and folders the game doesn't make.
    public let copies: [GameFolderItem]

    public static func scan(_ game: URL) -> GameFolderScan {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: game.path)) ?? []
        let byName = Dictionary(uniqueKeysWithValues: GameFolderItem.Kind.allCases.map { ($0.fileName.lowercased(), $0) })
        var items: [GameFolderItem] = [], copies: [GameFolderItem] = []
        for name in names where !name.hasPrefix(".") && name != "AddOns" {
            let url = game.appending(path: name)
            let item = GameFolderItem(name: name, kind: byName[name.lowercased()], url: url, isFolder: url.isFolder,
                                      bytes: url.isFolder ? Usage.size(of: url) : url.fileSize, modified: url.modified)
            if item.kind != nil { items.append(item) } else { copies.append(item) }
        }
        return GameFolderScan(items: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                              copies: copies.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}

/// One file in SavedVariables and who it belongs to.
public struct SavedVariablesFile: Sendable, Identifiable, Equatable {
    public enum Owner: Sendable, Equatable {
        /// An installed addon of this name declares `## SavedVariables:`.
        case addon(String)
        /// `ZO_*.lua`: the game's own interface settings. Never cleaned up.
        case game
        /// A `.lua` file no installed addon saves to.
        case none
        /// A copy someone made, like `pChat.lua.bak-20261024` or `HarvestMap.lua~`, or a folder.
        case copy
        /// Anything else, like the README of a git repository kept here. Left alone.
        case other
    }

    public let name: String
    public let url: URL
    public let bytes: Int64
    public let modified: Date?
    public let owner: Owner
    public var id: String { name }

    /// Files a clean-up offers to move to the Trash.
    public var isTidyable: Bool { owner == .none || owner == .copy }

    public init(name: String, url: URL, bytes: Int64, modified: Date?, owner: Owner) {
        self.name = name; self.url = url; self.bytes = bytes; self.modified = modified; self.owner = owner
    }
}

public enum SavedVariablesAudit {
    /// Every file in `<game>/SavedVariables`, largest first, with its owner among the addons in `addons`.
    public static func run(game: URL, addons: URL) -> [SavedVariablesFile] {
        let folder = game.appending(path: "SavedVariables", directoryHint: .isDirectory)
        let decls = declarations(addons)
        var owners: [String: String] = [:]
        for (key, value) in decls {
            owners[key] = value.addon
            for variable in value.variables { owners[variable.lowercased()] = value.addon }
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { name in
            let url = folder.appending(path: name)
            let owner: SavedVariablesFile.Owner
            if url.isFolder || (name.lowercased().contains(".lua") && !name.lowercased().hasSuffix(".lua")) {
                owner = .copy
            } else if !name.lowercased().hasSuffix(".lua") {
                owner = .other
            } else {
                let base = String(name.dropLast(4))
                if base.hasPrefix("ZO_") { owner = .game }
                else if let addon = owners[base.lowercased()] { owner = .addon(addon) }
                else if isCopyName(base) { owner = .copy }
                else { owner = .none }
            }
            return SavedVariablesFile(name: name, url: url, bytes: url.isFolder ? Usage.size(of: url) : url.fileSize,
                                      modified: url.modified, owner: owner)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `pChat copy`, `pChat (2)`, `pChat-backup`, `pChat.bak`, `pChat_old`, `pChat 2026-10-24`: names people give copies.
    public static func isCopyName(_ base: String) -> Bool {
        let pattern = #"(?i)([ _.-]+(copy|backup|bak|old|orig)( ?\d+)?|[ _-]*\(\d+\)|[ _.-]+\d{4}-?\d{2}-?\d{2}([ _T-]?\d{2,6})?)$"#
        guard let range = base.range(of: pattern, options: .regularExpression) else { return false }
        return range.lowerBound > base.startIndex
    }

    /// Addons up to three folders deep, as the game loads them, whose manifest has `## SavedVariables:`,
    /// keyed by lowercased name.
    public static func savers(_ addons: URL, depth: Int = 3) -> [String: String] {
        declarations(addons, depth: depth).mapValues(\.addon)
    }

    /// What the Game Folder's read needs from AddOns, from one walk of it.
    public struct AddonIndex: Sendable {
        /// Each installed addon that saves, by lowercased folder name: its folder, its name, and the
        /// variables its manifest declares.
        public var savers: [String: (url: URL, addon: String, variables: [String])] = [:]
        /// Each addon's lowercased folder name -> the AddOns folder it ships in (S-048).
        public var topFolders: [String: String] = [:]
        /// Every addon with a manifest, by lowercased folder name: its name, the variables it declares, and
        /// its `## DependsOn:` folders, as `SVGraph.Input.addons` takes them.
        public var manifests: [String: (addon: String, variables: [String], dependsOn: [String])] = [:]
    }

    /// Addons up to three folders deep, as the game loads them: one walk for everything the read uses.
    public static func index(_ addons: URL, depth: Int = 3) -> AddonIndex {
        let fm = FileManager.default
        var index = AddonIndex()
        func walk(_ dir: URL, _ level: Int, _ top: String?) {
            guard level <= depth, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in names where !name.hasPrefix(".") {
                let url = dir.appending(path: name, directoryHint: .isDirectory)
                guard url.isFolder else { continue }
                let owner = top ?? name
                if let manifest = Manifest.read(folder: url) {
                    index.topFolders[name.lowercased()] = owner
                    index.manifests[name.lowercased()] = (name, manifest.savedVariables, manifest.dependsOn)
                    if !manifest.savedVariables.isEmpty { index.savers[name.lowercased()] = (url, name, manifest.savedVariables) }
                }
                walk(url, level + 1, owner)
            }
        }
        walk(addons, 1, nil)
        return index
    }

    /// The folder of each installed addon that saves, keyed by lowercased name: where its Lua source is.
    public static func saverFolders(_ addons: URL, depth: Int = 3) -> [String: URL] {
        index(addons, depth: depth).savers.mapValues(\.url)
    }

    /// Each installed addon that saves, keyed by lowercased name, with the variables its manifest declares.
    public static func declarations(_ addons: URL, depth: Int = 3) -> [String: (addon: String, variables: [String])] {
        index(addons, depth: depth).savers.mapValues { ($0.addon, $0.variables) }
    }
}

private extension URL {
    var isFolder: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    /// Logical length of the file (what you read), not the space allocated on disk.
    var fileSize: Int64 { Int64((try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    var modified: Date? { (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
}

extension SavedVariablesAudit {
    /// Each addon that saves, keyed by lowercased name, with the top folder in AddOns it ships in
    /// (GS16Data -> LibGuildStore), so a map can group a library's data addons with it.
    public static func topFolders(_ addons: URL, depth: Int = 3) -> [String: String] {
        index(addons, depth: depth).topFolders
    }
}
