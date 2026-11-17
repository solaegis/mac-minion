import Foundation
import MacMinionKit

/// What an addon's own source, and AI, call the keys in its SavedVariables (docs/SOURCE-NAMES.md).
extension GameFolderModel {
    /// Reads what the file's addon calls its keys, once per file until the files change: only the
    /// open file needs it, and reading every addon's source took half of the whole read.
    func loadSourceNames(for file: String, generation: Int? = nil) async {
        guard inspectorSourceNames[file] == nil else { return }
        let found = await withInspectorStatus(String(localized: "Reading names from the addon's source…")) {
            await readSourceNames([file])
        }
        // A newer inspect may have cleared or replaced names while this read ran.
        if Task.isCancelled { return }
        if let generation, generation != inspectGeneration { return }
        apply(found)
    }

    /// What the source says for every file the Characters tab shows, from the cache where the addon's
    /// version hasn't changed. Also learns each file's variables, so a setting finds its file.
    func loadCharacterSourceNames() async {
        guard let matrix else { return }
        var variables: [String: String] = [:]
        for addon in matrix.addons {
            for settings in addon.characters.values {
                for setting in settings.values { if let v = setting.path.first?.description { variables[v] = addon.file } }
            }
        }
        schemaFileByVariable.merge(variables) { _, new in new }
        let missing = matrix.addons.map(\.file).filter { inspectorSourceNames[$0] == nil }
        if !missing.isEmpty {
            let found = await readSourceNames(missing)
            if Task.isCancelled { return }
            apply(found)
        }
        await collectListedIDs()
    }

    /// Game IDs in lists AI read the kind of, from every file that has such a list (S-077).
    func collectListedIDs() async {
        let withKinds = inspectorSourceNames.filter(\.value.hasIDKinds)
        let urls = Dictionary(savedVariables.map { ($0.name, $0.url) }, uniquingKeysWith: { a, _ in a })
        let docs = documents
        listedIDs = await Task.detached { () -> [String: Set<Int>] in
            var all: [String: Set<Int>] = [:]
            for (file, names) in withKinds {
                guard let url = urls[file], let doc = docs.get(file) ?? docs.document(named: file, at: url) else { continue }
                all.merge(names.idLookups(in: doc)) { $0.union($1) }
            }
            return all
        }.value
    }

    /// One result per file: the source's names (from the cache or read now) with AI names on top.
    private struct SourceRead: Sendable {
        let file: String
        let names: SVSourceNames
        /// Set when the source was read, not cached: to keep.
        let fresh: (folder: String, version: String)?
    }

    private func readSourceNames(_ files: [String]) async -> [SourceRead] {
        let addons = app.addonsFolder, aiCache = aiKeyNames, aiFields = aiKeyFields, known = addonFolders, cache = schemaCache
        // The companion's settings panels by addon folder (S-077).
        var panels: [String: [CompanionLAMControl]] = [:]
        for panel in (app.companionSnapshot?.lamPanels ?? [:]).values {
            if let addon = panel.addon?.lowercased() { panels[addon, default: []] += panel.controls }
        }
        return await Task.detached { () -> [SourceRead] in
            var savers: [String: URL]?
            return files.map { file in
                let base = String(file.dropLast(4)).lowercased()
                if known?[base] == nil, savers == nil { savers = SavedVariablesAudit.saverFolders(addons) }
                guard let folder = known?[base] ?? savers?[base] else { return SourceRead(file: file, names: SVSourceNames(), fresh: nil) }
                let version = Manifest.read(folder: folder)?.version ?? ""
                let name = folder.lastPathComponent
                // The version and the files' stamp: source can change without a new version.
                let stamp = "\(version)#\(SVSourceNames.fingerprint(folder: folder))"
                var found: SVSourceNames, fresh: (String, String)?
                if let cached = cache[folder: name, version: stamp] {
                    found = cached
                } else {
                    found = SVSourceNames.read(folder: folder)
                    fresh = (name, stamp)
                }
                // Names AI gave this version of the addon before.
                for e in aiCache.entries(folder: name, version: version) {
                    found.add(SVSourceName(title: e.name, detail: nil, source: .ai, isGuess: true), key: e.key, parent: e.parent)
                }
                for e in aiFields.entries(folder: name, version: version) { found.addAI(e.field, key: e.key, parent: e.parent) }
                if let controls = panels[name.lowercased()] { found.applyCompanion(controls) }
                return SourceRead(file: file, names: found, fresh: fresh)
            }
        }.value
    }

    private func apply(_ reads: [SourceRead]) {
        var changed = false, kept: [(folder: String, version: String)] = []
        for read in reads {
            inspectorSourceNames[read.file] = read.names
            if let fresh = read.fresh {
                // Kept without AI names: those have their own cache and are added on each read.
                schemaCache[folder: fresh.folder, version: fresh.version] = SVSourceNames.withoutAI(read.names)
                kept.append(fresh)
                changed = true
            }
        }
        if changed {
            // An older version or stamp of the same addon isn't needed again.
            schemaCache.keepOnly(kept)
            Store.saveSchemas(schemaCache)
        }
    }

