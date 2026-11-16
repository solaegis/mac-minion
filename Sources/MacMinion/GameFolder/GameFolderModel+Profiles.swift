import Foundation
import MacMinionKit

/// Default addon profiles and who loads what (S-070): each addon's defaults, from the companion's capture in
/// the game or else the addon's own Lua, and the settings each character runs on.
extension GameFolderModel {
    /// Each saving addon's defaults, by SavedVariables file: the companion's copy of a variable's defaults
    /// wins over what the source makes plain. Sources are read once per addon version and kept.
    nonisolated static func readDefaults(savers: [String: (url: URL, addon: String, variables: [String])], files: Set<String>,
                                         layouts: [String: CompanionSVLayout],
                                         cache: [String: (version: String, found: [SVDefaults.Found])])
        -> (defaults: [String: [SVDefaults.Found]], cache: [String: (version: String, found: [SVDefaults.Found])]) {
        var cache = cache
        var out: [String: [SVDefaults.Found]] = [:]
        for saver in savers.values {
            let file = saver.url.lastPathComponent + ".lua"
            guard files.contains(file) else { continue }
            let version = Manifest.read(folder: saver.url)?.version ?? ""
            let fromSource: [SVDefaults.Found]
            if let kept = cache[saver.url.path], kept.version == version {
                fromSource = kept.found
            } else {
                fromSource = Array(SVDefaults.parse(sources: SVSourceNames.sourceTexts(folder: saver.url), variables: saver.variables).values)
                cache[saver.url.path] = (version, fromSource)
            }
            var found: [SVDefaults.Found] = []
            for variable in saver.variables {
                let captured = layouts[variable]?.defaults
                let read = fromSource.first { $0.variable == variable }
                if let captured {
                    let lsv = layouts[variable]?.ctor?.hasPrefix("LSV") == true || read?.libSavedVars == true
                    found.append(SVDefaults.Found(variable: variable, table: captured.table, libSavedVars: lsv))
                } else if let read {
                    found.append(read)
                }
            }
            if !found.isEmpty { out[file] = found }
        }
        return (out, cache)
    }

    /// Each character's loaded addons that save, by SavedVariables file: from the companion's record of what
    /// they turned off, or else their list in AddOnSettings.txt. Characters neither covers are left out.
    var addonLoads: [String: Set<String>] {
        guard let base = current?.matrix, let folders = addonFolders else { return [:] }
        let present = Set(savedVariables.map(\.name))
        // Folder as the game names it -> its SavedVariables file.
        let saverFiles = folders.values.reduce(into: [String: String]()) { out, url in
            let file = url.lastPathComponent + ".lua"
            if present.contains(file) { out[url.lastPathComponent] = file }
        }
        let choices = addOnChoices
        var loads: [String: Set<String>] = [:]
        for id in base.characterIDs {
            if let enabled = app.companionSnapshot?.enabledBy[id] {
                let off = Set((enabled.disabled + enabled.notLoaded).map { $0.lowercased() })
                loads[id] = Set(saverFiles.filter { !off.contains($0.key.lowercased()) }.values)
            } else if let header = addOnHeader(id), let list = choices?.effective(for: header).choices {
                loads[id] = Set(saverFiles.filter { list[$0.key] == true }.values)
            }
        }
        return loads
    }

    /// Works the settings each character runs on out again, after a read, a new AddOnSettings.txt, or new defaults.
    func refreshEffectiveMatrix() {
        guard let base = current?.matrix else { effectiveMatrix = nil; return }
        effectiveMatrix = base.applying(SettingsMatrix.ProfileContext(defaults: addonDefaults, loads: addonLoads), names: names)
    }
}
