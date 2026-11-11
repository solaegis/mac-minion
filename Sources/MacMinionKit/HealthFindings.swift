import Foundation

/// One thing wrong in the game folder, by cause: the raw problems one action fixes, in plain words.
/// Built by `HealthFindings.build`; see docs/HEALTH-FINDINGS-PLAN.md.
public struct HealthFinding: Sendable, Identifiable, Equatable {
    /// What the player experiences, worst first.
    public enum Tier: Int, Sendable, Comparable, CaseIterable {
        case broken, dataAtRisk, outOfDate, clutter, size, info

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        /// The tier a raw problem of this kind belongs to on its own.
        public static func of(_ kind: SVProblem.Kind) -> Tier {
            switch kind {
            case .didntLoad, .luaError: .broken
            case .unreadable, .endsEarly, .missingVariable, .typeMismatch: .dataAtRisk
            case .outOfDateAddon: .outOfDate
            case .unusedFile, .staleFile, .copyFile, .strayItem, .unknownVariable, .unknownCharacter: .clutter
            case .longList, .largeFile, .slowLoad: .size
            case .empty, .unknownSchema: .info
            }
        }

        public var title: String {
            switch self {
            case .broken: String(localized: "Broken in game", bundle: .module)
            case .dataAtRisk: String(localized: "Saved data at risk", bundle: .module)
            case .outOfDate: String(localized: "Out of date", bundle: .module)
            case .clutter: String(localized: "Clean up", bundle: .module)
            case .size: String(localized: "Size and speed", bundle: .module)
            case .info: String(localized: "More", bundle: .module)
            }
        }
    }

    public enum Cause: String, Sendable, CaseIterable {
        case missingLibraries, outOfDateAddon, outOfDateAddons, damagedFile, ignoredData, runawayData,
             removedAddonLeftovers, unusedAddons, copiesAndStrays, unknownCharacter, mixedTypes, olderVersionLeftovers, single
    }

    /// How sure the grouping is. Anything short of certain says why on the card.
    public enum Certainty: String, Sendable { case certain, likely, possible }

    /// The one button a finding offers. Addons are named by folder, as manifests and the game name them.
    public enum Action: Sendable, Equatable {
        case installLibraries(folders: [String])
        case update(folders: [String])
        case showAddon(folder: String)
        case restoreFromBackup(files: [String])
        case cleanUp(problemIDs: [String])
        case showInInspector(problemID: String)
        /// Every place a character ID appears, in the Inspector.
        case findCharacter(id: String)
    }

    public enum Subject: Sendable, Hashable {
        case addon(String), character(String), file(String)
        public var name: String {
            switch self { case .addon(let n), .character(let n), .file(let n): n }
        }
    }

    /// `<cause>|<key>`, the same on every run.
    public let id: String
    public let cause: Cause
    public let tier: Tier
    public let certainty: Certainty
    /// The cause in plain words.
    public let title: String
    /// One sentence: what the player sees in game or could lose.
    public let impact: String
    /// What the count means (rule 4), when there is a count to interpret.
    public let summary: String?
    /// Why this isn't certain, when the card should say more than the certainty alone.
    public let certaintyNote: String?
    /// Addons first, then characters or files; the card collapses past a few.
    public let affected: [Subject]
    /// Nil: nothing to press, so the finding sits behind the More disclosure.
    public let action: Action?
    /// The raw problems, in the order they came in.
    public let problems: [SVProblem]
    /// Lowercased folders of the addons this finding is about, for links from other tabs (S-058).
    public let addonFolders: Set<String>
    /// IDs of the characters it names, for links from a character's page (S-058).
    public let characterIDs: Set<String>
    public let bytes: Int64

    /// In the main list; the rest go behind More.
    public var isMain: Bool { action != nil && tier != .info }
}

public enum HealthFindings {
    /// What the analysis reads beside the raw problems. Every part is optional; less input means less certainty.
    public struct Context: Sendable {
        /// SavedVariables files with their owners and sizes.
        public var files: [SavedVariablesFile]
        /// `LibraryAdvisor.missing`, unfiltered.
        public var libraries: [MissingLibrary]
        /// For `dependsOn` LibStub, and the characters an addon is on for.
        public var graph: SVGraph?
        public var companion: CompanionSnapshot?
        /// Lowercased folders of installed addons.
        public var installed: Set<String>
        /// Lowercased folders of installed addons with an update ready.
        public var updatable: Set<String>

