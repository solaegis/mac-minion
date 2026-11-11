import Foundation
import MacMinionKit

/// The connections map: what mentions an ID and what is stored with it (S-051).
extension GameFolderModel {
    /// Shows the connections map for an ID: what mentions it and what's stored with it (S-051).
    func showConnections(_ target: SVTarget, remember: Bool = true) async {
        await load()
        guard let refs = references, let names = names else { return }
        tab = .inspector
        inspectorResults = nil
        if remember, let current = inspectorConnections?.target, current != target { connectionsBack.append(current) }
        let folder = app.gameFolderURL.appending(path: "SavedVariables")
        let cache = documents
        inspectorBusy = true
        defer { inspectorBusy = false }
        inspectorConnections = await Task.detached {
            SVNeighborhood.build(target, refs: refs, names: names) {
                cache.document(named: $0, at: folder.appending(path: $0))
            }
        }.value
    }

    /// The ID a row stands for, by its key or its value.
    func target(of node: SVNode) -> SVTarget? {
        SVTarget.of(key: node.key, at: node.parentPath)
            ?? names.flatMap { SVTarget.of(value: node.value, key: node.key, at: node.parentPath, names: $0) }
    }

    func connectionsGoBack() async {
        guard let previous = connectionsBack.popLast() else { return }
        await showConnections(previous, remember: false)
    }

    func closeConnections() {
        inspectorConnections = nil
        connectionsBack = []
    }

    /// Opens the first place a file mentions the target, in the tree.
    func revealFirst(_ target: SVTarget, in file: String) async {
        let rows = await findResults([target], perTarget: 50).first?.files.first { $0.file == file }?.rows ?? []
        guard let row = rows.min(by: { $0.path.count < $1.path.count }) else { await inspect(file); return }
        closeConnections()
        inspectorReadable = false
        await reveal(file: file, path: row.path)
    }

    func connectionTitle(_ target: SVTarget) -> String {
        if let title = names?.title(for: target) { return title }
        switch target.kind {
        case .character, .account, .guild: return target.id
        default: return "\(target.kind.rawValue.prefix(1).uppercased())\(target.kind.rawValue.dropFirst()) \(target.id)"
        }
    }
}
