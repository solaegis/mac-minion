import Foundation

/// The SavedVariables graph, phases A–C of docs/research/sv-graph-model-findings.md: identity
/// (accounts, megaservers, characters), the addon side (addons, their globals, dependencies), and the
/// scopes where the two meet. Every edge carries where it came from and how sure it is. Values inside
/// scopes aren't nodes: the Inspector opens them from the file and path in the provenance.
public struct SVGraph: Sendable {
    public enum NodeKind: String, Sendable, CaseIterable {
        case account, megaserver, profile, character, addon, svGlobal, scope
    }

    public struct NodeID: Hashable, Sendable, CustomStringConvertible {
        public let kind: NodeKind
        public let key: String
        public init(_ kind: NodeKind, _ key: String) { self.kind = kind; self.key = key }
        public var description: String { "\(kind.rawValue):\(key)" }
    }

    public enum EdgeKind: String, Sendable, CaseIterable {
        /// Account → Character.
        case owns
        /// Character → Megaserver.
        case onServer
        /// Addon → SVGlobal, from `## SavedVariables:`.
        case declares
        /// Addon → Addon, from `## DependsOn:` and `## OptionalDependsOn:`.
        case dependsOn
        /// SVGlobal → Profile.
        case profiles
        /// Profile → Scope.
        case contains
        /// Scope → Character or Account: whose data the scope holds.
        case scopeOwner
        /// Character → Addon: on for that character at its last login (the companion's `enabledBy`).
        case enabledFor
        /// Character → Addon: the character owns a scope in one of the addon's globals.
        case hasDataIn

        /// The edges that form the two ownership trees, which must never cycle.
        public static let ownership: Set<EdgeKind> = [.owns, .declares, .profiles, .contains, .scopeOwner]
    }

    public enum Confidence: Int, Sendable, Comparable {
        case provisional, low, medium, high
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Edge: Hashable, Sendable {
        public let from: NodeID
        public let kind: EdgeKind
        public let to: NodeID
    }

    /// Where an edge came from: a file and key path when it was read from SavedVariables, and the rule.
    public struct Provenance: Hashable, Sendable {
        public let file: String?
        public let path: [String]
        /// `zo-scope`, `R1`, `R2`, `R3`, `R5`, `companion`, `manifest`, `name-unique`, `name-ambiguous`, `derived`.
        public let rule: String
        public let confidence: Confidence
    }

    /// Attributes per node: `name`, `pseudo`, `orphan`, `ambiguous`, `scopeKind`, …
    public private(set) var nodes: [NodeID: [String: String]] = [:]
    public private(set) var out: [NodeID: [EdgeKind: Set<NodeID>]] = [:]
    public private(set) var into: [NodeID: [EdgeKind: Set<NodeID>]] = [:]
    public private(set) var provenance: [Edge: [Provenance]] = [:]

    public init() {}

    // MARK: Building

    mutating func node(_ id: NodeID, _ attrs: [String: String] = [:]) {
        nodes[id, default: [:]].merge(attrs) { _, new in new }
    }

    mutating func link(_ from: NodeID, _ kind: EdgeKind, _ to: NodeID, _ prov: Provenance) {
        node(from)
        node(to)
        out[from, default: [:]][kind, default: []].insert(to)
        into[to, default: [:]][kind, default: []].insert(from)
        let edge = Edge(from: from, kind: kind, to: to)
        if !(provenance[edge]?.contains(prov) ?? false) { provenance[edge, default: []].append(prov) }
    }

    mutating func unlink(_ from: NodeID, _ kind: EdgeKind, _ to: NodeID) {
        out[from]?[kind]?.remove(to)
        into[to]?[kind]?.remove(from)
        provenance[Edge(from: from, kind: kind, to: to)] = nil
    }

    /// What the graph is built from: what each SavedVariables file holds, the installed manifests, and the
    /// names and homes the folder read already worked out. The companion snapshot is optional.
    public struct Input {
        /// File name -> its globals and scopes.
        public var parts: [String: FilePart]
        /// Lowercased folder name -> the addon's name, its declared globals, and its dependencies.
        public var addons: [String: (addon: String, variables: [String], dependsOn: [String])]
        public var names: SVNameIndex
        public var homes: [String: SettingsMatrix.Home]
        public var snapshot: CompanionSnapshot?

        public init(parts: [String: FilePart], addons: [String: (addon: String, variables: [String], dependsOn: [String])],
                    names: SVNameIndex, homes: [String: SettingsMatrix.Home], snapshot: CompanionSnapshot?) {
            self.parts = parts; self.addons = addons; self.names = names; self.homes = homes; self.snapshot = snapshot
        }