        public init(files: [SavedVariablesFile] = [], libraries: [MissingLibrary] = [], graph: SVGraph? = nil,
                    companion: CompanionSnapshot? = nil, installed: Set<String> = [], updatable: Set<String> = []) {
            self.files = files; self.libraries = libraries; self.graph = graph; self.companion = companion
            self.installed = installed; self.updatable = updatable
        }
    }

    /// Libraries the game dropped; an addon that still needs one is out of date, not missing a library.
    static let obsolete: Set<String> = ["libstub"]

    /// Groups `problems` by cause, so each one is in exactly one finding, and ranks the findings:
    /// tier, then addons and characters affected, then severity, then bytes, then title and id.
    public static func build(problems: [SVProblem], context: Context) -> [HealthFinding] {
        var builder = Builder(problems: problems, context: context)
        builder.missingLibraries()
        builder.outOfDate()
        builder.damagedFiles()
        builder.ignoredData()
        builder.runawayData()
        builder.clutter()
        builder.unknownCharacters()
        builder.perFileGroups()
        builder.standAlone()
        assert(builder.claimed.allSatisfy { $0 }, "every problem is in a finding")
        return ranked(builder.findings)
    }

    static func ranked(_ findings: [HealthFinding]) -> [HealthFinding] {
        func severity(_ f: HealthFinding) -> Int { f.problems.map(\.severity.rawValue).max() ?? 0 }
        return findings.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.affected.count != b.affected.count { return a.affected.count > b.affected.count }
            if severity(a) != severity(b) { return severity(a) > severity(b) }
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            let byTitle = a.title.localizedStandardCompare(b.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return a.id < b.id
        }
    }
}

/// The claim passes. Each pass takes only problems no earlier pass took, by position in the input.
private struct Builder {
    let problems: [SVProblem]
    let context: HealthFindings.Context
    var claimed: [Bool]
    var findings: [HealthFinding] = []

    init(problems: [SVProblem], context: HealthFindings.Context) {
        self.problems = problems
        self.context = context
        claimed = Array(repeating: false, count: problems.count)
    }

    // MARK: Helpers

    static func key(_ s: String) -> String { s.lowercased() }

    func open(where match: (SVProblem) -> Bool) -> [Int] {
        problems.indices.filter { !claimed[$0] && match(problems[$0]) }
    }

    func addonKey(_ p: SVProblem) -> String? { p.addon.map(Self.key) }

    /// The addon's title as the game shows it, else its folder.
    func title(ofAddon folder: String) -> String {
        if let state = context.companion?.addons.first(where: { Self.key($0.key) == Self.key(folder) })?.value {
            return state.title ?? state.name
        }
        return folder
    }

    /// The addon a SavedVariables file belongs to, else the file's name.
    func owner(ofFile file: String) -> String {
        if case .addon(let addon)? = context.files.first(where: { $0.name == file })?.owner { return addon }
        return String(file.prefix { $0 != "." })
    }

    /// The installed addon folder a SavedVariables file belongs to, if any.
    func ownerFolder(ofFile file: String) -> String? {
        if case .addon(let addon)? = context.files.first(where: { $0.name == file })?.owner { return addon }
        return nil
    }

    func size(ofFile file: String) -> Int64 { context.files.first { $0.name == file }?.bytes ?? 0 }

    /// True when the graph says the addon's manifest still names LibStub, or the game said LibStub kept it from loading.
    func needsLibStub(_ folder: String) -> Bool {
        let k = Self.key(folder)
        if let deps = context.graph?.out.first(where: { $0.key.kind == .addon && Self.key($0.key.key) == k })?.value[.dependsOn],
           deps.contains(where: { HealthFindings.obsolete.contains(Self.key($0.key)) }) {
            return true
        }
        return companionMissing(folder).contains { HealthFindings.obsolete.contains(Self.key($0)) }
    }

