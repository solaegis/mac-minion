import Foundation
import MacMinionKit

/// Ask About Your Game Folder and Explain a Problem with AI (S-076): the model looks things up through
/// tools over what MacMinion already read, after you allow saved values for the session.
extension GameFolderModel {
    static let askSystem = """
    You answer a player's questions about their Elder Scrolls Online addons and characters, from what MacMinion \
    has read in their SavedVariables files. Use the tools to look things up; never guess a value. Characters, \
    addons, and settings are named the way the tools name them. Answer in a few plain sentences or a short list. \
    When the tools don't show the answer, say so.
    """

    /// What Ask sends, for the permission question.
    var askItems: [String] {
        [String(localized: "Addon, character, account, and setting names"),
         String(localized: "Saved setting values the AI asks to see"),
         String(localized: "File sizes and the Problems list, including Lua error messages")]
    }

    /// Asks the question in `askQuestion`, letting the AI look things up.
    func ask() async {
        let question = askQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !askBusy else { return }
        askError = nil
        askAnswer = ""
        askSteps = []
        if let problem = app.prefs.aiConfig.problem { askError = problem; return }
        if let refused = await app.allowSendingValues(purpose: String(localized: "Ask About Your Game Folder"), items: askItems) {
            askError = refused
            return
        }
        askBusy = true
        defer { askBusy = false }
        do {
            askAnswer = try await AIClient(config: app.prefs.aiConfig).answer(system: Self.askSystem, prompt: question, tools: askTools) { call in
                await MainActor.run { self.askSteps.append(self.stepTitle(call)) }
            }
        } catch {
            askError = error.localizedDescription
        }
    }

    /// "Looked at WritWorthy's settings": what the AI asked for, in words.
    func stepTitle(_ call: AIToolCall) -> String {
        let addon = call.arguments["addon"].map { resolveAddon($0).map(app.addonName) ?? $0 }
        switch call.name {
        case "list_addons": return String(localized: "Listed the addons with settings")
        case "list_characters": return String(localized: "Listed the characters")
        case "addon_settings": return String(localized: "Looked at \(addon ?? "an addon")'s settings")
        case "setting_values": return String(localized: "Looked at \(call.arguments["setting"] ?? "a setting") in \(addon ?? "an addon")")
        case "problems": return String(localized: "Read the Problems list")
        case "largest_files": return String(localized: "Looked at file sizes")
        default: return call.name
        }
    }

    // MARK: Tools

    var askTools: [AITool] {
        // Answers are built on the main actor, from the read already in memory.
        func tool(_ spec: AIToolSpec, _ body: @escaping @MainActor ([String: String]) -> String) -> AITool {
            AITool(spec) { args in await MainActor.run { body(args) } }
        }
        return [
            tool(AIToolSpec(name: "list_addons", description: "Addons that keep per-character settings: file, name, how many characters have settings.")) { _ in
                self.toolAddons()
            },
            tool(AIToolSpec(name: "list_characters", description: "Every character: ID, name, account, and megaserver.")) { _ in
                self.toolCharacters()
            },
            tool(AIToolSpec(name: "addon_settings", description: "One addon's settings: each setting's name, what values it takes, and which value each character has.",
                            parameters: [.init("addon", "The addon's name or SavedVariables file, from list_addons.")])) { args in
                self.toolAddonSettings(args["addon"] ?? "")
            },
            tool(AIToolSpec(name: "setting_values", description: "One setting's value on every character.",
                            parameters: [.init("addon", "The addon's name or file."), .init("setting", "The setting's name, as addon_settings gives it.")])) { args in
                self.toolSettingValues(args["addon"] ?? "", args["setting"] ?? "")
            },
            tool(AIToolSpec(name: "problems", description: "What MacMinion's Problems page lists: broken addons, Lua errors, damaged or oversized files, leftovers.",
                            parameters: [.init("addon", "Only problems about this addon.", required: false)])) { args in
                self.toolProblems(args["addon"])
            },
            tool(AIToolSpec(name: "largest_files", description: "The biggest SavedVariables files and which addon saves each.")) { _ in
                self.toolLargestFiles()
            },
        ]
    }

    /// An addon's file from what the AI calls it: the file, the folder, or the title, in any case.
    func resolveAddon(_ name: String) -> String? {
        let n = name.lowercased().replacingOccurrences(of: ".lua", with: "")
        let files = matrix?.addons.map(\.file) ?? []
        return files.first { $0.lowercased().dropLast(4) == n }
            ?? files.first { app.addonName($0).lowercased() == n }
            ?? files.first { app.addonName($0).lowercased().contains(n) || $0.lowercased().contains(n) }
    }

    private func characterLine(_ id: String) -> String {
        let place = characterLocations.location(id)
        return [characterName(id), id, place.account, place.megaserver].compactMap { $0 }.joined(separator: " | ")
    }

    func toolAddons() -> String {
        guard let matrix else { return "Nothing has been read yet." }
        return (["file | addon | characters with settings"] + matrix.addons.map {
            "\($0.file) | \(app.addonName($0.file)) | \($0.characters.count)"
        }).joined(separator: "\n")
    }

    func toolCharacters() -> String {
        guard let matrix else { return "Nothing has been read yet." }
        return (["name | ID | account | megaserver"] + matrix.characterIDs.map(characterLine)).joined(separator: "\n")
    }