        public init(documents: [String: SVDocument], addons: [String: (addon: String, variables: [String], dependsOn: [String])],
                    names: SVNameIndex, homes: [String: SettingsMatrix.Home], snapshot: CompanionSnapshot?) {
            self.init(parts: documents.mapValues(FilePart.init(document:)), addons: addons, names: names, homes: homes, snapshot: snapshot)
        }
    }

    /// What the graph needs from one file, small enough to keep for every file while its tree is dropped.
    public struct FilePart: Sendable, Equatable {
        /// Top-level variable names.
        let globals: [String]
        let scopes: [ScopeRecord]

        public init(document: SVDocument) {
            globals = document.variables.compactMap { if case .string(let name) = $0.key { name } else { nil } }
            scopes = SVGraph.scopes(file: "", document: document)
        }
    }

    /// One ZO_SavedVars scope: `Var[profile][account][key]`.
    struct ScopeRecord: Sendable, Equatable {
        let file: String
        let global: String
        let profile: String
        let account: String
        let key: String
        let level: SVLevel
    }

    static func scopes(file: String, document: SVDocument) -> [ScopeRecord] {
        var found: [ScopeRecord] = []
        for variable in document.variables {
            guard case .string(let global) = variable.key else { continue }
            for profile in variable.value.table?.entries ?? [] {
                guard SVLevel.of(profile.key, at: [variable.key]) == .profile, case .string(let p) = profile.key else { continue }
                for account in profile.value.table?.entries ?? [] {
                    guard case .string(let a) = account.key, account.value.table != nil else { continue }
                    for scope in account.value.table?.entries ?? [] {
                        guard case .string(let k) = scope.key, scope.value.table != nil,
                              let level = SVLevel.of(scope.key, at: [variable.key, profile.key, account.key]) else { continue }
                        found.append(ScopeRecord(file: file, global: global, profile: p, account: a, key: k, level: level))
                    }
                }
            }
        }
        return found
    }

