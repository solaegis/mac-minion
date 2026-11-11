import Foundation
import MacMinionKit

/// Every place one ID appears, grouped by file, with each place's key path found again.
nonisolated struct SVFindResult: Identifiable {
    let target: SVTarget
    let title: String
    let total: Int
    let files: [SVFindFile]
    var id: SVTarget { target }
    var shown: Int { files.reduce(0) { $0 + $1.rows.count } }
}

nonisolated struct SVFindFile: Identifiable {
    let file: String
    let rows: [SVFindRow]
    var id: String { file }
}

nonisolated struct SVFindRow: Identifiable, Hashable {
    let file: String
    let path: [LuaKey]
    let value: String
    let offset: Int32
    var id: String { "\(file)#\(offset)" }
}

/// Find: every place an ID appears across SavedVariables.
extension GameFolderModel {
    /// Most places shown per ID, and in all, so a guild with thousands of sales stays quick.
    nonisolated static let findRowsPerTarget = 500
    nonisolated static let findRowsInAll = 3_000

    /// Finds every place IDs whose ID or name matches `query` appear, across all SavedVariables.
    func find(_ query: String) async {
        await load()
        guard let refs = references, let names = names else { return }
        await showFind(refs.targets(matching: query, names: names), query: query)
    }

    /// Finds every place the selected row's ID appears (its key, or else its value).
    func findEverywhere(_ node: SVNode? = nil) async {
        guard let node = node ?? inspectorSelectedNode, let names = names else { return }
        let target = SVTarget.of(key: node.key, at: node.parentPath)
            ?? SVTarget.of(value: node.value, key: node.key, at: node.parentPath, names: names)
        guard let target else { return }
        inspectorQuery = names.title(for: target) ?? target.id
        await showFind([target], query: inspectorQuery)
    }

    /// Finds every place one ID appears: a character or account from the Space tab.
    func findEverywhere(_ target: SVTarget) async {
        await load()
        tab = .inspector
        inspectorQuery = names?.title(for: target) ?? target.id
        await showFind([target], query: inspectorQuery)
    }

    private func showFind(_ targets: [SVTarget], query: String) async {
        inspectorBusy = true
        defer { inspectorBusy = false }
        inspectorResults = await findResults(targets)
        inspectorFindMessage = inspectorResults?.isEmpty == true ? String(localized: "Nothing in SavedVariables matches “\(query)”.") : nil
    }

    /// Every place each target appears, with key paths found again; the window and `macminion sv find` share it.
    func findResults(_ targets: [SVTarget], perTarget: Int = GameFolderModel.findRowsPerTarget) async -> [SVFindResult] {
        guard let refs = references, let names = names else { return [] }
        let folder = app.gameFolderURL.appending(path: "SavedVariables")
        let cache = documents
        return await Task.detached {
            var budget = GameFolderModel.findRowsInAll
            return targets.map { target -> SVFindResult in
                let hits = refs.hits[target] ?? []
                var byFile: [String: [SVFindRow]] = [:]
                for hit in hits.prefix(min(perTarget, max(budget, 0))) {
                    let file = refs.files[Int(hit.file)]
                    guard let doc = cache.document(named: file, at: folder.appending(path: file)),
                          let found = doc.entry(at: Int(hit.offset)) else { continue }
                    byFile[file, default: []].append(SVFindRow(file: file, path: found.path,
                                                                value: InspectorValue.preview(found.entry.value), offset: hit.offset))
                    budget -= 1
                }
                let title = names.title(for: target).map { "\($0) · \(target.kind.rawValue)" } ?? target.description
                return SVFindResult(target: target, title: title, total: hits.count,
                                    files: byFile.sorted { $0.key < $1.key }.map { SVFindFile(file: $0.key, rows: $0.value) })
            }
        }.value
    }

    /// Opens the file a result is in, shows the table around it, and selects it.
    func reveal(_ row: SVFindRow) async {
        if inspectorFile != row.file { await inspect(row.file) }
        inspectorResults = nil
        inspectorFocus = Array(row.path.dropLast())
        inspectorSelection = SVNode(entry: .placeholder(row.path.last!), parentPath: inspectorFocus).id
    }

    func clearFind() {
        inspectorConnections = nil
        inspectorResults = nil
        inspectorFindMessage = nil
        inspectorQuery = ""
    }
}
