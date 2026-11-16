import Foundation
import MacMinionKit

/// Default addon profiles (S-070): each addon's defaults, from the companion's capture in
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

    /// Works the settings each character runs on out again, after a read or new defaults.
    func refreshEffectiveMatrix() {
        guard let base = current?.matrix else { effectiveMatrix = nil; return }
        effectiveMatrix = base.applying(SettingsMatrix.ProfileContext(defaults: addonDefaults), names: names)
    }
}
