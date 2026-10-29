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
            case .layout: LayoutSettings()
            case .backups: BackupSettings()
            case .ai: AISettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        // The standard round help button, opening this tab's page in the docs.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                HelpLink { Docs.open(Docs.page(for: tab)) }
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.md)
        }
        .fitsContent()
        .frame(width: 560)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, updates, layout, backups, ai, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .updates: "Updates"
        case .layout: "Layout"
        case .backups: "Backups"
        case .ai: "AI"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .updates: "arrow.down.circle"
        case .layout: "square.grid.3x2"
        case .backups: "clock.arrow.circlepath"
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
                Text(loginError).font(.caption).foregroundStyle(Palette.negative)
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
        AppUpdateSettings()
        Section {
            Toggle("Check for updates automatically", isOn: $prefs.checkAutomatically)
            Picker("Check", selection: $prefs.checkInterval) {
                ForEach(CheckInterval.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!prefs.checkAutomatically)
        } header: {
            Text("Addon Checks")
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
            Text("Addon Installs")
        } footer: {
            Text("Automatic installs skip addons marked Ignore Updates. Turn off Minion's own auto-update so the two apps don't both write to AddOns.")
                .foregroundStyle(.secondary)
        }
    }
}

struct LayoutSettings: View {
    @Environment(AppModel.self) private var model
    @State private var customizing = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            LabeledContent("Sections") {
                Text("\(prefs.visibleOverview.count) of \(OverviewSection.allCases.count) shown")
            }
            HStack {
                Button("Customize Overview…") { customizing = true }
                Spacer()
                Button("Reset to Default") { prefs.resetOverview() }
            }
        } header: {
            Text("Overview")
        } footer: {
            Text("Choose the sections and drag them into order. You can also right-click a section on the Overview.")
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $customizing) { OverviewCustomizeSheet() }
        Section {
            Picker("Installed", selection: $prefs.installedLayout) {
                ForEach(BrowseLayout.allCases) { Text($0.title).tag($0) }
            }
            Picker("Find More", selection: $prefs.findMoreLayout) {
                ForEach(BrowseLayout.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Show As")
        } footer: {
            Text("Switch any time from the toolbar, or with Option-Command-1 and Option-Command-2.")
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Card size", selection: $prefs.cardSize) {
                ForEach(CardSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show preview images", isOn: $prefs.showThumbnails)
        } header: {
            Text("Cards")
        }
        Section {
            Toggle("Put updates first, as wide cards", isOn: $prefs.featureUpdates)
            Toggle("Group libraries in their own section", isOn: $prefs.groupLibraries)
            Toggle("Show the top four Find More results above the grid", isOn: $prefs.featurePopular)
        } header: {
            Text("Grid")
        } footer: {
            Text("Featured addons get wide cards in their own section; every card in the main grid is the same size. Find More features the top four only while it isn't searching or sorting by name.")
                .foregroundStyle(.secondary)
        }
        .disabled(prefs.installedLayout == .list && prefs.findMoreLayout == .list)
    }
}

struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var ollamaModels: [OllamaModel] = []
    @State private var loadedModels: Set<String> = []
    @State private var host = HostProfile.current()
    @State private var benchmarking: String?
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
                LabeledContent("This Mac", value: host.summary)
                if let pick = recommendation {
                    LabeledContent {
                        if pick.model == prefs.ollamaModel {
                            Label("In use", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.positive)
                        } else {
                            Button("Use \(pick.model)") { prefs.ollamaModel = pick.model }
                        }
                    } label: {
                        Text("Recommended: \(pick.model)")
                        Text(pick.reason)
                    }
                }
                HStack(spacing: Space.sm) {
                    Button("Benchmark Top Models") { Task { await benchmark() } }
                        .disabled(benchmarking != nil || ollamaModels.isEmpty)
                        .help("Write a short summary with the three best candidates and measure their speed on this Mac")
                    if let benchmarking {
                        ProgressView().controlSize(.small)
                        Text("Testing \(benchmarking)…").font(.caption).foregroundStyle(.secondary)
                    } else if !speedLine.isEmpty {
                        Text(speedLine).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                testRow
            }
            .task { await loadModels() }
        case .claude:
            KeyedProviderSection(provider: .claude, model: $prefs.claudeModel)
                .id(AIProvider.claude)
        case .openai:
            KeyedProviderSection(provider: .openai, model: $prefs.openAIModel)
                .id(AIProvider.openai)
        }
    }

    private var footer: String {
        switch model.prefs.aiProvider {
        case .off: "Summaries of addon changelogs. Nothing is sent anywhere while this is off."
        case .ollama: "Changelogs stay on this Mac. Ollama must be running."
        case .claude: "Addon names and changelog text are sent to Anthropic, and nowhere else."
        case .openai: "Addon names and changelog text are sent to OpenAI, and nowhere else."
        }
    }

    private var recommendation: ModelAdvisor.Pick? {
        ModelAdvisor.recommend(ollamaModels, host: host, loaded: loadedModels, speeds: model.prefs.modelSpeeds)
    }

    /// "gemma4 44 tok/s · phi4 31 tok/s", for models measured on this Mac.
    private var speedLine: String {
        ollamaModels.compactMap { m in
            model.prefs.modelSpeeds[m.name].map { String(format: "%@ %.0f tok/s", m.name.replacingOccurrences(of: ":latest", with: ""), $0.tokensPerSecond) }
        }.joined(separator: " · ")
    }

    /// Measures the three best candidates, one at a time.
    private func benchmark() async {
        let base = model.prefs.aiConfig.ollamaURL
        for candidate in ModelAdvisor.rank(ollamaModels, host: host, loaded: loadedModels).prefix(3) {
            benchmarking = candidate.name
            if let speed = try? await AIClient.benchmark(candidate.name, at: base) {
                model.prefs.modelSpeeds[candidate.name] = speed
            }
        }
        benchmarking = nil
        host = HostProfile.current()
        loadedModels = await AIClient.loadedModels(at: base)
    }

    private var modelChoices: [String] {
        let names = ollamaModels.map(\.name)
        let current = model.prefs.ollamaModel
        return current.isEmpty || names.contains(current) ? names : [current] + names
    }

    private var testRow: some View {
        HStack(spacing: Space.sm) {
            Button("Test Connection") { Task { await test() } }
                .disabled(testing || model.prefs.aiConfig.problem != nil)
            if testing {
                ProgressView().controlSize(.small)
            } else if let testResult {
                Label(testResult, systemImage: testFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(testFailed ? Palette.negative : Palette.positive)
                    .lineLimit(2)
            }
        }
    }

    private func loadModels() async {
        guard !Store.isOverridden else {
            ollamaModels = [OllamaModel(name: "llama3.2", bytes: 2_000_000_000, family: "llama", billions: 3.2),
                            OllamaModel(name: "phi4:latest", bytes: 9_100_000_000, family: "phi3", billions: 14.7, contextLength: 16_384)]
            return
        }
        loadingModels = true
        defer { loadingModels = false }
        do {
            ollamaModels = try await AIClient.ollamaModels(at: model.prefs.aiConfig.ollamaURL)
            loadedModels = await AIClient.loadedModels(at: model.prefs.aiConfig.ollamaURL)
            host = HostProfile.current()
            if model.prefs.ollamaModel.isEmpty, let pick = recommendation?.model ?? ollamaModels.first?.name {
                model.prefs.ollamaModel = pick
            }
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

/// API key, model, and connection status for a hosted provider (Claude, OpenAI).
struct KeyedProviderSection: View {
    let provider: AIProvider
    @Binding var model: String
    @Environment(AppModel.self) private var app
    @State private var keyDraft = ""
    @State private var status = ConnectionStatus.untested
    @State private var keychainFailed = false
    @State private var fetched: [String] = []
    @State private var loadingModels = false
    @State private var listIsCached = false

    private var llm: any LLMProvider {
        provider == .claude ? AnthropicProvider(key: app.prefs.claudeKey) : OpenAIProvider(key: app.prefs.openAIKey)
    }
    private var hasKey: Bool { !app.prefs.apiKey(for: provider).isEmpty }

    var body: some View {
        Section {
            LabeledContent("Status") {
                if status == .testing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(shownStatus.title, systemImage: symbol).foregroundStyle(color).lineLimit(2)
                }
            }
            SecureField("API Key", text: $keyDraft, prompt: Text(hasKey ? "Saved in Keychain" : keyPrompt))
                .onSubmit(save)
            HStack(spacing: Space.sm) {
                Spacer()
                Button("Remove Key", role: .destructive) {
                    app.prefs.removeKey(for: provider)
                    status = .noKey
                }
                .disabled(!hasKey)
                Button("Save to Keychain", action: save)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: Space.sm) {
                TextField("Model", text: $model, prompt: Text(llm.defaultModel))
                Menu("Choose Model", systemImage: "list.bullet") {
                    ForEach(modelChoices, id: \.self) { id in
                        Button(title(id)) { model = id }
                    }
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pick from the models \(llm.displayName) offers")
                if loadingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh Models", systemImage: "arrow.clockwise") { Task { await loadModels() } }
                        .labelStyle(.iconOnly)
                        .disabled(!hasKey)
                        .help("Ask \(llm.displayName) which models this key can use")
                }
            }
            Button("Test Connection") { Task { await test() } }
                .disabled(status == .testing || app.prefs.aiConfig.problem != nil)
        } header: {
            Text(llm.displayName)
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .onAppear {
            status = hasKey ? .untested : .noKey
            fetched = app.prefs.cachedModels[provider] ?? []
        }
    }

    private var keyPrompt: String { provider == .claude ? "sk-ant-…" : "sk-…" }

    private var footer: String {
        let site = provider == .claude ? "console.anthropic.com" : "platform.openai.com"
        var text = "The key is kept in your login Keychain, for this Mac user only, and sent only to \(llm.displayName). Create one at \(site). Model IDs change: choose one from the list or type it."
        if keychainFailed { text = "The Keychain didn't save the key. " + text }
        if listIsCached { text += " Showing the last model list; \(llm.displayName) couldn't be reached." }
        return text
    }

    private var shownStatus: ConnectionStatus { hasKey ? status : .noKey }

    private var symbol: String {
        switch shownStatus {
        case .connected: "checkmark.circle.fill"
        case .invalidKey, .failed: "xmark.circle.fill"
        case .rateLimited: "clock.badge.exclamationmark"
        case .noKey: "key"
        case .untested, .testing: "circle.dashed"
        }
    }

    private var color: Color {
        switch shownStatus {
        case .connected: Palette.positive
        case .invalidKey, .failed, .rateLimited: Palette.negative
        default: .secondary
        }
    }

    /// Fetched or cached models, else the known defaults, with the current model kept in the list.
    private var modelChoices: [String] {
        let list = fetched.isEmpty ? llm.availableModels : fetched
        return model.isEmpty || list.contains(model) ? list : [model] + list
    }

    private func title(_ id: String) -> String {
        provider == .claude ? AnthropicProvider.title(for: id) : OpenAIProvider.title(for: id)
    }

    private func save() {
        keychainFailed = !app.prefs.saveKey(keyDraft, for: provider)
        guard !keychainFailed else { return }
        keyDraft = ""
        status = .untested
        Task { await loadModels() }
    }

    private func loadModels() async {
        guard hasKey, !Store.isOverridden else { return }
        loadingModels = true
        defer { loadingModels = false }
        do {
            fetched = try await llm.fetchModels()
            app.prefs.cachedModels[provider] = fetched
            listIsCached = false
        } catch {
            fetched = app.prefs.cachedModels[provider] ?? []
            listIsCached = !fetched.isEmpty
            if case .invalidKey = ConnectionStatus(error) { status = .invalidKey }
        }
    }

    private func test() async {
        status = .testing
        do {
            _ = try await app.testAI()
            status = .connected
        } catch {
            status = ConnectionStatus(error)
        }
    }
}
