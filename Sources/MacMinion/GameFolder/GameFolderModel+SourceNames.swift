import Foundation
import MacMinionKit

/// What an addon's own source, and AI, call the keys in its SavedVariables (docs/SOURCE-NAMES.md).
extension GameFolderModel {
    /// Reads what the file's addon calls its keys, once per file until the files change: only the
    /// open file needs it, and reading every addon's source took half of the whole read.
    func loadSourceNames(for file: String) async {
        guard inspectorSourceNames[file] == nil else { return }
        let addons = app.addonsFolder, aiCache = aiKeyNames, known = addonFolders
        let found = await Task.detached { () -> SVSourceNames in
            let base = String(file.dropLast(4)).lowercased()
            guard let folder = known?[base] ?? SavedVariablesAudit.saverFolders(addons)[base] else { return SVSourceNames() }
            var found = SVSourceNames.read(folder: folder)
            // Names AI gave this version of the addon before.
            let version = Manifest.read(folder: folder)?.version ?? ""
            for e in aiCache.entries(folder: folder.lastPathComponent, version: version) {
                found.add(SVSourceName(title: e.name, detail: nil, source: .ai, isGuess: true), key: e.key, parent: e.parent)
            }
            return found
        }.value
        inspectorSourceNames[file] = found
    }

    /// Keys in the table shown that the addon's source doesn't name: what AI is asked about.
    var keysToNameWithAI: [String] {
        inspectorRows.compactMap { node in
            guard node.level == nil, case .string(let key) = node.key, !CharacterID.isID(key),
                  inspectorSourceName(node.key, at: node.parentPath)?.title == nil else { return nil }
            return key
        }
    }

    /// Asks the configured AI to name the shown table's keys from the lines of the addon's source that use
    /// them. Sends key names and source lines only, never saved values.
    func nameKeysWithAI() async {
        guard let file = inspectorFile, !aiNamingBusy else { return }
        let keys = keysToNameWithAI, parent = inspectorFocus.last?.description ?? "", addons = app.addonsFolder
        message = nil
        errorMessage = nil
        guard !keys.isEmpty else { message = String(localized: "Every key in this table already has a name."); return }
        aiNamingBusy = true
        defer { aiNamingBusy = false }
        let found = await Task.detached { () -> (folder: String, version: String, evidence: [SVKeyEvidence])? in
            guard let folder = SavedVariablesAudit.saverFolders(addons)[String(file.dropLast(4)).lowercased()] else { return nil }
            return (folder.lastPathComponent, Manifest.read(folder: folder)?.version ?? "",
                    SVAINaming.evidence(keys: keys, sources: SVSourceNames.sourceTexts(folder: folder)))
        }.value
        guard let found else { errorMessage = String(localized: "No installed addon saves \(file), so there's no source to read."); return }
        guard !found.evidence.isEmpty else {
            message = "\(app.addonName(file))'s source doesn't use these keys by name, so there's nothing for AI to read."
            return
        }
        let table = ([file] + inspectorFocus.map(\.description)).joined(separator: " › ")
        do {
            let answer = try await AIClient(config: app.prefs.aiConfig).complete(
                system: SVAINaming.system, prompt: SVAINaming.prompt(addon: app.addonName(file), table: table, evidence: found.evidence))
            let named = applyAINames(SVAINaming.parse(answer, keys: Set(found.evidence.map(\.key))),
                                     file: file, folder: found.folder, version: found.version, parent: parent)
            message = named == 0 ? "\(app.aiSource) couldn't tell what these keys are for from the source."
                : "\(app.aiSource) named \(named) key\(named == 1 ? "" : "s") from \(app.addonName(file))'s source. They end in “?”: they're guesses."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps AI names for this addon version and shows them; returns how many there were.
    @discardableResult
    func applyAINames(_ names: [String: String], file: String, folder: String, version: String, parent: String) -> Int {
        guard !names.isEmpty else { return 0 }
        var source = inspectorSourceNames[file] ?? SVSourceNames()
        for (key, name) in names {
            aiKeyNames[folder, version, parent, key] = name
            source.add(SVSourceName(title: name, detail: nil, source: .ai, isGuess: true), key: key, parent: parent)
        }
        inspectorSourceNames[file] = source
        Store.saveAINames(aiKeyNames)
        return names.count
    }

    /// What the addon's source calls a key in the open file.
    func inspectorSourceName(_ key: LuaKey, at parent: [LuaKey]) -> SVSourceName? {
        inspectorFile.flatMap { inspectorSourceNames[$0] }?.name(for: key, at: parent)
    }
}
