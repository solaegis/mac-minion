import Foundation
import Testing
@testable import MacMinionKit

private let panel = #"""
ZO_CreateStringId("SI_DEMO_SHOW_MAP", "Show |cFFFFFFthe|r map")
local defaults = {
    showMap = true, -- Show the map while crafting
    speed = 2, -- TODO: remove
    window = { x = 10, y = 20 },
}
local options = {
    {
        type = "checkbox",
        name = GetString(SI_DEMO_SHOW_MAP),
        tooltip = "Opens the map beside the crafting station.",
        getFunc = function() return Demo.sv.showMap end,
        setFunc = function(v) Demo.sv.showMap = v end,
    },
    {
        type = "slider",
        name = "Window left",
        choices = { name = "not this one" },
        getFunc = function()
            return Demo.sv.window.x
        end,
    },
    { type = "checkbox", name = "Map", getFunc = function() return Demo.sv["other"].map end },
}
"""#

private let byConstant = #"""
Demo.Types = {
    --SETTING_TYPE_ACCESSIBILITY,
    SETTING_TYPE_CAMERA,
    SETTING_TYPE_COMBAT,
}
for _,x in pairs(Demo.Types) do
    Demo.Default.allSettings[x] = {}
end
MODE_FAST = 1
MODE_SLOW = 2
Demo.Modes = { MODE_FAST, MODE_SLOW }
for _, m in ipairs(Demo.Modes) do Demo.Default.byMode[m] = {} end
Demo.sv.counts[MODE_SLOW] = 0
"""#

@Test func namesKeysFromTheSettingsPanel() throws {
    let names = SVSourceNames.parse([panel])
    let map = try #require(names.name(for: .string("showMap"), at: [.string("Demo_SV"), .string("$AccountWide")]))
    #expect(map.title == "Show the map" && map.detail == "Opens the map beside the crafting station." && map.source == .settingsPanel && !map.isGuess)
    let x = try #require(names.name(for: .string("x"), at: [.string("window")]))
    #expect(x.title == "Window left" && x.isGuess == false)
    #expect(names.name(for: .string("x"), at: [.string("elsewhere")])?.isGuess == true, "a short key matched by name alone is a guess")
    #expect(names.name(for: .string("map"), at: [.string("other")])?.title == "Map")
    #expect(names.name(for: .string("speed"), at: []) == nil, "TODO comments aren't descriptions")
}

@Test func commentsDescribeDefaults() {
    let names = SVSourceNames.parse(["local d = {\n    autoLoot = false, -- Loot everything when you open a body\n}\n"])
    #expect(names.name(for: .string("autoLoot"), at: [])?.detail == "Loot everything when you open a body")
    #expect(names.name(for: .string("autoLoot"), at: [])?.title == nil && names.name(for: .string("autoLoot"), at: [])?.isGuess == true)
    let examples = SVSourceNames.parse(["local r = {\n    glyph = 1, -- Glyph\n    link = 2, -- \"|H0:item:1|h|h\"\n    level = 3, -- 150 or 160\n}\n"])
    #expect(examples.isEmpty, "example values and single words aren't descriptions")
}

@Test func tablesKeyedByConstants() {
    let names = SVSourceNames.parse([byConstant])
    #expect(names.note(forTable: .string("allSettings"))?.hasPrefix("Keyed by SETTING_TYPE_* values, like SETTING_TYPE_CAMERA, SETTING_TYPE_COMBAT") == true)
    #expect(names.name(for: .integer(10), at: [.string("allSettings")]) == nil, "the game's numbers aren't in the source")
    let slow = names.name(for: .integer(2), at: [.string("byMode")])
    #expect(slow?.title == "MODE_SLOW" && slow?.isGuess == true && slow?.source == .constant)
    #expect(names.name(for: .integer(2), at: [.string("counts")])?.title == "MODE_SLOW")
}

@Test func leavesOutTranslations() {
    #expect(SVSourceNames.isTranslation("de.lua") && SVSourceNames.isTranslation("Demo_fr.lua") && !SVSourceNames.isTranslation("Demo.lua"))
}

/// SOURCE_NAMES_ADDONS=<AddOns folder> swift test --filter surveyInstalledAddons: how many keys each addon names.
@Test func surveyInstalledAddons() {
    guard let path = ProcessInfo.processInfo.environment["SOURCE_NAMES_ADDONS"] else { return }
    let folder = URL(filePath: path)
    for name in ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted() where !name.hasPrefix(".") {
        let start = Date()
        let names = SVSourceNames.read(folder: folder.appending(path: name))
        print("SURVEY \(name): \(names.count) names, \(names.tableNotes.count) notes, \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        guard ProcessInfo.processInfo.environment["SOURCE_NAMES_SHOW"] == name else { continue }
        for (parent, keys) in names.names.sorted(by: { $0.key < $1.key }) {
            for (key, n) in keys.sorted(by: { $0.key < $1.key }) { print("  [\(parent)] \(key) = \(n.title ?? "-") | \(n.detail ?? "") \(n.isGuess ? "(guess)" : "")") }
        }
        for (table, note) in names.tableNotes { print("  NOTE \(table): \(note)") }
    }
}

// MARK: Ranges and choices

private let controlsSource = #"""
local MODE_OFF = 0
local MODE_ALWAYS = 1
local MODE_COMBAT = 2
local sizes = { "Small", "Large" }
local options = {
    { type = "slider", name = "Scale", min = 50, max = 150, step = 5, default = 100,
      getFunc = function() return MyAddon.sv.ui.scale end, setFunc = function(v) MyAddon.sv.ui.scale = v end },
    { type = "dropdown", name = "Show", choices = { "Never", "Always", "In combat" }, -- labels
      choicesValues = { MODE_OFF, MODE_ALWAYS, MODE_COMBAT },
      getFunc = function() return MyAddon.sv.mode end, setFunc = function(v) MyAddon.sv.mode = v end },
    { type = "dropdown", name = "Size", choices = sizes,
      getFunc = function() return MyAddon.sv.size end, setFunc = function(v) MyAddon.sv.size = v end },
}
"""#

@Test func slidersGiveRanges() throws {
    let names = SVSourceNames.parse([controlsSource])
    let scale = try #require(names.control(for: .string("scale"), at: [.string("ui")]))
    #expect(scale.type == "slider")
    #expect(scale.range == 50...150)
    #expect(scale.step == 5)
    #expect(scale.defaultValue == "100")
    #expect(scale.isOutOfRange(.integer(200)))
    #expect(!scale.isOutOfRange(.number(75)))
}

@Test func dropdownsGiveChoicesFromConstants() throws {
    let names = SVSourceNames.parse([controlsSource])
    let mode = try #require(names.control(for: .string("mode"), at: []))
    #expect(mode.choices.map(\.label) == ["Never", "Always", "In combat"])
    #expect(mode.choice(for: .integer(2))?.label == "In combat")
    #expect(mode.choice(for: .number(1))?.label == "Always")
    #expect(SVReadable.display(.integer(2), key: .string("mode"), at: [], names: nil, control: mode)
            == .choice(label: "In combat", value: "2"))
}

@Test func dropdownsWithoutValuesSaveTheLabel() throws {
    let names = SVSourceNames.parse([controlsSource])
    let size = try #require(names.control(for: .string("size"), at: []))
    #expect(size.choices.map(\.value) == ["Small", "Large"])
    // The label is the value: nothing new to show.
    #expect(SVReadable.display(.string("Large"), key: .string("size"), at: [], names: nil, control: size) == .text("Large"))
}

@Test func comparisonsWithConstantsGiveChoices() throws {
    let source = """
    MyAddon.STYLE_NONE = 0
    MyAddon.STYLE_ICON = 1
    MyAddon.STYLE_TEXT = 2
    if MyAddon.sv.style == MyAddon.STYLE_ICON then end
    if self.sv.style ~= MyAddon.STYLE_TEXT then end
    """
    let style = try #require(SVSourceNames.parse([source]).control(for: .string("style"), at: []))
    #expect(style.type == "constants")
    #expect(style.choice(for: .integer(2))?.label == "Text")
    #expect(style.choice(for: .integer(0)) == nil)
}

@Test func rangedNumbersShowTheirRange() {
    let control = SVControl(type: "slider", min: 0, max: 10)
    #expect(SVReadable.display(.integer(12), key: .string("count"), at: [], names: nil, control: control)
            == .ranged(text: "12", range: 0...10, outOfRange: true))
}

@Test func tableItemsSkipCommentsAndNesting() {
    #expect(SVSourceNames.items("\"a,b\", -- one, two\n GetString(SI_X), { 1, 2 }; 3")
            == [#""a,b""#, "GetString(SI_X)", "{ 1, 2 }", "3"])
}
