import Foundation
import Testing
@testable import MacMinionKit

private let panel = #"""
local options = {
    { type = "slider", name = "Scale", min = 50, max = 150,
      getFunc = function() return MyAddon.sv.ui.scale end },
    { type = "checkbox", name = "Enabled",
      getFunc = function() return MyAddon.sv.enabled end },
}
"""#

private func setting(_ key: String, _ value: LuaValue, parent: [String]) -> SettingsMatrix.Setting {
    let path = parent.map(LuaKey.string) + [.string(key)]
    return SettingsMatrix.Setting(value: value, key: .string(key), path: path, text: "")
}

@Test func theSchemaCacheKeepsWhatTheSourceSaysPerVersion() throws {
    var names = SVSourceNames.parse([panel])
    names.add(SVSourceName(title: "AI guess", detail: nil, source: .ai, isGuess: true), key: "mystery", parent: "")
    var cache = SVSchemaCache()
    cache[folder: "MyAddon", version: "1.2"] = SVSourceNames.withoutAI(names)
    let data = try JSONEncoder().encode(cache)
    let back = try JSONDecoder().decode(SVSchemaCache.self, from: data)
    let kept = try #require(back[folder: "myaddon", version: "1.2"])
    #expect(kept.control(for: .string("scale"), at: [.string("ui")])?.range == 50...150)
    #expect(kept.name(for: .string("enabled"), at: [])?.title == "Enabled")
    #expect(kept.name(for: .string("mystery"), at: []) == nil, "AI names have their own cache")
    #expect(back[folder: "MyAddon", version: "1.3"] == nil, "a new version is read again")
}

@Test func theSchemaCacheForgetsOldVersions() {
    var cache = SVSchemaCache()
    cache[folder: "A", version: "1"] = SVSourceNames()
    cache[folder: "A", version: "2"] = SVSourceNames()
    cache[folder: "B", version: "1"] = SVSourceNames()
    cache.entries["0|c|1"] = SVSourceNames()
    cache.keepOnly([(folder: "A", version: "2")])
    #expect(cache[folder: "A", version: "1"] == nil)
    #expect(cache[folder: "A", version: "2"] != nil)
    #expect(cache[folder: "B", version: "1"] != nil, "addons not given are left alone")
    #expect(cache.entries["0|c|1"] == nil, "an older format is dropped")
}

@Test func numbersOutsideTheSlidersRangeAreProblems() {
    let names = SVSourceNames.parse([panel])
    let settings = [setting("scale", .integer(200), parent: ["MyAddon_SV", "ui"]),
                    setting("scale", .integer(200), parent: ["MyAddon_SV", "ui"]),
                    setting("scale", .integer(100), parent: ["Other", "ui"]),
                    setting("enabled", .bool(true), parent: ["MyAddon_SV"])]
    let problems = SVProblems.outOfRange(file: "MyAddon.lua", settings: settings, names: names)
    #expect(problems.count == 1, "one per place, and only outside the range")
    #expect(problems.first?.kind == .outOfRange)
    #expect(problems.first?.message.contains("Scale is 200") == true)
    #expect(problems.first?.message.contains("50 to 150") == true)
}
