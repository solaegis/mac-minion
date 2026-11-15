import AppKit
import MacMinionKit

/// A change that can be taken back and made again: Edit › Undo runs `undo`, then Redo runs `redo`.
/// Both are known when the change is made, so Redo is registered at once, as `UndoManager` needs.
@MainActor
struct Reversible {
    /// The action's name in the Edit menu: "Undo Remove Addon".
    var name: String
    var undo: @MainActor () async throws -> Void
    var redo: @MainActor () async throws -> Void

    var inverted: Reversible { Reversible(name: name, undo: redo, redo: undo) }

    /// Several changes as one menu item: undo takes them back newest first, redo makes them again in order.
    static func group(_ name: String, _ parts: [Reversible]) -> Reversible? {
        guard parts.count > 1 else { return parts.first.map { Reversible(name: name, undo: $0.undo, redo: $0.redo) } }
        return Reversible(name: name,
                          undo: { for part in parts.reversed() { try await part.undo() } },
                          redo: { for part in parts { try await part.redo() } })
    }
}

/// Why an undo or redo didn't run.
enum UndoProblem: LocalizedError {
    case gameRunning
    case other(String)

    var errorDescription: String? {
        switch self {
        case .gameRunning: String(localized: "Quit Elder Scrolls Online first: it rewrites these files when it quits.")
        case .other(let why): why
        }
    }
}

/// One undo stack for the app's data: the main window's, so Command-Z works whichever page or menu made the
/// change (rule: "Undo", design/MACOS-UI-ARCHITECTURE.md). Undo and redo run one at a time, in order.
@MainActor
enum MainUndo {
    /// Set by the self-test, which has no window to take a manager from.
    static var override: UndoManager?
    /// Shown when an undo or redo can't run: (title, why). Set once by `AppModel`.
    static var onFailure: (@MainActor (String, String) -> Void)?

    static var manager: UndoManager? {
        override
            ?? NSApplication.shared.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })?.undoManager
            ?? NSApplication.shared.mainWindow?.undoManager
    }

    private static var running: Task<Void, Never>?

    /// Registers a change made just now.
    static func register(_ change: Reversible) {
        guard let manager else { return }
        register(change, token: Token(), manager: manager)
    }

    /// Waits until every undo and redo started so far is done.
    static func settle() async {
        while let task = running {
            await task.value
            if running == task { running = nil }
        }
    }

    /// One change's place on the stack; dropping its actions after a failure leaves the others.
    private final class Token {}

    private static func register(_ change: Reversible, token: Token, manager: UndoManager) {
        // The manager keeps an unowned reference to its target; the handler keeps the token alive.
        manager.registerUndo(withTarget: token) { [token] _ in
            MainActor.assumeIsolated {
                let redoing = manager.isRedoing
                // Registered now, during undo, so it lands on the redo stack (and the other way round).
                register(change.inverted, token: token, manager: manager)
                let previous = running
                running = Task { @MainActor in
                    await previous?.value
                    do {
                        try await change.undo()
                    } catch {
                        manager.removeAllActions(withTarget: token)
                        let title = redoing ? String(localized: "Couldn't Redo \(change.name)") : String(localized: "Couldn't Undo \(change.name)")
                        onFailure?(title, error.localizedDescription)
                    }
                }
            }
        }
        manager.setActionName(change.name)
    }
}

/// Folders an install moved aside, kept so it can be undone without downloading again. Emptied at launch:
/// the undo stack doesn't outlive the app.
enum UndoStash {
    static var root: URL { Store.directory.appending(path: "undo", directoryHint: .isDirectory) }

    /// A new, empty pair of folders for one change.
    static func make() -> (old: URL, new: URL) {
        let base = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (base.appending(path: "old", directoryHint: .isDirectory), base.appending(path: "new", directoryHint: .isDirectory))
    }

    static func clear() { try? FileManager.default.removeItem(at: root) }
}

/// A value an undo and its redo share, such as where the Trash put an item this time.
@MainActor
final class UndoBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension Reversible {
    /// Puts back each file's bytes from before, and Redo writes the change again; either is refused while ESO
    /// runs, and when a file changed since (the game or another app wrote it), so nothing newer is lost.
    static func files(_ name: String, before: [URL: Data], after: [URL: Data], gameRunning: @escaping @MainActor () -> Bool,
                      done: @escaping @MainActor (_ undone: Bool) async -> Void) -> Reversible {
        Reversible(name: name, undo: {
            guard !gameRunning() else { throw UndoProblem.gameRunning }
            try FileSnapshot.write(before, expecting: after)
            await done(true)
        }, redo: {
            guard !gameRunning() else { throw UndoProblem.gameRunning }
            try FileSnapshot.write(after, expecting: before)
            await done(false)
        })
    }

    /// Puts items back from the Trash, and Redo moves them there again. `refuse` says why not to, if anything.
    static func trash(_ name: String, items: [TrashedItem], refuse: @escaping @MainActor () -> UndoProblem? = { nil },
                      done: @escaping @MainActor (_ undone: Bool) async -> Void) -> Reversible {
        let box = UndoBox(items)
        return Reversible(name: name, undo: {
            if let problem = refuse() { throw problem }
            try TrashMove.putBack(box.value)
            await done(true)
        }, redo: {
            if let problem = refuse() { throw problem }
            box.value = try TrashMove.trashAgain(box.value)
            await done(false)
        })
    }
}
