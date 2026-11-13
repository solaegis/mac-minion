import Foundation

/// Where a character is: their account and megaserver. Either can be unknown.
/// A name is unique only on one megaserver, so a character is (account, megaserver, name), never (account, name).
public struct CharacterLocation: Sendable, Hashable {
    public var account: String?
    public var megaserver: String?

    public init(account: String?, megaserver: String?) {
        self.account = account
        self.megaserver = megaserver
    }
}

/// Every known character's account and megaserver, by ID: the companion's roster first, then the
/// tables keyed by their ID (`SettingsMatrix.Home`), then the ID's prefix for the megaserver.
public struct CharacterLocations: Sendable, Hashable {
    var known: [String: CharacterLocation] = [:]

    public init() {}

    public init(roster: [String: CompanionCharacter]?, homes: [String: SettingsMatrix.Home]) {
        for (id, home) in homes {
            known[id] = CharacterLocation(account: home.account, megaserver: SVLevel.megaserver(ofProfile: home.server))
        }
        for (id, c) in roster ?? [:] {
            known[id] = CharacterLocation(account: c.account.isEmpty ? known[id]?.account : c.account,
                                       megaserver: SVLevel.megaserver(ofProfile: c.server) ?? known[id]?.megaserver)
        }
    }

    /// A character's account and megaserver, as far as anything says.
    public func location(_ id: String) -> CharacterLocation {
        var p = known[id] ?? CharacterLocation(account: nil, megaserver: nil)
        if p.megaserver == nil { p.megaserver = CharacterID.megaserver(ofID: id) }
        return p
    }

    /// What a table keyed by a character's name stands for.
    public enum Match: Sendable, Equatable {
        /// No known character fits.
        case none
        /// Exactly one character.
        case one(String)
        /// A table under the `Default` profile, which every megaserver shares: one character of this name
        /// on each of these megaservers, so the game gives them all the same table.
        case shared([String])
        /// More than one character could be meant, and nothing says which.
        case ambiguous([String])
    }

    /// The character a name-keyed table at `Var › profile › account › name` belongs to, from `ids` (the
    /// characters with that name). The account must match, and the megaserver too unless the profile is
    /// `Default`. An unknown account or megaserver only fits when nothing known says otherwise.
    public func resolve(name: String, account: String, profile: String, among ids: [String]) -> Match {
        let megaserver = SVLevel.megaserver(ofProfile: profile)
        let fits = ids.filter { id in
            let p = location(id)
            let sameAccount = p.account == nil || p.account == account
            let sameServer = megaserver == nil || p.megaserver == nil || p.megaserver == megaserver
            return sameAccount && sameServer
        }.sorted()
        switch fits.count {
        case 0: return .none
        case 1: return .one(fits[0])
        default:
            let servers = fits.map { location($0).megaserver }
            if megaserver == nil, servers.allSatisfy({ $0 != nil }), Set(servers).count == fits.count { return .shared(fits) }
            return .ambiguous(fits)
        }
    }

    /// "NA and EU", for a table those characters share.
    public func sharedServers(_ ids: [String]) -> String {
        let short = ids.compactMap { location($0).megaserver }.map(SettingsMatrix.shortServer).sorted()
        return short.formatted(.list(type: .and))
    }
}