    func companionMissing(_ folder: String) -> [String] {
        context.companion?.addons.first { Self.key($0.key) == Self.key(folder) }?.value.missing ?? []
    }

    /// The characters an addon was on for at their last login, by name: the graph, else the companion.
    func characters(for folders: [String]) -> [(id: String, name: String)] {
        var ids: Set<String> = []
        let keys = Set(folders.map(Self.key))
        if let graph = context.graph {
            for node in graph.nodes.keys where node.kind == .addon && keys.contains(Self.key(node.key)) {
                for (c, why) in graph.characters(for: node.key) where why.contains(.enabledFor) { ids.insert(c.key) }
            }
        } else if let snap = context.companion {
            // Only addons the game reported: one it never saw isn't on for anyone.
            let known = keys.intersection(snap.addons.keys.map(Self.key))
            for (id, row) in snap.enabledBy {
                let off = Set(row.disabled.map(Self.key))
                if known.contains(where: { !off.contains($0) }) { ids.insert(id) }
            }
        }
        let named = ids.map { (id: $0, name: context.companion?.characters[$0]?.name ?? context.graph?.nodes[SVGraph.NodeID(.character, $0)]?["name"] ?? $0) }
        return named.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Adds a finding made of the problems at `indices` and marks them taken.
    mutating func add(_ cause: HealthFinding.Cause, key: String, tier: HealthFinding.Tier? = nil, certainty: HealthFinding.Certainty = .certain,
                      title: String, impact: String, summary: String? = nil, note: String? = nil,
                      affected: [HealthFinding.Subject], action: HealthFinding.Action?, indices: [Int], bytes: Int64? = nil,
                      folders: [String] = [], characters: [(id: String, name: String)] = []) {
        for i in indices { claimed[i] = true }
        let members = indices.sorted().map { problems[$0] }
        let worst = members.map { HealthFinding.Tier.of($0.kind) }.min() ?? .info
        var seen: Set<HealthFinding.Subject> = []
        // Every addon it touches: named outright, named by a companion problem, or owning a file in it. The
        // companion's own file only reports on other addons, so it never makes a finding about the companion.
        let owners = members.filter { !CompanionData.isCompanionFile($0.file) }.compactMap { ownerFolder(ofFile: $0.file) }
        let addonFolders = Set((folders + members.compactMap(\.addon) + owners).map(Self.key))
        // A character no file names says so in the title already; "On Unknown character" would only repeat it.
        let named = affected + characters.filter { $0.name != SVName.unknownCharacter }.map { .character($0.name) }
        findings.append(HealthFinding(
            id: "\(cause.rawValue)|\(key)", cause: cause, tier: tier ?? worst, certainty: certainty,
            title: title, impact: impact, summary: summary, certaintyNote: note,
            affected: named.filter { seen.insert($0).inserted }, action: action, problems: members,
            addonFolders: addonFolders, characterIDs: Set(characters.map(\.id)),
            bytes: bytes ?? members.reduce(0) { $0 + $1.bytes }))
    }

    func luaErrorCount(_ folders: Set<String>) -> Int {
        context.companion?.errors.filter { $0.addon.map { folders.contains(Self.key($0)) } ?? false }.reduce(0) { $0 + $1.count } ?? 0
    }

    // MARK: 1. Missing libraries

    /// Joins every missing library to the addons that need it, then makes one finding per connected group:
    /// two libraries the same addons need are one finding, and an installed library that didn't load
    /// because of another missing one joins that one's group.
    mutating func missingLibraries() {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var x = x
            while let p = parent[x], p != x { x = p }
            return x
        }
        func union(_ a: String, _ b: String) {
            parent[a] = parent[a] ?? a
            parent[b] = parent[b] ?? b
            let ra = find(a), rb = find(b)
            if ra != rb { if ra < rb { parent[rb] = ra } else { parent[ra] = rb } }
        }

        // lib key -> (folder as asked for, catalog entry, from a manifest)
        var libs: [String: (folder: String, catalog: CatalogAddon?, manifest: Bool)] = [:]
        var addonFolder: [String: String] = [:]
        for lib in context.libraries where lib.required {
            let k = Self.key(lib.folder)
            libs[k] = (lib.folder, lib.addon, true)
            for dependent in lib.wantedBy {
                addonFolder[Self.key(dependent)] = dependent
                union("lib:" + k, "addon:" + Self.key(dependent))
            }
        }
        for (name, state) in context.companion?.addons ?? [:] {
            for missing in state.missing where !HealthFindings.obsolete.contains(Self.key(missing)) {
                let m = Self.key(missing)
                addonFolder[Self.key(name)] = name
                if context.installed.contains(m) {
                    // Installed but didn't load itself: the cause is whatever it is missing.
                    addonFolder[m] = addonFolder[m] ?? missing
                    union("addon:" + m, "addon:" + Self.key(name))
                } else {
                    if libs[m] == nil {
                        let known = context.libraries.first { Self.key($0.folder) == m }
                        libs[m] = (missing, known?.addon, false)
                    }
                    union("lib:" + m, "addon:" + Self.key(name))
                }
            }
        }

        var groups: [String: (libs: [String], addons: [String])] = [:]
        for node in parent.keys {
            let root = find(node)
            if node.hasPrefix("lib:") { groups[root, default: ([], [])].libs.append(String(node.dropFirst(4))) }
            else { groups[root, default: ([], [])].addons.append(String(node.dropFirst(6))) }
        }
        for (_, group) in groups.sorted(by: { $0.key < $1.key }) where !group.libs.isEmpty {
            let libKeys = group.libs.sorted()
            let dependents = Set(group.addons)
            let indices = open { [.didntLoad, .luaError].contains($0.kind) && addonKey($0).map(dependents.contains) == true }
            let entries = libKeys.compactMap { libs[$0] }
            let installable = entries.filter { $0.catalog != nil }.map(\.folder)
            let folders = group.addons.sorted().map { addonFolder[$0] ?? $0 }
            let heading = entries.count == 1
                ? String(localized: "\(entries[0].catalog?.name ?? entries[0].folder) is missing", bundle: .module)
                : String(localized: "\(entries.count) libraries are missing", bundle: .module)
            var impact = entries.count == 1
                ? String(localized: "\(folders.count) addons don't load without it.", bundle: .module)
                : String(localized: "\(folders.count) addons don't load without them.", bundle: .module)
            if installable.isEmpty {
                impact += " " + String(localized: "ESOUI doesn't list it; the addon's page says where to get it.", bundle: .module)
            }
            let errors = luaErrorCount(Set(group.addons))
            let action: HealthFinding.Action? = !installable.isEmpty ? .installLibraries(folders: installable)
                : folders.first.map { .showAddon(folder: $0) }
            add(.missingLibraries, key: libKeys.joined(separator: "+"), tier: .broken,
                certainty: entries.allSatisfy(\.manifest) ? .certain : .likely,
                title: heading, impact: impact,
                summary: errors > 0 ? String(localized: "\(errors) Lua errors last session.", bundle: .module) : nil,
                affected: folders.map { .addon(title(ofAddon: $0)) },
                action: action, indices: indices, folders: folders, characters: characters(for: folders))
        }
    }