    public static func build(_ input: Input) -> SVGraph {
        var g = SVGraph()

        // Addon side: addons, their globals, dependencies.
        var globalOwner: [String: NodeID] = [:]
        var addonByName: [String: NodeID] = [:]
        for (_, decl) in input.addons {
            let addon = NodeID(.addon, decl.addon)
            g.node(addon, ["name": decl.addon])
            addonByName[decl.addon] = addon
            for variable in decl.variables {
                let global = NodeID(.svGlobal, variable)
                g.node(global, ["declared": "true"])
                g.link(addon, .declares, global, Provenance(file: nil, path: [], rule: "manifest", confidence: .high))
                globalOwner[variable] = addon
            }
        }
        for (_, decl) in input.addons {
            for dep in decl.dependsOn {
                let name = String(dep.prefix { $0 != ">" && $0 != "<" && $0 != "=" })
                guard !name.isEmpty else { continue }
                let target = addonByName[name] ?? NodeID(.addon, name)
                if addonByName[name] == nil { g.node(target, ["name": name, "missing": "true"]) }
                g.link(NodeID(.addon, decl.addon), .dependsOn, target, Provenance(file: nil, path: [], rule: "manifest", confidence: .high))
            }
        }

        // Globals present in files, with an owner even when no installed manifest declares them.
        for (file, part) in input.parts {
            for name in part.globals {
                let global = NodeID(.svGlobal, name)
                g.node(global, ["present": "true", "file": file])
                if globalOwner[name] == nil {
                    let owner = name.hasPrefix("ZO_") ? NodeID(.addon, "game") : NodeID(.addon, "missing")
                    g.node(owner, ["name": owner.key, "synthetic": "true"])
                    g.node(global, ["orphan": name.hasPrefix("ZO_") ? "false" : "true"])
                    g.link(owner, .declares, global, Provenance(file: file, path: [name], rule: "no-manifest", confidence: .high))
                }
            }
        }

        // Characters by ID, from every source that names one.
        func addCharacter(_ id: String) -> NodeID {
            let c = NodeID(.character, id)
            if g.nodes[c] == nil {
                var attrs: [String: String] = [:]
                if let name = input.names.characters[id]?.name { attrs["name"] = name }
                g.node(c, attrs)
            }
            return c
        }
        func place(_ id: String, account: String, server: String?, prov: Provenance) {
            let c = addCharacter(id)
            g.node(NodeID(.account, account), ["pseudo": account.hasPrefix("@") ? "false" : "true"])
            g.link(NodeID(.account, account), .owns, c, prov)
            if let server {
                g.node(NodeID(.megaserver, server))
                g.link(c, .onServer, NodeID(.megaserver, server), prov)
            }
        }

        // The companion's roster is the game's own list: highest confidence.
        for (id, c) in input.snapshot?.characters ?? [:] {
            place(id, account: c.account, server: SVLevel.megaserver(ofProfile: c.server) ?? c.server,
                  prov: Provenance(file: input.snapshot?.file, path: ["characters", id], rule: "companion", confidence: .high))
            if !c.previousNames.isEmpty { g.node(NodeID(.character, id), ["previousNames": c.previousNames.joined(separator: ", ")]) }
        }
        for (id, home) in input.homes {
            let server = SVLevel.megaserver(ofProfile: home.server)
            place(id, account: home.account, server: server,
                  prov: Provenance(file: nil, path: [], rule: server == nil ? "zo-scope" : "R1-R3", confidence: .high))
        }

        /// A character's megaserver: the companion's roster, a real home, else the ID prefix (provisional).
        func megaserverOf(_ id: String) -> String? {
            if let c = input.snapshot?.characters[id] { return SVLevel.megaserver(ofProfile: c.server) ?? c.server }
            if let home = input.homes[id], let real = SVLevel.megaserver(ofProfile: home.server) { return real }
            return prefixMegaserver(id)
        }

        // Scopes, and who owns each.
        var scopeRecords: [ScopeRecord] = []
        for (file, part) in input.parts {
            scopeRecords += part.scopes.map { ScopeRecord(file: file, global: $0.global, profile: $0.profile, account: $0.account, key: $0.key, level: $0.level) }
        }
        var byName: [String: [String]] = [:]
        for (id, c) in input.names.characters { byName[c.name, default: []].append(id) }

        for r in scopeRecords {
            let global = NodeID(.svGlobal, r.global)
            let profile = NodeID(.profile, "\(r.global)|\(r.profile)")
            let scope = NodeID(.scope, "\(r.global)|\(r.profile)|\(r.account)|\(r.key)")
            let prov = Provenance(file: r.file, path: [r.global, r.profile, r.account, r.key], rule: "zo-scope", confidence: .high)
            g.node(profile, ["name": r.profile])
            g.node(scope, ["scopeKind": r.level.rawValue, "file": r.file])
            g.link(global, .profiles, profile, prov)
            g.link(profile, .contains, scope, prov)
            let account = NodeID(.account, r.account)
            g.node(account, ["pseudo": r.account.hasPrefix("@") ? "false" : "true"])
            let megaserver = SVLevel.megaserver(ofProfile: r.profile)

            switch r.level {
            case .accountWide:
                g.link(scope, .scopeOwner, account, prov)
            case .character where CharacterID.isID(r.key):
                let c = addCharacter(r.key)
                g.link(scope, .scopeOwner, c, prov)
                if g.into[c]?[.owns]?.isEmpty ?? true { g.link(account, .owns, c, prov) }
            case .character, .characterName:
                let name = String(r.key.split(separator: "^").first ?? Substring(r.key))
                let candidates = (byName[name] ?? []).filter { id in
                    let home = input.homes[id]
                    let sameAccount = home == nil || home?.account == r.account
                    let theirs = megaserverOf(id)
                    let sameServer = megaserver == nil || theirs == nil || theirs == megaserver
                    return sameAccount && sameServer
                }
                if candidates.count == 1 {
                    g.link(scope, .scopeOwner, addCharacter(candidates[0]),
                           Provenance(file: r.file, path: prov.path, rule: "name-unique", confidence: .medium))
                } else if candidates.isEmpty {
                    let orphan = NodeID(.character, "name:\(r.account):\(name)")
                    g.node(orphan, ["name": name, "orphan": "true"])
                    g.link(account, .owns, orphan, Provenance(file: r.file, path: prov.path, rule: "name-only", confidence: .low))
                    g.link(scope, .scopeOwner, orphan, Provenance(file: r.file, path: prov.path, rule: "name-only", confidence: .low))
                } else {
                    g.node(scope, ["ambiguous": "true"])
                    for id in candidates {
                        g.link(scope, .scopeOwner, addCharacter(id),
                               Provenance(file: r.file, path: prov.path, rule: "name-ambiguous", confidence: .low))
                    }
                }
            default:
                break
            }
        }

        // Last resort for a character with no megaserver: the ID prefix. Provisional (38/38 on 2 accounts).
        for id in Array(g.nodes.keys) where id.kind == .character && !id.key.hasPrefix("name:") {
            guard g.out[id]?[.onServer]?.isEmpty ?? true else { continue }
            if let server = prefixMegaserver(id.key) {
                g.link(id, .onServer, NodeID(.megaserver, server), Provenance(file: nil, path: [], rule: "R5", confidence: .provisional))
            }
        }

        // Character ↔ Addon.
        for edge in scopeRecords {
            let scope = NodeID(.scope, "\(edge.global)|\(edge.profile)|\(edge.account)|\(edge.key)")
            guard let owner = globalOwner[edge.global] else { continue }
            for c in g.out[scope]?[.scopeOwner] ?? [] where c.kind == .character {
                g.link(c, .hasDataIn, owner, Provenance(file: edge.file, path: [edge.global, edge.profile, edge.account, edge.key],
                                                         rule: "derived", confidence: .high))
            }
        }
        if let snap = input.snapshot {
            for (id, row) in snap.enabledBy {
                let c = addCharacter(id)
                let off = Set(row.disabled)
                for name in snap.addons.keys where !off.contains(name) {
                    let addon = addonByName[name] ?? NodeID(.addon, name)
                    g.link(c, .enabledFor, addon, Provenance(file: snap.file, path: ["enabledBy", id], rule: "companion", confidence: .high))
                }
            }
        }
        return g
    }

