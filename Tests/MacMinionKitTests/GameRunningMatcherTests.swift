import Testing
@testable import MacMinionKit

@Test func macAppMatcherFindsESONotUnrelated() {
    #expect(GameRunningMatcher.matchesMacApp(localizedName: "The Elder Scrolls Online", bundleIdentifier: "com.zenimax.ESO"))
    #expect(GameRunningMatcher.matchesMacApp(localizedName: "eso", bundleIdentifier: ""))
    #expect(GameRunningMatcher.matchesMacApp(localizedName: "eso64", bundleIdentifier: ""))
    #expect(!GameRunningMatcher.matchesMacApp(localizedName: "The Elder Scrolls V: Skyrim", bundleIdentifier: "com.zenimax.skyrim"))
    #expect(!GameRunningMatcher.matchesMacApp(localizedName: "Bethesda Launcher", bundleIdentifier: "com.zenimax.launcher"))
    #expect(!GameRunningMatcher.matchesMacApp(localizedName: "Steam", bundleIdentifier: "com.valvesoftware.steam"))
    #expect(!GameRunningMatcher.matchesMacApp(localizedName: "CrossOver", bundleIdentifier: "com.codeweavers.CrossOver"))
    #expect(!GameRunningMatcher.matchesMacApp(localizedName: "Safari", bundleIdentifier: "com.apple.Safari"))
}

@Test func wineCommandLineMatchesOnlyEso64() {
    #expect(GameRunningMatcher.matchesWineCommandLine(#"C:\windows\system32\wine eso64.exe -skipmovies"#))
    #expect(GameRunningMatcher.matchesWineCommandLine("/Users/x/.cxoffice/Elder Scrolls/drive_c/Program Files (x86)/Zenimax Online/The Elder Scrolls Online/game/client/eso64.exe"))
    #expect(GameRunningMatcher.matchesWineCommandLine("ESO64.EXE"))
    #expect(!GameRunningMatcher.matchesWineCommandLine("/tmp/copy-of-eso64.exe.bak"))
    #expect(!GameRunningMatcher.matchesWineCommandLine(#"C:\Program Files (x86)\Steam\steam.exe -applaunch 306130"#))
    #expect(!GameRunningMatcher.matchesWineCommandLine("Bethesda.net_Launcher.exe"))
    #expect(!GameRunningMatcher.matchesWineCommandLine(#"C:\users\crossover\Documents\...\TamrielTradeCentre\Client\Client.exe"#))
    #expect(!GameRunningMatcher.matchesWineCommandLine("winewrapper.exe"))
}

@Test func isGameRunningCombinesMacAndWine() {
    #expect(GameRunningMatcher.isGameRunning(
        macApps: [(localizedName: "Safari", bundleIdentifier: "com.apple.Safari")],
        wineCommandLines: [#"C:\game\eso64.exe"#]))
    #expect(GameRunningMatcher.isGameRunning(
        macApps: [(localizedName: "The Elder Scrolls Online", bundleIdentifier: "")],
        wineCommandLines: ["steam.exe"]))
    #expect(!GameRunningMatcher.isGameRunning(
        macApps: [(localizedName: "Steam", bundleIdentifier: "com.valvesoftware.steam")],
        wineCommandLines: ["steam.exe", "Bethesda.net_Launcher.exe", "Client.exe"]))
}
