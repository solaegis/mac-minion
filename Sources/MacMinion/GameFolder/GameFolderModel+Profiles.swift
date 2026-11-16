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
        let wanted = savers.values.filter { files.contains($0.url.lastPathComponent + ".lua") }
        // Read the addons not kept from the last read in parallel: each is independent, and reading their Lua
        // is most of the time.
        let versions = wanted.map { Manifest.read(folder: $0.url)?.version ?? "" }
        let stale = wanted.indices.filter { cache[wanted[$0].url.path]?.version != versions[$0] }
        let fresh = ParsedSlots(count: stale.count)
        DispatchQueue.concurrentPerform(iterations: stale.count) { n in
            let saver = wanted[stale[n]]
            fresh.set(n, Array(SVDefaults.parse(sources: SVSourceNames.sourceTexts(folder: saver.url), variables: saver.variables).values))
        }
        for (n, i) in stale.enumerated() { cache[wanted[i].url.path] = (versions[i], fresh.get(n)) }
        for saver in wanted {
            let file = saver.url.lastPathComponent + ".lua"
            let fromSource = cache[saver.url.path]?.found ?? []
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

/// One result slot per addon, written from concurrent reads.
nonisolated private final class ParsedSlots: @unchecked Sendable {
    private var slots: [[SVDefaults.Found]]
    private let lock = NSLock()

    init(count: Int) { slots = Array(repeating: [], count: count) }

    func set(_ i: Int, _ value: [SVDefaults.Found]) { lock.withLock { slots[i] = value } }
    func get(_ i: Int) -> [SVDefaults.Found] { lock.withLock { slots[i] } }
}
