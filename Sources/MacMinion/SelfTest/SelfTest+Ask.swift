import Foundation
import MacMinionKit

extension SelfTest {
    /// Ask About Your Game Folder, Explain with AI on Problems, and the saved-values permission (S-076).
    static func askAndDiagnose(_ model: AppModel) async {
        await model.gameFolder.load()
        let folder = model.gameFolder
        let providerBefore = model.prefs.aiProvider
        model.prefs.aiProvider = .ollama
        model.prefs.ollamaModel = model.prefs.ollamaModel.isEmpty ? "llama3.2" : model.prefs.ollamaModel

        // Settings: on unless turned off; off means never, on means asked once a session.
        check("saved values are allowed unless turned off", model.prefs.allowsValues(.ollama) && model.prefs.allowsValues(.claude))
        model.prefs.setAllowsValues(false, for: .ollama)
        let refused = await model.allowSendingValues(purpose: "Test", items: ["x"])
        check("a provider not allowed saved values is never asked", refused?.contains("Allow Saved Values") == true && model.valuesRequest == nil, refused ?? "nil")
        model.prefs.setAllowsValues(true, for: .ollama)
        model.valuesApproved = []
        let declined = Task { await model.allowSendingValues(purpose: "Test", items: ["x"]) }
        for _ in 0..<40 where model.valuesRequest == nil { try? await Task.sleep(for: .milliseconds(25)) }
        check("the first time, you're asked what will be sent", model.valuesRequest?.items == ["x"] && model.valuesRequest?.provider == .ollama)
        model.answerValuesRequest(false)
        check("Don't Send sends nothing", await declined.value == "Nothing was sent." && !model.valuesApproved.contains(.ollama))
        let allowed = Task { await model.allowSendingValues(purpose: "Test", items: ["x"]) }
        for _ in 0..<40 where model.valuesRequest == nil { try? await Task.sleep(for: .milliseconds(25)) }
        model.answerValuesRequest(true)
        check("Allow Until Quit is kept for the session", await allowed.value == nil && model.valuesApproved.contains(.ollama))
        check("once allowed, you aren't asked again", await model.allowSendingValues(purpose: "Test", items: ["x"]) == nil && model.valuesRequest == nil)

        // The tools answer from what MacMinion read.
        check("an addon is found by its file, folder, or part of its name",
              folder.resolveAddon("WritWorthy.lua") == "WritWorthy.lua" && folder.resolveAddon("writ") == "WritWorthy.lua")
        check("list_addons lists files and names", folder.toolAddons().contains("WritWorthy.lua | WritWorthy |"), folder.toolAddons())
        check("list_characters names each character", folder.toolCharacters().contains("Masisi | 8796093036412335"), folder.toolCharacters())
        let settings = folder.toolAddonSettings("WritWorthy")
        check("addon_settings gives names, what values a setting takes, and who has which",
              settings.contains("Writs to keep [takes 0 to 100, in steps of 5]: 10 on") && settings.contains("Auto craft"), settings)
        let values = folder.toolSettingValues("writworthy", "Auto craft")
        check("setting_values gives each character's value", values.contains("Masisi (8796093036412335): Off"), values)
        check("an unknown addon says how to find one", folder.toolAddonSettings("Nope").contains("Use list_addons"))
        check("problems can be narrowed to an addon", folder.toolProblems("Dustman").contains("Dustman"), folder.toolProblems("Dustman"))
        check("largest_files lists sizes", folder.toolLargestFiles().contains("HarvestMapAD.lua"))
        check("each tool call reads as a step", folder.stepTitle(AIToolCall(id: "1", name: "addon_settings", arguments: ["addon": "writ"]))
              == "Looked at WritWorthy's settings")
        check("Ask offers six tools", folder.askTools.map(\.spec.name) == ["list_addons", "list_characters", "addon_settings", "setting_values", "problems", "largest_files"])

        // Without a working setup, both say what's missing and send nothing.
        model.prefs.aiProvider = .claude
        folder.askQuestion = "Which characters have Auto craft off?"
        await folder.ask()
        check("Ask says what's missing in Settings", folder.askError == "Add a Claude API key in Settings." && folder.askAnswer.isEmpty, folder.askError ?? "")
        if let finding = folder.healthFindings.first {
            await folder.diagnose(finding)
            check("Explain with AI on Problems says what's missing in Settings", folder.diagnosisErrors[finding.id] == "Add a Claude API key in Settings.")
            folder.diagnosisErrors = [:]
        }
        folder.askQuestion = ""
        folder.askError = nil
        model.valuesApproved = []
        model.prefs.aiProvider = providerBefore
    }
}
