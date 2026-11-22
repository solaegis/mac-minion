import Foundation
import Testing
@testable import MacMinionKit

@Test func linksReadActionsPagesAndAddons() {
    #expect(AppLink(url: URL(string: "macminion://action/update-all")!) == .action(.updateAll))
    #expect(AppLink(url: URL(string: "MacMinion://Action/Check-For-Updates")!) == .action(.checkForUpdates), "case doesn't matter")
    #expect(AppLink(url: URL(string: "macminion://open/find-more")!) == .open(page: "find-more"))
    #expect(AppLink(url: URL(string: "macminion://addon/7")!) == .addon(7))
    #expect(AppLink(url: URL(string: "macminion://addon/7/")!) == .addon(7), "a trailing slash is fine")
}

@Test func linksRefuseWhatTheyDontKnow() {
    for text in ["https://action/update-all", "macminion://action/delete-everything", "macminion://open/nowhere",
                 "macminion://addon/x", "macminion://addon/-3", "macminion://addon/7/8", "macminion://action", "macminion://other/x"] {
        #expect(AppLink(url: URL(string: text)!) == nil, "\(text)")
    }
}

@Test func updateAllLinkStillParsesWithoutConfirm() {
    // Confirm is enforced when opening the URL in the app, not when parsing the link.
    #expect(AppLink(url: URL(string: "macminion://action/update-all")!) == .action(.updateAll))
    #expect(AppLink(url: URL(string: "macminion://action/update-all?confirm=1")!) == .action(.updateAll))
}

@Test func everyLinkReadsBackFromItsURL() {
    let links = AppLink.Action.allCases.map(AppLink.action) + AppLink.pages.map { AppLink.open(page: $0) } + [.addon(1234)]
    for link in links { #expect(AppLink(url: link.url) == link) }
}