    /// The megaserver a character ID's prefix suggests. Provisional: it held for 38 of 38 IDs on 2 accounts.
    static func prefixMegaserver(_ id: String) -> String? {
        id.hasPrefix("8796093") ? "NA Megaserver" : id.hasPrefix("8798292") ? "EU Megaserver" : nil
    }

    // MARK: Traversal

    /// Every path from `node` up to a root, following ownership edges backwards. Ownership is a DAG, so
    /// this ends; ambiguous scopes give one path per candidate.
    public func up(from node: NodeID) -> [[NodeID]] {
        // Parents along owns, declares, profiles, and contains. A scope also has its owner (identity side),
        // reached forwards along scopeOwner.
        let parents = EdgeKind.ownership.subtracting([.scopeOwner]).flatMap { into[node]?[$0] ?? [] }
        let owners = node.kind == .scope ? Array(out[node]?[.scopeOwner] ?? []) : []
        let next = (parents + owners).sorted { $0.description < $1.description }
        if next.isEmpty { return [[node]] }
        var paths: [[NodeID]] = []
        for parent in next where parent != node {
            for path in up(from: parent) { paths.append([node] + path) }
        }
        return paths
    }

    /// Nodes reached from `node` along `via`, breadth first, at most `limit`.
    public func down(from node: NodeID, via: Set<EdgeKind> = EdgeKind.ownership, limit: Int = 200) -> [NodeID] {
        var seen: Set<NodeID> = [node], queue = [node], found: [NodeID] = []
        while !queue.isEmpty, found.count < limit {
            let here = queue.removeFirst()
            var next: [NodeID] = []
            for kind in via where kind != .scopeOwner { next += out[here]?[kind] ?? [] }
            // Down from a character or account goes to the scopes it owns.
            if via.contains(.scopeOwner), here.kind == .character || here.kind == .account { next += into[here]?[.scopeOwner] ?? [] }
            for n in next.sorted(by: { $0.description < $1.description }) where !seen.contains(n) {
                seen.insert(n); queue.append(n); found.append(n)
                if found.count >= limit { break }
            }
        }
        return found
    }

    /// The addons a character is tied to, and how: enabled, has data, or both.
    public func addons(for character: String) -> [(addon: NodeID, why: Set<EdgeKind>)] {
        let c = NodeID(.character, character)
        var why: [NodeID: Set<EdgeKind>] = [:]
        for kind in [EdgeKind.enabledFor, .hasDataIn] { for a in out[c]?[kind] ?? [] { why[a, default: []].insert(kind) } }
        return why.map { (addon: $0.key, why: $0.value) }
            .sorted { $0.addon.key.localizedStandardCompare($1.addon.key) == .orderedAscending }
    }

    /// The characters tied to an addon, and how.
    public func characters(for addon: String) -> [(character: NodeID, why: Set<EdgeKind>)] {
        let a = NodeID(.addon, addon)
        var why: [NodeID: Set<EdgeKind>] = [:]
        for kind in [EdgeKind.enabledFor, .hasDataIn] { for c in into[a]?[kind] ?? [] { why[c, default: []].insert(kind) } }
        return why.map { (character: $0.key, why: $0.value) }.sorted { $0.character.key < $1.character.key }
    }

    /// Characters known only by a name, scopes with more than one candidate owner, and globals no
    /// installed addon declares.
    public func orphans() -> [NodeID] {
        nodes.filter { $0.value["orphan"] == "true" || $0.value["ambiguous"] == "true" }.keys.sorted { $0.description < $1.description }
    }

    public func explain(_ from: NodeID, _ kind: EdgeKind, _ to: NodeID) -> [Provenance] {
        provenance[Edge(from: from, kind: kind, to: to)] ?? []
    }

    /// True when the ownership edges have no cycle. Checked by tests; a cycle there is a bug.
    public var ownershipIsAcyclic: Bool {
        var state: [NodeID: Int] = [:] // 1 visiting, 2 done
        func visit(_ n: NodeID) -> Bool {
            if state[n] == 2 { return true }
            if state[n] == 1 { return false }
            state[n] = 1
            for kind in EdgeKind.ownership where kind != .scopeOwner {
                for m in out[n]?[kind] ?? [] where !visit(m) { return false }
            }
            state[n] = 2
            return true
        }
        return nodes.keys.allSatisfy(visit)
    }
}
