import Foundation
import MacMinionKit

/// One full read of SavedVariables, with what the AddOns folder says about who saves what: everything the
/// Game Folder pages show. Kept whole, so a read arrives, and is set aside, in one step.
struct SavedVariablesRead {
    var names: SVNameIndex
    var references: SVReferenceIndex
    /// What looks wrong in SavedVariables, errors first (S-039).
    var problems: [SVProblem]
    /// What takes space in SavedVariables (S-040).
    var usage: SVUsage
    /// Addons' settings per character (S-054).
    var matrix: SettingsMatrix
    /// MacMinion Companion's character roster; empty when the addon hasn't written one (S-049).
    var roster: [String: CompanionCharacter]
    /// Accounts, characters, addons, and where they meet: what Problems groups by (S-052).
    var graph: SVGraph
    /// SavedVariables file -> the AddOns folder it ships in, for grouping the space map (S-048).
    var topFolders: [String: String]
    /// Each installed addon that saves, by lowercased folder name -> its folder.
    var addonFolders: [String: URL]
    /// When the read finished.
    var at: Date

    /// Kit's read of the files, with the AddOns index it was read against.
    init(_ read: SVFolderRead, topFolders: [String: String], addonFolders: [String: URL], at: Date = .now) {
        names = read.names
        references = read.references
        problems = read.problems
        usage = read.usage
        matrix = read.matrix
        roster = read.roster
        graph = read.graph
        self.topFolders = topFolders
        self.addonFolders = addonFolders
        self.at = at
    }
}
