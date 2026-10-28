import AppKit
import MacMinionKit
import ServiceManagement
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .updates: UpdateSettings()
            case .ai: AISettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 560)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, updates, ai, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .updates: "Updates"
        case .ai: "AI"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .updates: "arrow.down.circle"
        case .ai: "sparkles"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            LabeledContent("Folder") {
                Text(model.addonsFolder.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.addonsFolder.path(percentEncoded: false))
            }
            HStack {
                Button("Live") { model.addonsFolder = AddonsLocation.live }
                Button("PTS") { model.addonsFolder = AddonsLocation.pts }
                Spacer()
                Button("Show in Finder") { model.showInFinder() }
                Button("Choose…", action: choose)
            }
        } header: {
            Text("AddOns Folder")
        } footer: {
            Text("NA and EU share the live folder.").foregroundStyle(.secondary)
        }
        Section("App") {
            Toggle("Show in menu bar", isOn: $prefs.showMenuBarItem)
            Toggle("Open at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { setOpenAtLogin(openAtLogin) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
        }
        Section {
            Button("Import from Minion") { model.importFromMinionIfNeeded(force: true) }
        } header: {
            Text("Minion")
        } footer: {
            Text("Reads installed versions and the update log from ~/.minion/minion.xml. Minion's own files stay as they are.")
                .foregroundStyle(.secondary)
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        guard !Store.isOverridden else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change it: \(error.localizedDescription)"
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.addonsFolder
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { model.addonsFolder = url }
    }
}

struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            Toggle("Check for updates automatically", isOn: $prefs.checkAutomatically)
            Picker("Check", selection: $prefs.checkInterval) {
                ForEach(CheckInterval.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!prefs.checkAutomatically)
        } header: {
            Text("Checking")
        } footer: {
            Text("MacMinion also checks each time it opens.").foregroundStyle(.secondary)
        }
        Section {
            Toggle("Install updates automatically", isOn: $prefs.autoUpdate)
            Stepper(value: $prefs.concurrentUpdates, in: 1...4) {
                LabeledContent("Downloads at once", value: "\(prefs.concurrentUpdates)")
            }
            Toggle("Notify me when updates are ready", isOn: $prefs.notifyUpdates)
                .disabled(prefs.autoUpdate)
        } header: {
            Text("Installing")
        } footer: {
            Text("Automatic installs skip addons marked Ignore Updates. Turn off Minion's own auto-update so the two apps don't both write to AddOns.")
                .foregroundStyle(.secondary)
        }
    }
}

struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var ollamaModels: [String] = []
    @State private var loadingModels = false
    @State private var testResult: String?
    @State private var testFailed = false
    @State private var testing = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            Picker("Provider", selection: $prefs.aiProvider) {
                ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Summarize changes when I open an addon with an update", isOn: $prefs.summarizeOnOpen)
                .disabled(!prefs.aiEnabled)
        } header: {
            Text("Assistant")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }

        switch prefs.aiProvider {
        case .off:
            EmptyView()
        case .ollama:
            Section("Ollama") {
                TextField("Server", text: $prefs.ollamaURL, prompt: Text(AIConfig.defaultOllamaURL.absoluteString))
                    .onSubmit { Task { await loadModels() } }
                HStack {
                    Picker("Model", selection: $prefs.ollamaModel) {
                        if prefs.ollamaModel.isEmpty { Text("Choose…").tag("") }
                        ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Refresh Models", systemImage: "arrow.clockwise") { Task { await loadModels() } }
                        .labelStyle(.iconOnly)
                        .disabled(loadingModels)
                        .help("Ask Ollama which models are installed")
                }
                testRow
            }
            .task { await loadModels() }
        case .claude:
            Section {
                SecureField("API Key", text: $prefs.claudeKey, prompt: Text("sk-ant-…"))
                Picker("Model", selection: $prefs.claudeModel) {
                    ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                }
                testRow
            } header: {
                Text("Claude")
            } footer: {
                Text("The key is kept in your login Keychain. Create one at console.anthropic.com.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: String {
        switch model.prefs.aiProvider {
        case .off: "Summaries of addon changelogs. Nothing is sent anywhere while this is off."
        case .ollama: "Changelogs stay on this Mac. Ollama must be running."
        case .claude: "Changelog text is sent to Anthropic to write each summary."
        }
    }

    private var modelChoices: [String] {
        let current = model.prefs.ollamaModel
        return current.isEmpty || ollamaModels.contains(current) ? ollamaModels : [current] + ollamaModels
    }

    private var testRow: some View {
        HStack(spacing: Space.sm) {
            Button("Test Connection") { Task { await test() } }
                .disabled(testing || model.prefs.aiConfig.problem != nil)
            if testing {
                ProgressView().controlSize(.small)
            } else if let testResult {
                Label(testResult, systemImage: testFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(testFailed ? .red : .green)
                    .lineLimit(2)
            }
        }
    }

    private func loadModels() async {
        guard !Store.isOverridden else {
            ollamaModels = ["llama3.2", "qwen3:8b"]
            return
        }
        loadingModels = true
        defer { loadingModels = false }
        do {
            ollamaModels = try await AIClient.ollamaModels(at: model.prefs.aiConfig.ollamaURL)
            if model.prefs.ollamaModel.isEmpty, let first = ollamaModels.first { model.prefs.ollamaModel = first }
            testResult = nil
        } catch {
            ollamaModels = []
            testResult = "Can't reach Ollama at \(model.prefs.ollamaURL)"
            testFailed = true
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            testResult = try await model.testAI()
            testFailed = false
        } catch {
            testResult = error.localizedDescription
            testFailed = true
        }
    }
}
