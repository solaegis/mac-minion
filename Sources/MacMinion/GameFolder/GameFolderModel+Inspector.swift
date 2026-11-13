import AppKit
import MacMinionKit

/// The file open in the Inspector and where the Inspector is in it.
extension GameFolderModel {
    /// Opens a SavedVariables file in the Inspector, and names IDs from every file and the installed libraries.
    func inspect(_ fileName: String) async {
        tab = .inspector
        guard let url = savedVariables.first(where: { $0.name == fileName })?.url else { return }
        // Drop any enrich from the last file before yielding, so its status cannot outlive this open.
        inspectorEnrichTask?.cancel()
        inspectorEnrichTask = nil
        inspectorStatus = nil
        // Finish any in-flight List/Table delegate before flipping pending/file selection state.
        await Task.yield()
        inspectGeneration += 1
        let generation = inspectGeneration
        inspectorOpenGeneration += 1
        inspectorOpeningTable = false
        inspectorBusy = true
        inspectorPendingFile = fileName
        let cache = documents
        // Cache hit: skip reading bytes until Show Raw needs them. Miss: read once and parse.
        let loaded = await Task.detached { () -> (data: Data, doc: SVDocument, needsBytes: Bool)? in
            let stamp = SVDocumentCache.Stamp(url: url)
            if let cached = cache.get(fileName, stamp: stamp) {
                return (Data(), cached, true)
            }
            let data = (try? Data(contentsOf: url)) ?? Data()
            let doc = SVDocument.parse(data)
            cache.put(fileName, stamp: stamp, document: doc)
            return (data, doc, false)
        }.value
        guard generation == inspectGeneration, let loaded else {
            if generation == inspectGeneration { inspectorBusy = false; inspectorPendingFile = nil }
            return
        }
        documents.pin(fileName)
        inspectorFile = fileName
        inspectorData = loaded.data
        inspectorDataNeedsLoad = loaded.needsBytes
        inspectorDocument = loaded.doc
        inspectorFocus = []
        inspectorSelection = nil
        inspectorRoots = SVNode.roots(loaded.doc)
        // Paint the file now; source names and the folder index enrich in the background.
        inspectorBusy = false
        inspectorPendingFile = nil
        inspectorEnrichTask?.cancel()
        inspectorEnrichTask = Task {
            await enrichInspector(generation: generation, file: fileName)
        }
    }

    /// Source names and the folder name index for the open file. Safe to call again from tests.
    func awaitInspectorEnrichment() async {
        if let task = inspectorEnrichTask {
            await task.value
        } else if let file = inspectorFile {
            await enrichInspector(generation: inspectGeneration, file: file)
        }
        // A cancelled enrich from an earlier file must not leave its caption stuck.
        if progress == nil { inspectorStatus = nil }
    }

    private func enrichInspector(generation: Int, file: String) async {
        guard generation == inspectGeneration, !Task.isCancelled else { return }
        await loadSourceNames(for: file, generation: generation)
        guard generation == inspectGeneration, !Task.isCancelled else { return }
        await load()
    }

    /// Loads file bytes when Copy Value needs them after a cache-hit inspect.
    func ensureInspectorData() {
        guard inspectorDataNeedsLoad, let url = inspectorFileURL else { return }
        inspectorData = (try? Data(contentsOf: url)) ?? Data()
        inspectorDataNeedsLoad = false
    }

    /// The entry as written in the file, for Show Raw: reads the file's bytes off the main thread first.
    func loadInspectorRawText(_ node: SVNode) async -> String {
        if inspectorDataNeedsLoad, let url = inspectorFileURL {
            let generation = inspectGeneration
            let data = await Task.detached { (try? Data(contentsOf: url)) ?? Data() }.value
            if generation == inspectGeneration, inspectorDataNeedsLoad {
                inspectorData = data
                inspectorDataNeedsLoad = false
            }
        }
        return inspectorRawText(node)
    }

    /// What the Inspector is doing, in words; nil when it is idle.
    var inspectorActivity: String? {
        if let pending = inspectorPendingFile { return String(localized: "Opening \(String(pending.dropLast(4)))…") }
        if inspectorOpeningTable { return String(localized: "Opening table…") }
        if let inspectorStatus { return inspectorStatus }
        // The read of every file, which names the IDs in this one.
        if inspectorFile != nil, let progress { return progress.step }
        return nil
    }

    /// Says what a piece of background work is doing until it ends, unless newer work took the line.
    func withInspectorStatus<T>(_ text: String, _ work: () async -> T) async -> T {
        inspectorStatus = text
        defer { if inspectorStatus == text { inspectorStatus = nil } }
        return await work()
    }

    /// Finds a row by its ID among the rows on screen and the ones opened under them.
    func inspectorNode(_ id: SVNode.ID?) -> SVNode? { inspectorCursor.node(id) }

    var inspectorSelectedNode: SVNode? { inspectorNode(inspectorSelection) }

    /// Shows only the selected table's entries, like opening a folder.
    /// Large tables sort off the main thread; small ones open at once.
    func inspectorOpen(_ node: SVNode? = nil) {
        guard let node = node ?? inspectorSelectedNode, node.value.table != nil else { return }
        let count = node.value.table?.count ?? 0
        if node.childrenReady || count < SVNode.asyncChildrenThreshold {
            _ = node.children
            applyInspectorOpen(node)
            return
        }
        Task { await openLargeInspectorTable(node) }
    }

    private func applyInspectorOpen(_ node: SVNode) {
        var next = inspectorCursor
        guard next.open(node) else { return }
        inspectorCursor = next
        inspectorSelection = nil
    }

    /// Sorts a wide table off the main thread, with the Opening placeholder until it is ready.
    private func openLargeInspectorTable(_ node: SVNode) async {
        inspectorOpenGeneration += 1
        let generation = inspectorOpenGeneration
        let path = node.path
        let table = node.value.table!
        inspectorOpeningTable = true
        defer {
            if generation == inspectorOpenGeneration { inspectorOpeningTable = false }
        }
        // Sort off the main thread (entries are Sendable); build SVNodes on return.
        let sorted = await Task.detached {
            table.entries.sorted { LuaKey.displayOrder($0.key, $1.key) }
        }.value
        guard generation == inspectorOpenGeneration, inspectorFile != nil else { return }
        let kids = sorted.map { SVNode(entry: $0, parentPath: path) }
        // The selected row is the same object the cursor holds; install there so refresh skips the sort.
        if let live = inspectorNode(node.id) {
            live.installChildren(kids)
            applyInspectorOpen(live)
        } else {
            node.installChildren(kids)
            applyInspectorOpen(node)
        }
    }

    /// Goes up to the table around the one shown, selecting the one that was open.
    func inspectorEnclosing() {
        var next = inspectorCursor
        guard let left = next.enclosing() else { return }
        inspectorCursor = next
        inspectorSelection = left
    }

    func inspectorName(_ node: SVNode) -> SVName? {
        guard let names = names else { return nil }
        return names.name(forKey: node.key, at: node.parentPath)
            ?? names.name(forValue: node.value, key: node.key, at: node.parentPath)
    }

    /// The entry as written in the file, up to a limit.
    func inspectorRawText(_ node: SVNode, limit: Int = 200_000) -> String {
        ensureInspectorData()
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
