import AppKit
import MacMinionKit
import SwiftUI

extension AppModel {
    /// The details column can open: an addon or folder is selected on a page that has one.
    var inspectorAvailable: Bool {
        selection != nil && sidebar != .overview && sidebar != .backups && sidebar != .gameFolder
    }

    /// The addon selected on Installed, Updates, or Find More, for the Addons menu.
    var selectedAddonID: Int? {
        guard sidebar == .installed || sidebar == .updates || sidebar == .findMore,
              case .addon(let id)? = selection else { return nil }
        return id
    }
}

/// The Addons menu's items for the selected addon: the same actions as its context menu and detail panel,
/// so none of them is only a click away (design/MACOS-UI-ARCHITECTURE.md, section 4).
struct SelectedAddonCommands: View {
    let model: AppModel

    var body: some View {
        let id = model.selectedAddonID
        let installed = id.flatMap(model.installed)
        let catalog = id.flatMap(model.catalogAddon)
        let title = switch installed?.status {
        case nil: String(localized: "Install")
        case .updateAvailable: String(localized: "Update")
        default: String(localized: "Reinstall")
        }
        Button(title) { if let id { Task { await model.install(id) } } }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(id == nil || id.map(model.busy.contains) == true || (installed == nil && catalog == nil))
        Toggle("Ignore Updates", isOn: Binding(get: { installed?.record.ignored ?? false },
                                               set: { if let id { model.setIgnored(id, $0) } }))
            .keyboardShortcut("u", modifiers: [.command, .control])
            .disabled(installed == nil)
        Toggle("Thumbs Up", isOn: Binding(get: { id.map { model.rating($0) == .up } ?? false },
                                          set: { if let id { model.setRating(id, $0 ? .up : nil) } }))
            .keyboardShortcut(.upArrow, modifiers: [.command, .option, .control])
            .disabled(id == nil)
        Toggle("Thumbs Down", isOn: Binding(get: { id.map { model.rating($0) == .down } ?? false },
                                            set: { if let id { model.setRating(id, $0 ? .down : nil) } }))
            .keyboardShortcut(.downArrow, modifiers: [.command, .option, .control])
            .disabled(id == nil)
        Button("Open on ESOUI") { if let url = installed?.catalog.infoURL ?? catalog?.infoURL { NSWorkspace.shared.open(url) } }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled((installed?.catalog.infoURL ?? catalog?.infoURL) == nil)
        Button("Show Addon in Finder") { model.showInFinder(installed?.record.dirs.first) }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(installed == nil)
        Button("Remove Addon…") { model.pendingRemoval = installed }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(installed == nil || id.map(model.busy.contains) == true)
    }
}

/// The Addons menu's items for Backups.
struct BackupCommands: View {
    let model: AppModel

    var body: some View {
        let backup = model.sidebar == .backups ? model.selectedBackup : nil
        Button("Restore Backup…") { model.pendingRestore = backup }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(backup == nil || model.backupBusy != nil)
        Button("Move Backup to Trash…") { model.pendingBackupDeletion = backup }
            .keyboardShortcut("b", modifiers: [.command, .option, .shift])
            .disabled(backup?.kind != .snapshot || model.backupBusy != nil)
        Button("Show Backups in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.prefs.backupFolder]) }
            .keyboardShortcut("b", modifiers: [.command, .option])
    }
}

/// The View menu's items for the inspector, Overview, and filters.
struct PageViewCommands: View {
    let model: AppModel

    var body: some View {
        Button(model.inspectorHidden || !model.inspectorAvailable ? String(localized: "Show Inspector") : String(localized: "Hide Inspector")) {
            model.inspectorHidden.toggle()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(!model.inspectorAvailable)
        Button("Customize Overview…") { model.open(.overview); model.customizingOverview = true }
            .keyboardShortcut("o", modifiers: [.command, .option])
        let scope: FilterScope? = model.sidebar == .installed ? .installed : model.sidebar == .findMore ? .findMore : nil
        Menu("Filter") {
            if let scope { FilterMenuItems(scope: scope).environment(model) }
        }
        .disabled(scope == nil)
    }
}
