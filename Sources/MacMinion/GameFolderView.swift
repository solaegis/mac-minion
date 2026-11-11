import AppKit
import MacMinionKit
import SwiftUI

/// The Game Folder page's tabs (S-064): characters first, then one file's contents, what's wrong, and the
/// game's own settings files.
enum GameFolderTab: String, CaseIterable, Identifiable {
    case characters, inspector, problems, gameSettings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .characters: String(localized: "Characters")
        case .inspector: String(localized: "Inspector")
        case .problems: String(localized: "Problems")
        case .gameSettings: String(localized: "Game Settings")
        }
    }

    static let top: [GameFolderTab] = allCases
}

/// Files waiting for a yes before they go to the Trash.
struct TrashRequest: Identifiable {
    let id = UUID()
    let title: String
    let urls: [URL]
    let bytes: Int64
}

/// Everything beside AddOns: characters, one file's contents, what's wrong, and the game's settings files.
struct GameFolderPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.gameFolder.tab {
            case .characters: CharactersExplorer(model: model)
            case .inspector: InspectorView()
            case .problems: ProblemsView()
            case .gameSettings: GameSettingsView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                GameFolderTabBar()
                GameFolderBanner()
            }
        }
        .navigationTitle("Game Folder")
        .toolbar {
            ToolbarItem { PageHelpButton() }
            ToolbarItem {
                // Problems lists the same files as Clean up findings, so the question opens there.
                Button("Clean Up…", systemImage: "trash") { model.gameFolder.tab = .problems; model.gameFolder.askToTidy() }
                    .labelStyle(.iconOnly)
                    .disabled(model.gameFolder.tidyableSavedVariables.isEmpty || model.backupBusy != nil)
                    .help("Move SavedVariables files no installed addon uses, and copies of them, to the Trash (Shift-Command-T)")
            }
            ToolbarItem {
                Button("Show in Finder", systemImage: "folder") { model.gameFolder.showInFinder() }
                    .labelStyle(.iconOnly)
                    .help("Show the game folder in Finder (Option-Command-G)")
            }
        }
        .alert(model.gameFolder.pendingTrash?.title ?? "", isPresented: Binding(get: { model.gameFolder.pendingTrash != nil },
                                                                     set: { if !$0 { model.gameFolder.pendingTrash = nil } }),
               presenting: model.gameFolder.pendingTrash) { request in
            Button("Back Up and Move to Trash", role: .destructive) { Task { await model.gameFolder.moveToTrash(request) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(String(localized: "MacMinion backs up SavedVariables and the settings files first, then moves \(request.bytes.formatted(.byteCount(style: .file))) to the Trash."))
        }
        .task { await model.gameFolder.scan(); await model.gameFolder.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.gameFolder.scan() }
        }
    }
}

/// Characters / Inspector / Problems / Game Settings — in the page, not the toolbar, so it stays
/// visible at the minimum window width.
private struct GameFolderTabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("View", selection: Binding(get: { model.gameFolder.tab }, set: { tab in
            model.gameFolder.tab = tab
            if tab == .characters { model.gameFolder.explorerReset() }
        })) {
            // Problems counts causes to act on, not raw checks.
            let findings = model.gameFolder.healthFindings.filter(\.isMain).count
            ForEach(GameFolderTab.top) { tab in
                let count = tab == .problems ? findings : 0
                Text(count > 0 ? "\(tab.title) (\(count))" : tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Your characters, one file's contents, what's wrong, or the game's settings files")
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.sm)
        .background(.bar)
    }
}

/// A warning while ESO runs, progress, or the last result.
private struct GameFolderBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.gameIsRunning {
            banner { Label("Quit Elder Scrolls Online to make changes.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.negative) }
        } else if let busy = model.backupBusy {
            banner { ProgressView().controlSize(.small); Text(busy) }
        } else if let error = model.gameFolder.errorMessage {
            banner { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.negative) }
        } else if let message = model.gameFolder.message {
            banner { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.positive) }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Space.sm) { content() }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.sm)
            .background(.bar)
    }
}

extension SavedVariablesFile {
    var ownerText: String {
        switch owner {
        case .addon(let name): name
        case .game: String(localized: "The game")
        case .none: String(localized: "No installed addon")
        case .copy: String(localized: "Your copy")
        case .other: String(localized: "Not saved by the game")
        }
    }

    var sortDate: Date { modified ?? .distantPast }
}
