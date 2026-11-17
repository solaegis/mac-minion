import Foundation
import MacMinionKit

/// One saved key to explain (S-075): which file, and where in it.
struct ExplainTarget: Identifiable, Equatable {
    let file: String
    let key: LuaKey
    let parent: [LuaKey]
    var id: String { file + "|" + (parent + [key]).luaPath }
}

/// Explain Setting: what the addon's source says about a key, then a paragraph from AI on request.
extension GameFolderModel {
    /// Opens Explain Setting for a key, reading the addon's source for it off the main thread.
    func explain(file: String, key: LuaKey, parent: [LuaKey]) async {
        let target = ExplainTarget(file: file, key: key, parent: parent)
        explainTarget = target
        explanation = nil
        explanationAI = ""
        explainError = nil
        await loadSourceNames(for: file)
        let source = inspectorSourceNames[file], addons = app.addonsFolder, known = addonFolders
        let built = await Task.detached { () -> SVExplanation in
            let base = String(file.dropLast(4)).lowercased()
            let folder = known?[base] ?? SavedVariablesAudit.saverFolders(addons)[base]
            let sources = folder.map(SVSourceNames.sourceTexts(folder:)) ?? []
            return SVExplanation.build(key: key, parent: parent, source: source, sources: sources)
        }.value
        guard explainTarget == target else { return }
        explanation = built
    }

    /// The Inspector's selected key.
    func explainSelection() async {
        guard let file = inspectorFile, let node = inspectorSelectedNode else { return }
        await explain(file: file, key: node.key, parent: node.parentPath)
    }

    /// A setting on the Characters tab.
    func explain(file: String, setting: SettingsMatrix.Setting) async {
        await explain(file: file, key: setting.key, parent: Array(setting.path.dropLast()))
    }

    /// Streams a short explanation from the configured AI, from the facts and source lines only.
    func explainWithAI() async {
        guard let target = explainTarget, let explanation, !explainingWithAI else { return }
        explainError = nil
        explanationAI = ""
        explainingWithAI = true
        defer { explainingWithAI = false }
        let table = ([target.file] + target.parent.map(\.description)).joined(separator: " › ")
        do {
            _ = try await AIClient(config: app.prefs.aiConfig).stream(
                system: SVExplanation.system, prompt: explanation.prompt(addon: app.addonName(target.file), table: table)
            ) { text in
                await MainActor.run { if self.explainTarget == target { self.explanationAI = text } }
            }
        } catch {
            if explainTarget == target { explainError = error.localizedDescription }
        }
    }
}
