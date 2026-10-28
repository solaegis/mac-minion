import Foundation

/// A library one or more installed addons ask for that isn't in AddOns.
public struct MissingLibrary: Sendable, Hashable, Identifiable {
    public var id: String { folder }
    /// The folder name the manifests ask for.
    public let folder: String
    /// The ESOUI entry that installs it.
    public let addon: CatalogAddon
    /// Folders of the installed addons that ask for it.
    public let wantedBy: [String]
    /// True when at least one addon lists it in DependsOn: that addon won't load without it.
    public let required: Bool
}

/// Reads `## DependsOn:` and `## OptionalDependsOn:` from every folder in AddOns and finds the ESOUI
/// libraries they name that aren't there.
public enum LibraryAdvisor {
    /// Obsolete libraries that addons still name for old game versions; never worth installing now.
    static let obsolete: Set<String> = ["LibStub"]

    /// `nested` are library folders bundled inside other addons; the game loads those too.
    public static func missing(folders: [String: Manifest?], nested: Set<String> = [], catalog: [CatalogAddon]) -> [MissingLibrary] {
        var wanted: [String: (by: Set<String>, required: Bool)] = [:]
        func present(_ name: String) -> Bool { folders[name] != nil || nested.contains(name) }
        for (folder, manifest) in folders {
            guard let manifest else { continue }
            for name in manifest.dependsOn where !present(name) {
                wanted[name, default: ([], false)].by.insert(folder)
                wanted[name]?.required = true
            }
            for name in manifest.optionalDependsOn where !present(name) {
                wanted[name, default: ([], false)].by.insert(folder)
            }
        }
        var byFolder: [String: [CatalogAddon]] = [:]
        for addon in catalog { for dir in addon.dirs { byFolder[dir, default: []].append(addon) } }
        return wanted.compactMap { name, want -> MissingLibrary? in
            guard !obsolete.contains(name), let entries = byFolder[name] else { return nil }
            // Prefer the entry that installs just this folder, then the most downloaded.
            guard let best = entries.max(by: { ($0.dirs.count == 1 ? 1 : 0, $0.downloads) < ($1.dirs.count == 1 ? 1 : 0, $1.downloads) })
            else { return nil }
            // Optional ones: libraries only. A missing required dependency counts whatever it is.
            guard want.required || best.categoryID == AddonCategory.librariesID else { return nil }
            return MissingLibrary(folder: name, addon: best, wantedBy: want.by.sorted(), required: want.required)
        }
        .sorted { ($0.required ? 0 : 1, -$0.wantedBy.count, $0.folder) < ($1.required ? 0 : 1, -$1.wantedBy.count, $1.folder) }
    }
}
