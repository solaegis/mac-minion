import AppKit
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
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
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
                Button("Choose…", action: choose)
            }
        } header: {
            Text("AddOns Folder")
        } footer: {
            Text("NA and EU share the live folder.").foregroundStyle(.secondary)
        }
        Section("Updates") {
            Toggle("Check for updates every hour", isOn: $model.checkHourly)
            Toggle("Install updates automatically", isOn: $model.autoUpdate)
        }
        Section {
            Button("Import from Minion") { model.importFromMinionIfNeeded(force: true) }
        } header: {
            Text("Minion")
        } footer: {
            Text("Reads the installed versions from ~/.minion/minion.xml. Minion's own files stay as they are.")
                .foregroundStyle(.secondary)
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