    /// Keys in the table shown that AI could say more about: ones the source doesn't name, numbers with no
    /// range or choices, and numbered lists, unless AI was asked about them before (S-074).
    var keysToNameWithAI: [String] {
        let source = inspectorFile.flatMap { inspectorSourceNames[$0] }
        return inspectorRows.compactMap { node in
            guard node.level == nil, case .string(let key) = node.key, !CharacterID.isID(key),
                  source?.aiField(for: node.key, at: node.parentPath) == nil else { return nil }
            let unnamed = source?.name(for: node.key, at: node.parentPath)?.title == nil
            let control = source?.control(for: node.key, at: node.parentPath)
            let bareNumber = { if case .integer = node.value { control == nil } else { false } }()
            let list = node.value.table.map { t in !t.entries.isEmpty && t.entries.allSatisfy { if case .integer = $0.key { true } else { false } } } ?? false
            return unnamed || bareNumber || (list && control?.indexMeaning == nil && control?.idKind == nil) ? key : nil
        }
    }

    /// Asks the configured AI to name the shown table's keys from the lines of the addon's source that use
    /// them. Sends key names and source lines only, never saved values.
    func nameKeysWithAI() async {
        guard let file = inspectorFile, !aiNamingBusy else { return }
        let keys = keysToNameWithAI, parent = inspectorFocus.last?.description ?? "", addons = app.addonsFolder
        message = nil
        errorMessage = nil
        if let problem = app.prefs.aiConfig.problem { errorMessage = problem; return }
        guard !keys.isEmpty else { message = String(localized: "AI has nothing more to read here: every key is named or was asked about."); return }
        let shapes = Dictionary(inspectorRows.compactMap { node -> (String, String)? in
            guard case .string(let key) = node.key, keys.contains(key) else { return nil }
            return (key, SVAISchema.shape(of: node.value))
        }, uniquingKeysWith: { a, _ in a })
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
            let asked = Set(found.evidence.map(\.key))
            let answer = try await AIClient(config: app.prefs.aiConfig).complete(
                system: SVAISchema.system,
                prompt: SVAISchema.prompt(addon: app.addonName(file), table: table, evidence: found.evidence, shapes: shapes))
            let read = applyAIFields(SVAISchema.parse(answer, keys: asked), asked: asked,
                                     file: file, folder: found.folder, version: found.version, parent: parent)
            message = read == 0 ? "\(app.aiSource) couldn't tell what these keys are for from the source."
                : "\(app.aiSource) read \(read) key\(read == 1 ? "" : "s") from \(app.addonName(file))'s source. What it says ends in “?”: it's a guess."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps what AI read for this addon version and shows it; returns how many keys it said something about.
    /// Keys asked about with no answer are kept as asked, so they aren't sent again for this version.
    @discardableResult
    func applyAIFields(_ fields: [String: SVAIField], asked: Set<String>, file: String, folder: String, version: String,
                       parent: String) -> Int {
        var source = inspectorSourceNames[file] ?? SVSourceNames()
        for key in asked {
            let field = fields[key] ?? SVAIField()
            aiKeyFields[folder, version, parent, key] = field
            source.addAI(field, key: key, parent: parent)
            if let label = field.label { aiKeyNames[folder, version, parent, key] = label }
        }
        inspectorSourceNames[file] = source
        Store.saveAIFields(aiKeyFields)
        if fields.values.contains(where: { $0.idKind != nil }) { Task { await collectListedIDs() } }
        Store.saveAINames(aiKeyNames)
        return fields.count
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

    /// For an item of a numbered list: what its position stands for ("Favorite zone 1"), from AI.
    func inspectorItemLabel(_ node: SVNode) -> String? {
        guard case .integer(let n) = node.key, let meaning = inspectorFile.flatMap({ inspectorSourceNames[$0] })?.itemControl(at: node.parentPath)?.indexMeaning
        else { return nil }
        return "\(meaning) \(n)?"
    }

    /// A game ID AI read the kind of, for the value or for the list it's in, named.
    func inspectorIDName(_ node: SVNode) -> SVName? {
        guard case .integer(let id) = node.value, let source = inspectorFile.flatMap({ inspectorSourceNames[$0] }) else { return nil }
        let kind = source.control(for: node.key, at: node.parentPath)?.idKind
            ?? { if case .integer = node.key { source.itemControl(at: node.parentPath)?.idKind } else { nil } }()
        return kind.flatMap { names?.name(forID: id, kind: $0) }
    }

    /// The range or choices the addon's source gives a key in the open file.
    func inspectorControl(_ key: LuaKey, at parent: [LuaKey]) -> SVControl? {
        inspectorFile.flatMap { inspectorSourceNames[$0] }?.control(for: key, at: parent)
    }

    /// What the addon's source says about the file a setting is in.
    func sourceNames(for setting: SettingsMatrix.Setting) -> SVSourceNames? {
        setting.path.first.flatMap { schemaFileByVariable[$0.description] }.flatMap { inspectorSourceNames[$0] }
    }

    /// A Characters-tab setting label ("Colors › Guild 1") with its last part named by the addon's source,
    /// when the source names it. A guess ends in "?".
    func settingLabel(_ label: String, _ setting: SettingsMatrix.Setting?) -> String {
        guard let setting, let named = sourceNames(for: setting)?.name(for: setting.key, at: Array(setting.path.dropLast())),
              var title = named.title else { return label }
        if named.isGuess, !title.hasSuffix("?") { title += "?" }
        var parts = label.components(separatedBy: " › ")
        parts[parts.count - 1] = title
        return parts.joined(separator: " › ")
    }
}
