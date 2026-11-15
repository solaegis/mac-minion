import Foundation
import Testing
@testable import MacMinionKit

private struct Scratch {
    let root = FileManager.default.temporaryDirectory.appending(path: "mm-undo-\(UUID().uuidString)", directoryHint: .isDirectory)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func url(_ relative: String) -> URL { root.appending(path: relative) }
    func write(_ relative: String, _ text: String) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func read(_ relative: String) -> String? { (try? Data(contentsOf: url(relative))).map { String(decoding: $0, as: UTF8.self) } }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: url(relative).path) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func fileSnapshotPutsBackOnlyWhenNothingChangedSince() throws {
    let s = try Scratch(); defer { s.cleanUp() }
    try s.write("a.txt", "after a")
    try s.write("b.txt", "after b")
    let before = [s.url("a.txt"): Data("before a".utf8), s.url("b.txt"): Data("before b".utf8)]
    let after = [s.url("a.txt"): Data("after a".utf8), s.url("b.txt"): Data("after b".utf8)]
    try FileSnapshot.write(before, expecting: after)
    #expect(s.read("a.txt") == "before a" && s.read("b.txt") == "before b")

    try FileSnapshot.write(after, expecting: before)
    try s.write("b.txt", "the game wrote this")
    #expect(throws: ReversalError.changedSince(["b.txt"])) { try FileSnapshot.write(before, expecting: after) }
    #expect(s.read("a.txt") == "after a", "no file changes when any one changed since")
    #expect(s.read("b.txt") == "the game wrote this")
}

@Test func trashedItemsComeBackAndGoAgain() throws {
    let s = try Scratch(); defer { s.cleanUp() }
    try s.write("AddOns/Foo/Foo.txt", "foo")
    // A stand-in Trash, so the test never touches ~/.Trash.
    let fakeTrash: (URL) throws -> TrashedItem = { url in
        let dest = s.url("Trash/\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: dest)
        return TrashedItem(original: url, trashed: dest)
    }
    let first = try fakeTrash(s.url("AddOns/Foo"))
    #expect(!s.exists("AddOns/Foo"))
    try TrashMove.putBack([first])
    #expect(s.read("AddOns/Foo/Foo.txt") == "foo")

    let again = try TrashMove.trashAgain([first], using: fakeTrash)
    #expect(!s.exists("AddOns/Foo") && again[0].trashed != first.trashed)

    try s.write("AddOns/Foo/Other.txt", "a new folder in its place")
    #expect(throws: ReversalError.occupied(["Foo"])) { try TrashMove.putBack(again) }
    try FileManager.default.removeItem(at: s.url("AddOns/Foo"))
    try FileManager.default.removeItem(at: again[0].trashed)
    #expect(throws: ReversalError.missing(["Foo"])) { try TrashMove.putBack(again) }
}

@Test func folderExchangeSwapsAnUpdateBackAndForth() throws {
    let s = try Scratch(); defer { s.cleanUp() }
    let addons = s.url("AddOns"), old = s.url("undo/old"), new = s.url("undo/new")
    // After an update: the new Foo and a new FooLib are installed; the old Foo is in the stash.
    try s.write("AddOns/Foo/v.txt", "2")
    try s.write("AddOns/FooLib/v.txt", "2")
    try s.write("AddOns/Other/v.txt", "kept")
    try s.write("undo/old/Foo/v.txt", "1")
    let newDirs = ["Foo", "FooLib"], oldDirs = FolderExchange.folders(in: old)
    #expect(oldDirs == ["Foo"])

    try FolderExchange.exchange(in: addons, takeOut: newDirs, to: new, putIn: oldDirs, from: old)
    #expect(s.read("AddOns/Foo/v.txt") == "1" && !s.exists("AddOns/FooLib") && s.read("AddOns/Other/v.txt") == "kept")

    try FolderExchange.exchange(in: addons, takeOut: oldDirs, to: old, putIn: newDirs, from: new)
    #expect(s.read("AddOns/Foo/v.txt") == "2" && s.read("AddOns/FooLib/v.txt") == "2")

    // Undo after a first install: nothing to put back, the new folders just leave.
    try FolderExchange.exchange(in: addons, takeOut: ["FooLib"], to: new, putIn: [], from: old)
    #expect(!s.exists("AddOns/FooLib") && s.read("undo/new/FooLib/v.txt") == "2")
}

@Test func folderExchangeChecksBeforeMovingAnything() throws {
    let s = try Scratch(); defer { s.cleanUp() }
    let addons = s.url("AddOns"), old = s.url("undo/old"), new = s.url("undo/new")
    try s.write("AddOns/Foo/v.txt", "2")
    try s.write("undo/old/Foo/v.txt", "1")
    #expect(throws: ReversalError.missing(["Bar"])) {
        try FolderExchange.exchange(in: addons, takeOut: ["Foo", "Bar"], to: new, putIn: ["Foo"], from: old)
    }
    #expect(s.read("AddOns/Foo/v.txt") == "2", "nothing moved")
    try s.write("AddOns/Baz/v.txt", "someone else's")
    try s.write("undo/old/Baz/v.txt", "1")
    #expect(throws: ReversalError.occupied(["Baz"])) {
        try FolderExchange.exchange(in: addons, takeOut: ["Foo"], to: new, putIn: ["Foo", "Baz"], from: old)
    }
    #expect(s.read("AddOns/Foo/v.txt") == "2" && s.read("AddOns/Baz/v.txt") == "someone else's")
}

@Test func installerKeepsReplacedFoldersInTheStash() async throws {
    let s = try Scratch(); defer { s.cleanUp() }
    try s.write("AddOns/Foo/v.txt", "1")
    // A zip with the new Foo.
    try s.write("src/Foo/v.txt", "2")
    let zip = s.url("foo.zip")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", s.url("src").path, zip.path]
    try p.run()
    p.waitUntilExit()
    let stash = s.url("undo/old")
    let record = try await Installer(addons: s.url("AddOns")).install(
        AddonDetails(id: 1, version: "2", md5: "", fileName: "foo.zip", downloadURL: zip), stash: stash)
    #expect(record.dirs == ["Foo"])
    #expect(s.read("AddOns/Foo/v.txt") == "2" && s.read("undo/old/Foo/v.txt") == "1")
}