    func toolAddonSettings(_ addon: String) -> String {
        guard let file = resolveAddon(addon), let a = matrix?.addon(file) else { return "No addon matches “\(addon)”. Use list_addons." }
        var lines = ["\(app.addonName(file)) (\(file)), \(a.characters.count) characters."]
        for key in a.keys {
            let groups = a.values(of: key)
            guard let setting = groups.first?.setting else { continue }
            var line = "- \(settingLabel(key, setting))"
            let parent = Array(setting.path.dropLast())
            if let control = sourceNames(for: setting)?.control(for: setting.key, at: parent), let values = SVExplanation(key: key, name: nil, control: control, lines: []).values {
                line += " [takes \(values)]"
            }
            let shown = groups.prefix(4).map { "\(Self.text(display($0.setting))) on \($0.characters.count)" }
            line += ": " + shown.joined(separator: "; ") + (groups.count > 4 ? "; and \(groups.count - 4) more values" : "")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    func toolSettingValues(_ addon: String, _ setting: String) -> String {
        guard let file = resolveAddon(addon), let a = matrix?.addon(file) else { return "No addon matches “\(addon)”. Use list_addons." }
        let wanted = setting.lowercased()
        guard let key = a.keys.first(where: { k in
            k.lowercased() == wanted || settingLabel(k, a.values(of: k).first?.setting).lowercased() == wanted
        }) else { return "\(app.addonName(file)) has no setting “\(setting)”. Use addon_settings." }
        return a.characters.keys.sorted { characterName($0) < characterName($1) }.compactMap { id in
            a.characters[id]?[key].map { "\(characterName(id)) (\(id)): \(Self.text(display($0)))" }
        }.joined(separator: "\n")
    }

    func toolProblems(_ addon: String?) -> String {
        var findings = healthFindings
        if let addon, !addon.isEmpty {
            let n = addon.lowercased()
            findings = findings.filter { f in f.affected.contains { $0.name.lowercased().contains(n) } || f.title.lowercased().contains(n) }
        }
        guard !findings.isEmpty else { return "Nothing on the Problems page\(addon.map { " about \($0)" } ?? "")." }
        return findings.prefix(20).map { f in
            "- \(f.title) (\(f.tier.title)): \(f.impact)" + (f.problems.first.map { " e.g. \($0.message)" } ?? "")
        }.joined(separator: "\n")
    }

    func toolLargestFiles() -> String {
        savedVariables.sorted { $0.bytes > $1.bytes }.prefix(15).map {
            "\($0.name): \($0.bytes.formatted(.byteCount(style: .file)))"
        }.joined(separator: "\n")
    }

    /// A value as the tools say it: "Always (2)", "On", "Glenumbra (zone 3)".
    static func text(_ display: SVDisplay) -> String {
        switch display {
        case .toggle(let on): on ? "On" : "Off"
        case .color(let r, let g, let b, _): SettingValueView.hex(r, g, b)
        case .item(let title, _): title
        case .date(let date): date.formatted(date: .abbreviated, time: .omitted)
        case .gold(let n): "\(n.formatted()) gold"
        case .name(let name): name.id.map { "\(name.title) (\(name.kind.rawValue) \($0))" } ?? name.title
        case .number(let s), .text(let s): s
        case .table(let count, let isList): isList ? "a list of \(count)" : "a table of \(count)"
        case .choice(let label, let value): "\(label) (\(value))"
        case .ranged(let text, let range, let out): out ? "\(text), outside \(range.lowerBound.formatted())–\(range.upperBound.formatted())" : text
        }
    }

    // MARK: Explain a problem

    /// Streams a likely cause and fix for one finding, from what the Problems page shows about it.
    func diagnose(_ finding: HealthFinding) async {
        guard diagnosing == nil else { return }
        diagnosisErrors[finding.id] = nil
        if let problem = app.prefs.aiConfig.problem { diagnosisErrors[finding.id] = problem; return }
        if let refused = await app.allowSendingValues(purpose: String(localized: "Explain with AI"),
                                                      items: [String(localized: "This problem as the Problems page shows it, including Lua error messages"),
                                                              String(localized: "Addon, file, and character names")]) {
            diagnosisErrors[finding.id] = refused
            return
        }
        diagnosing = finding.id
        defer { diagnosing = nil }
        var prompt = "Problem: \(finding.title)\nKind: \(finding.tier.title)\nWhat it means: \(finding.impact)\n"
        if let summary = finding.summary { prompt += "Count: \(summary)\n" }
        if let note = finding.certaintyNote { prompt += "Note: \(note)\n" }
        prompt += "About: \(finding.affected.map(\.name).joined(separator: ", "))\n\nDetails:\n"
        for p in finding.problems.prefix(12) {
            prompt += "- \(p.file): \(p.message)\n"
            if let detail = p.detail { prompt += String(detail.prefix(1_500)).split(separator: "\n").map { "    \($0)" }.joined(separator: "\n") + "\n" }
        }
        let id = finding.id
        do {
            _ = try await AIClient(config: app.prefs.aiConfig).stream(system: Self.diagnoseSystem, prompt: prompt) { text in
                await MainActor.run { self.diagnoses[id] = text }
            }
        } catch {
            diagnosisErrors[id] = error.localizedDescription
        }
    }

    static let diagnoseSystem = """
    You help a player fix a problem MacMinion found with their Elder Scrolls Online addons or saved files. \
    From the details, say in 2 to 4 plain sentences the most likely cause and what to try first, in MacMinion \
    (update the addon, install a library, restore a backup, clean up) or in the game. Say how sure you are. \
    No headings or code.
    """
}
