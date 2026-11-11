import AppKit
import MacMinionKit

/// The file open in the Inspector and where the Inspector is in it.
extension GameFolderModel {
    /// Opens a SavedVariables file in the Inspector, and names IDs from every file and the installed libraries.
    func inspect(_ fileName: String) async {
        tab = .inspector
        guard let url = savedVariables.first(where: { $0.name == fileName })?.url else { return }
        inspectorBusy = true
        defer { inspectorBusy = false }
        let cache = documents
        let (data, doc) = await Task.detached { () -> (Data, SVDocument) in
            let data = (try? Data(contentsOf: url)) ?? Data()
            let stamp = SVDocumentCache.Stamp(url: url)
            if let cached = cache.get(fileName, stamp: stamp) {
                return (data, cached)
            }
            let doc = SVDocument.parse(data)
            cache.put(fileName, stamp: stamp, document: doc)
            return (data, doc)
        }.value
        documents.pin(fileName)
        inspectorFile = fileName
        inspectorData = data
        inspectorDocument = doc
        inspectorFocus = []
        inspectorSelection = nil
        inspectorRoots = SVNode.roots(doc)
        await loadSourceNames(for: fileName)
        await load()
    }

    /// Finds a row by its ID among the rows on screen and the ones opened under them.
    func inspectorNode(_ id: SVNode.ID?) -> SVNode? { inspectorCursor.node(id) }

    var inspectorSelectedNode: SVNode? { inspectorNode(inspectorSelection) }

    /// Shows only the selected table's entries, like opening a folder.
    func inspectorOpen(_ node: SVNode? = nil) {
        guard let node = node ?? inspectorSelectedNode, inspectorCursor.open(node) else { return }
        inspectorSelection = nil
    }

    /// Goes up to the table around the one shown, selecting the one that was open.
    func inspectorEnclosing() {
        guard let left = inspectorCursor.enclosing() else { return }
        inspectorSelection = left
    }

    func inspectorName(_ node: SVNode) -> SVName? {
        guard let names = names else { return nil }
        return names.name(forKey: node.key, at: node.parentPath)
            ?? names.name(forValue: node.value, key: node.key, at: node.parentPath)
    }

    /// The entry as written in the file, up to a limit.
    func inspectorRawText(_ node: SVNode, limit: Int = 200_000) -> String {
        let span = node.span.clamped(to: 0..<inspectorData.count)
        let shown = span.prefix(limit)
        let text = String(decoding: inspectorData[shown], as: UTF8.self)
        return span.count > limit ? text + "\n… \((span.count - limit).formatted(.byteCount(style: .file))) more" : text
    }

    func copyInspectorPath() {
        guard let node = inspectorSelectedNode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path.luaPath, forType: .string)
    }

    func copyInspectorValue() {
        guard let node = inspectorSelectedNode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(InspectorValue.plain(node.value) ?? inspectorRawText(node, limit: .max), forType: .string)
    }

    func lookUpOnUESP() {
        guard let node = inspectorSelectedNode, let url = inspectorName(node)?.uesp else { return }
        NSWorkspace.shared.open(url)
    }

    /// The inspected SavedVariables file, for Inspector > Open in Editor.
    var inspectorFileURL: URL? { savedVariables.first { $0.name == inspectorFile }?.url }

    /// Opens a file in the Inspector, shows the table around `path`, and selects it.
    func reveal(file: String, path: [LuaKey]) async {
        await inspect(file)
        guard let last = path.last else { return }
        inspectorFocus = Array(path.dropLast())
        inspectorSelection = SVNode(entry: .placeholder(last), parentPath: inspectorFocus).id
    }
}