    // MARK: 2. Out of date

    mutating func outOfDate() {
        var addons: [String: String] = [:] // key -> folder
        for i in open(where: { $0.kind == .outOfDateAddon || ($0.kind == .didntLoad && $0.addon.map(needsLibStub) == true) }) {
            if let folder = problems[i].addon { addons[Self.key(folder)] = folder }
        }
        var merged: [(folder: String, indices: [Int])] = []
        for (k, folder) in addons.sorted(by: { $0.key < $1.key }) {
            let indices = open { [.outOfDateAddon, .luaError, .didntLoad].contains($0.kind) && addonKey($0) == k }
            let broken = indices.filter { problems[$0].kind != .outOfDateAddon }
            guard !broken.isEmpty else { merged.append((folder, indices)); continue }
            let libStub = needsLibStub(folder)
            let errors = luaErrorCount([k])
            let impact = broken.contains { problems[$0].kind == .didntLoad }
                ? String(localized: "It doesn't load in game.", bundle: .module)
                : String(localized: "It throws Lua errors in game.", bundle: .module)
            let summary = libStub ? String(localized: "It still needs LibStub, which the game no longer has.", bundle: .module)
                : errors > 0 ? String(localized: "\(errors) Lua errors last session.", bundle: .module) : nil
            add(.outOfDateAddon, key: k, tier: .broken, title: String(localized: "\(title(ofAddon: folder)) is out of date", bundle: .module),
                impact: impact, summary: summary,
                affected: [.addon(title(ofAddon: folder))],
                action: context.updatable.contains(k) ? .update(folders: [folder]) : .showAddon(folder: folder), indices: indices,
                folders: [folder], characters: characters(for: [folder]))
        }
        guard !merged.isEmpty else { return }
        let folders = merged.map(\.folder)
        let ready = folders.filter { context.updatable.contains(Self.key($0)) }
        let libStub = folders.filter(needsLibStub).count
        var parts: [String] = []
        if libStub > 0 { parts.append(String(localized: "\(libStub) still need LibStub", bundle: .module)) }
        if !ready.isEmpty { parts.append(String(localized: "\(ready.count) have an update ready", bundle: .module)) }
        let one = folders.count == 1
        let summary = !parts.isEmpty ? parts.formatted(.list(type: .and)) + "."
            : one ? String(localized: "No update yet.", bundle: .module) : String(localized: "None has an update yet.", bundle: .module)
        let heading = folders.count == 1 ? String(localized: "\(title(ofAddon: folders[0])) is out of date", bundle: .module)
            : String(localized: "\(folders.count) addons are out of date", bundle: .module)
        add(.outOfDateAddons, key: folders.map(Self.key).joined(separator: "+"), title: heading,
            impact: one ? String(localized: "It loads only while out-of-date addons are allowed, and can break after a game update.", bundle: .module)
                : String(localized: "They load only while out-of-date addons are allowed, and can break after a game update.", bundle: .module),
            summary: summary, affected: folders.map { .addon(title(ofAddon: $0)) },
            action: !ready.isEmpty ? .update(folders: ready) : .showAddon(folder: folders[0]),
            indices: merged.flatMap(\.indices), folders: folders)
    }

