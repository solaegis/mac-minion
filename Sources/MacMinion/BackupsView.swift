import AppKit
import MacMinionKit
import SwiftUI

/// Backups in Minion's folder and format: settings and SavedVariables zips with an addon list, plus
/// Minion's initial full AddOns backup. Either app can restore the other's.
struct BackupsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                ForEach(model.backups) { backup in
                    BackupRow(backup: backup)
                }
            } header: {
                Text(model.prefs.backupFolder.appending(path: "minion-backups/\(model.prefs.backupGameID)").path(percentEncoded: false))
                    .textSelection(.enabled)
            } footer: {
                Text(footer).foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { BackupBanner() }
        .overlay {
            if model.backups.isEmpty {
                ContentUnavailableView {
                    Label("No Backups Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("A backup holds your SavedVariables, AddOnSettings.txt, UserSettings.txt, and the list of installed addons, in Minion's format.")
                } actions: {
                    Button("Back Up Now") { Task { await model.backUp() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Backups")
        .toolbar {
            ToolbarItem {
                Button("Back Up Now", systemImage: "plus.circle") { Task { await model.backUp() } }
                    .disabled(model.backupBusy != nil)
                    .help("Back up settings, SavedVariables, and the addon list now (Command-B)")
            }
            ToolbarItem {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.prefs.backupFolder])
                }
                .help("Show the backup folder in Finder")
            }
        }
        .sheet(item: $model.pendingRestore) { RestoreSheet(backup: $0) }
        .task { model.loadBackups() }
    }

    private var footer: String {
        let schedule = model.prefs.backupSchedule
        let keep = model.prefs.backupsToKeep
        return (schedule == .off ? "Automatic backups are off." : "Backs up \(schedule.title.lowercased()), keeping the newest \(keep == 0 ? "all" : String(keep)).")
            + " Minion uses this folder too. Change it in Settings > Backups."
    }
}

/// Progress, the last result, or an error, above the list.
private struct BackupBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let busy = model.backupBusy {
            banner { ProgressView().controlSize(.small); Text(busy) }
        } else if let error = model.backupError {
            banner { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.negative) }
        } else if let message = model.backupMessage {
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

private struct BackupRow: View {
    @Environment(AppModel.self) private var model
    let backup: Backup

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: backup.kind == .initial ? "archivebox.fill" : "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(Palette.accentText)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore…") { model.pendingRestore = backup }
                .disabled(model.backupBusy != nil)
        }
        .padding(.vertical, Space.xs)
        .contextMenu {
            Button("Restore…") { model.pendingRestore = backup }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([backup.zip ?? backup.addonList].compactMap { $0 })
            }
            if backup.kind == .snapshot {
                Divider()
                Button("Move to Trash", role: .destructive) { model.deleteBackup(backup) }
            }
        }
    }

    private var title: String {
        if backup.kind == .initial { return "Minion's First Backup" }
        return backup.date?.formatted(date: .complete, time: .omitted) ?? backup.name
    }

    private var detail: String {
        if backup.kind == .initial {
            return "The whole AddOns folder · \(backup.bytes.formatted(.byteCount(style: .file)))"
                + (backup.date.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
        }
        let count = backup.addonIDs.count
        var parts = ["\(count) addons"]
        if backup.zip != nil { parts.append("settings and SavedVariables, \(backup.bytes.formatted(.byteCount(style: .file)))") }
        else { parts.append("addon list only") }
        return parts.joined(separator: " · ")
    }
}

/// What to bring back, and a warning when ESO is running.
private struct RestoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let backup: Backup
    @State private var options = AppModel.RestoreOptions()

    var body: some View {
        let list = Set(backup.addonIDs)
        let missing = list.filter { model.installed($0) == nil && model.catalogAddon($0) != nil }.count
        let extra = list.isEmpty ? 0 : model.installed.filter { !list.contains($0.id) }.count
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Restore \(backup.kind == .initial ? "Minion's First Backup" : backup.name)?").font(.title2.bold())
            Form {
                if backup.zip != nil {
                    Toggle(isOn: $options.files) {
                        Text(backup.kind == .initial ? "AddOns folders from the backup" : "SavedVariables and settings files")
                        Text(backup.kind == .initial ? "Each addon folder in the backup replaces the one you have; yours go to the Trash."
                             : "Replaces your SavedVariables, AddOnSettings.txt, and UserSettings.txt with the backup's.")
                    }
                }
                if !list.isEmpty {
                    Toggle(isOn: $options.reinstallMissing) {
                        Text("Install missing addons (\(missing))")
                        Text("Addons on the backup's list that aren't installed now, at their latest version.")
                    }
                    .disabled(missing == 0)
                    Toggle(isOn: $options.removeOthers) {
                        Text("Remove addons not in the backup (\(extra))")
                        Text("Moves them to the Trash. Their saved settings stay.")
                    }
                    .disabled(extra == 0)
                }
            }
            .formStyle(.grouped)
            if model.gameIsRunning {
                Label("Quit Elder Scrolls Online first: it writes SavedVariables when it quits and would undo the restore.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.negative)
            }
            Text("Before restoring, MacMinion saves what you have now in \(model.restoreSafetyFolder.path(percentEncoded: false)).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") {
                    dismiss()
                    Task { await model.restore(backup, options: options) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!options.files && !options.reinstallMissing && !options.removeOthers)
            }
        }
        .padding(Space.xxl)
        .frame(width: 520)
        .fitsContent()
        .noInitialFocus()
    }
}

struct BackupSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Section {
            LabeledContent("Folder") {
                Text(prefs.backupFolder.path(percentEncoded: false)).lineLimit(1).truncationMode(.head)
            }
            HStack {
                Button("Use Minion's Folder") { prefs.backupDir = MinionImport.read()?.backupDir ?? "~/.minion"; model.loadBackups() }
                Spacer()
                Button("Choose…", action: choose)
            }
            TextField("Game name", text: $prefs.backupGameID, prompt: Text("ESO-1"))
                .onSubmit { model.loadBackups() }
        } header: {
            Text("Where")
        } footer: {
            Text("Backups go in <folder>/minion-backups/<game name>, as Minion keeps them, so either app can restore the other's.")
                .foregroundStyle(.secondary)
        }
        Section("When") {
            Picker("Back up automatically", selection: $prefs.backupSchedule) {
                ForEach(BackupSchedule.allCases) { Text($0.title).tag($0) }
            }
            Stepper(value: $prefs.backupsToKeep, in: 0...60) {
                LabeledContent("Keep", value: prefs.backupsToKeep == 0 ? "Every backup" : "Newest \(prefs.backupsToKeep)")
            }
            Button("Back Up Now") { Task { await model.backUp() } }
                .disabled(model.backupBusy != nil)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.prefs.backupFolder
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.prefs.backupDir = url.path
            model.loadBackups()
        }
    }
}
