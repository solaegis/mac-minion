import Foundation

/// Last few parsed SavedVariables trees for Find, Connections, and the Inspector.
///
/// The folder read (`SVFolderRead`) drops trees on purpose. Interactive lookups need them again
/// (`SVDocument.entry(at:)`), so this keeps a small stamped LRU instead of re-parsing on every query.
public final class SVDocumentCache: @unchecked Sendable {
    public struct Stamp: Equatable, Sendable {
        public let size: Int
        public let modified: Date?

        public init(size: Int, modified: Date?) {
            self.size = size
            self.modified = modified
        }

        /// Size and modification date of `url` as it is now.
        public init(url: URL) {
            var url = url
            url.removeAllCachedResourceValues()
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            self.size = values?.fileSize ?? -1
            self.modified = values?.contentModificationDate
        }
    }

    public let capacity: Int

    private let lock = NSLock()
    /// Oldest at the front, newest at the back.
    private var order: [String] = []
    private var entries: [String: (stamp: Stamp, document: SVDocument)] = [:]
    /// The Inspector's open file: never LRU-evicted while pinned.
    private var pinned: String?

    public init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    /// Cached document when `file` and `stamp` match; otherwise reads `url`, stores it, and returns it.
    public func document(named file: String, at url: URL, stamp: Stamp) -> SVDocument? {
        if let hit = get(file, stamp: stamp) { return hit }
        guard let doc = try? SVDocument.read(url) else { return nil }
        put(file, stamp: stamp, document: doc)
        return doc
    }

    /// Same as `document(named:at:stamp:)`, stamping from `url`'s size and date.
    public func document(named file: String, at url: URL) -> SVDocument? {
        document(named: file, at: url, stamp: Stamp(url: url))
    }

    public func get(_ file: String) -> SVDocument? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[file] else { return nil }
        touchLocked(file)
        return entry.document
    }

    /// Hit only when the stored stamp still matches.
    public func get(_ file: String, stamp: Stamp) -> SVDocument? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[file], entry.stamp == stamp else { return nil }
        touchLocked(file)
        return entry.document
    }

    public func put(_ file: String, stamp: Stamp, document: SVDocument) {
        lock.lock()
        defer { lock.unlock() }
        entries[file] = (stamp, document)
        touchLocked(file)
        evictLocked()
    }

    public func remove(_ file: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: file)
        order.removeAll { $0 == file }
        if pinned == file { pinned = nil }
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
        pinned = nil
    }

    /// Drops entries whose stamp no longer matches, and files that are gone from `stamps`.
    public func retain(matching stamps: [String: Stamp]) {
        lock.lock()
        defer { lock.unlock() }
        for file in Array(entries.keys) {
            guard let want = stamps[file], entries[file]?.stamp == want else {
                entries.removeValue(forKey: file)
                order.removeAll { $0 == file }
                if pinned == file { pinned = nil }
                continue
            }
        }
    }

    /// Keeps `file` from LRU eviction while it is the Inspector's open document. Pass `nil` to clear.
    public func pin(_ file: String?) {
        lock.lock()
        defer { lock.unlock() }
        pinned = file
        if let file, entries[file] != nil { touchLocked(file) }
        evictLocked()
    }

    public func unpin() {
        pin(nil)
    }

    /// Names currently held, oldest first. For tests.
    public var files: [String] {
        lock.lock()
        defer { lock.unlock() }
        return order
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    private func touchLocked(_ file: String) {
        order.removeAll { $0 == file }
        order.append(file)
    }

    private func evictLocked() {
        while entries.count > capacity {
            guard let victim = order.first(where: { $0 != pinned }) else { break }
            entries.removeValue(forKey: victim)
            order.removeAll { $0 == victim }
        }
    }
}