    // MARK: 3–5. Inside one file

    static let insideFile: Set<SVProblem.Kind> = [.unreadable, .endsEarly, .empty, .missingVariable, .unknownVariable, .typeMismatch, .longList, .largeFile]

    func files(with kind: SVProblem.Kind) -> [String] {
        Array(Set(open { $0.kind == kind }.map { problems[$0].file })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A file that doesn't read or ends early: the rest of what's found in it can't be trusted, so it's detail.
    mutating func damagedFiles() {
        let damaged = Set(files(with: .unreadable) + files(with: .endsEarly)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for file in damaged {
            let indices = open { $0.file == file && Self.insideFile.contains($0.kind) }
            let endsEarly = indices.contains { problems[$0].kind == .endsEarly }
            add(.damagedFile, key: file, title: String(localized: "\(owner(ofFile: file))'s saved data is damaged", bundle: .module),
                impact: endsEarly ? String(localized: "The file stops partway, so the addon may lose its settings at the next login.", bundle: .module)
                    : String(localized: "The game can't read it, so the addon starts with its defaults.", bundle: .module),
                affected: [.file(file)], action: .restoreFromBackup(files: [file]), indices: indices, bytes: size(ofFile: file))
        }
    }

    /// None of the declared variables is in the file, and the ones that are aren't declared: one cause.
    mutating func ignoredData() {
        for file in files(with: .missingVariable) {
            let indices = open { $0.file == file && ($0.kind == .missingVariable || $0.kind == .unknownVariable) }
            let addon = owner(ofFile: file)
            let bytes = size(ofFile: file)
            let ready = context.updatable.contains(Self.key(addon))
            add(.ignoredData, key: file, certainty: .likely,
                title: String(localized: "\(title(ofAddon: addon)) saves data the game doesn't load", bundle: .module),
                impact: String(localized: "Its settings may not stick between sessions.", bundle: .module),
                summary: String(localized: "\(bytes.formatted(.byteCount(style: .file))) the game never loads.", bundle: .module),
                affected: [.addon(title(ofAddon: addon)), .file(file)],
                action: ready ? .update(folders: [addon]) : .showInInspector(problemID: problems[indices[0]].id),
                indices: indices, bytes: bytes)
        }
    }

    /// A large file with a long list in it: the list is why it's large. Size alone is never a finding here.
    mutating func runawayData() {
        let large = Set(files(with: .largeFile))
        for file in files(with: .longList) where large.contains(file) {
            let addon = owner(ofFile: file)
            let indices = open { ($0.file == file && ($0.kind == .largeFile || $0.kind == .longList))
                || ($0.kind == .slowLoad && addonKey($0) == Self.key(addon)) }
            let bytes = size(ofFile: file)
            let list = indices.first { problems[$0].kind == .longList } ?? indices[0]
            add(.runawayData, key: file, title: String(localized: "\(title(ofAddon: addon))'s data keeps growing", bundle: .module),
                impact: String(localized: "The game reads all of it at every login and reload, so loading screens take longer.", bundle: .module),
                summary: String(localized: "\(bytes.formatted(.byteCount(style: .file))) in all.", bundle: .module),
                affected: [.addon(title(ofAddon: addon)), .file(file)],
                action: .showInInspector(problemID: problems[list].id), indices: indices, bytes: bytes)
        }
    }

    // MARK: 6. Clutter

    mutating func clutter() {
        let removed = open { $0.kind == .unusedFile }
        if !removed.isEmpty {
            let bytes = removed.reduce(Int64(0)) { $0 + problems[$1].bytes }
            add(.removedAddonLeftovers, key: "all", title: String(localized: "Files from \(removed.count) removed addons", bundle: .module),
                impact: String(localized: "The game never loads them.", bundle: .module),
                summary: String(localized: "\(bytes.formatted(.byteCount(style: .file))) you can free.", bundle: .module),
                affected: removed.map { .file(problems[$0].file) }, action: .cleanUp(problemIDs: removed.map { problems[$0].id }), indices: removed)
        }

        let stale = open { $0.kind == .staleFile }
        if !stale.isEmpty {
            let addons = stale.map { owner(ofFile: problems[$0].file) }
            // Files are written only at reload, logout, or quit: a character who hasn't played keeps the file old.
            let on = characters(for: addons).map(\.name)
            let certainty: HealthFinding.Certainty = context.companion?.enabledBy.isEmpty ?? true ? .likely : on.isEmpty ? .certain : .possible
            add(.unusedAddons, key: "all", certainty: certainty,
                title: String(localized: "Addons you haven't used lately", bundle: .module),
                impact: String(localized: "Moving their files to the Trash resets their settings if you turn them back on.", bundle: .module),
                summary: String(localized: "Not loaded on any character for \(SVFileProblems.staleDays) days or more.", bundle: .module),
                note: certainty == .possible ? String(localized: "Turned on for \(on.formatted(.list(type: .and))), who may not have played since.", bundle: .module) : nil,
                affected: addons.map { .addon(title(ofAddon: $0)) }, action: .cleanUp(problemIDs: stale.map { problems[$0].id }), indices: stale)
        }

        let copies = open { $0.kind == .copyFile || $0.kind == .strayItem }
        if !copies.isEmpty {
            let bytes = copies.reduce(Int64(0)) { $0 + problems[$1].bytes }
            add(.copiesAndStrays, key: "all", title: String(localized: "\(copies.count) copies and stray items", bundle: .module),
                impact: String(localized: "The game doesn't make or read them.", bundle: .module),
                summary: String(localized: "\(bytes.formatted(.byteCount(style: .file))) you can free.", bundle: .module),
                affected: copies.map { .file(problems[$0].file) }, action: .cleanUp(problemIDs: copies.map { problems[$0].id }), indices: copies)
        }
    }

    // MARK: 7. Per file

    mutating func perFileGroups() {
        for file in files(with: .typeMismatch) {
            let indices = open { $0.file == file && $0.kind == .typeMismatch }
            let addon = owner(ofFile: file)
            add(.mixedTypes, key: file, certainty: .likely,
                title: String(localized: "Some \(title(ofAddon: addon)) settings mix types", bundle: .module),
                impact: String(localized: "An addon that expects one type can fail on the other.", bundle: .module),
                summary: String(localized: "\(indices.count) settings", bundle: .module),
                affected: [.addon(title(ofAddon: addon)), .file(file)],
                action: .showInInspector(problemID: problems[indices[0]].id), indices: indices)
        }
        for file in files(with: .unknownVariable) {
            let indices = open { $0.file == file && $0.kind == .unknownVariable }
            let addon = owner(ofFile: file)
            add(.olderVersionLeftovers, key: file, tier: .info,
                title: String(localized: "\(title(ofAddon: addon)) keeps variables it no longer uses", bundle: .module),
                impact: String(localized: "Left by an older version; the game never loads them.", bundle: .module),
                affected: [.addon(title(ofAddon: addon)), .file(file)], action: nil, indices: indices)
        }
    }

    // MARK: 8. Stands alone

    /// Data for a character no file names, across every file that keeps it: one finding per character.
    mutating func unknownCharacters() {
        var ids: [String] = []
        for i in open(where: { $0.kind == .unknownCharacter }) {
            if let id = problems[i].character, !ids.contains(id) { ids.append(id) }
        }
        for id in ids {
            let indices = open { $0.kind == .unknownCharacter && $0.character == id }
            add(.unknownCharacter, key: id, certainty: .likely,
                title: String(localized: "Data for an unknown character (\(id))", bundle: .module),
                impact: String(localized: "No file names this character, so it's likely one you deleted. Addons still keep its data in \(String(localized: "\(indices.count) files", bundle: .module)).", bundle: .module),
                note: String(localized: "Or a character that hasn't logged in since your other files last saved its name.", bundle: .module),
                affected: indices.map { .file(problems[$0].file) }, action: .findCharacter(id: id), indices: indices,
                characters: [(id: id, name: SVName.unknownCharacter)])
        }
    }

    mutating func standAlone() {
        for i in open(where: { _ in true }) {
            let p = problems[i]
            let folder = p.addon
            let action: HealthFinding.Action?
            switch p.kind {
            case .didntLoad, .luaError, .outOfDateAddon:
                if let folder, context.updatable.contains(Self.key(folder)) { action = .update(folders: [folder]) }
                else if let folder { action = .showAddon(folder: folder) }
                else { action = .showInInspector(problemID: p.id) }
            case .longList, .typeMismatch, .missingVariable, .unreadable, .endsEarly:
                action = .showInInspector(problemID: p.id)
            case .unusedFile, .copyFile, .staleFile, .strayItem:
                action = .cleanUp(problemIDs: [p.id])
            case .largeFile, .slowLoad, .empty, .unknownSchema, .unknownVariable:
                action = nil
            case .unknownCharacter:
                action = p.character.map { .findCharacter(id: $0) }
            }
            let tier = action == nil ? HealthFinding.Tier.info : HealthFinding.Tier.of(p.kind)
            let affected: [HealthFinding.Subject] = folder.map { [.addon(title(ofAddon: $0))] } ?? [.file(p.file)]
            let on = tier == .broken ? folder.map { characters(for: [$0]) } ?? [] : []
            // The cause, not the check, when the game said which addon it is.
            let heading = switch (p.kind, folder) {
            case (.luaError, let folder?): String(localized: "\(title(ofAddon: folder)) throws Lua errors", bundle: .module)
            case (.didntLoad, let folder?): String(localized: "\(title(ofAddon: folder)) doesn't load", bundle: .module)
            case (.longList, _): String(localized: "\(title(ofAddon: owner(ofFile: p.file))) keeps a long list", bundle: .module)
            default: p.kind.title
            }
            add(.single, key: p.id, tier: tier, certainty: p.kind == .luaError && folder == nil ? .likely : .certain,
                title: heading, impact: p.message, affected: affected, action: action, indices: [i], characters: on)
        }
    }
}
