import AppKit
import MacMinionKit
import SwiftUI

/// Backups in Minion's folder and format: settings and SavedVariables zips with an addon list, plus
/// Minion's initial full AddOns backup. Either app can restore the other's.
struct BackupsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedBackupID) {
            if let file = model.backupFocus { RestoreOneFileSection(file: file) }
            Section {
                ForEach(model.backups) { backup in
                    BackupRow(backup: backup).readableRow().tag(backup.id)
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
                .help("Show the backup folder in Finder (Option-Command-B)")
            }
        }
        .sheet(item: $model.pendingRestore) { RestoreSheet(backup: $0) }
        .alert("Move the backup from \(model.pendingBackupDeletion?.title ?? "") to the Trash?",
               isPresented: Binding(get: { model.pendingBackupDeletion != nil }, set: { if !$0 { model.pendingBackupDeletion = nil } }),
               presenting: model.pendingBackupDeletion) { backup in
            Button("Move to Trash", role: .destructive) { model.deleteBackup(backup) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its zip and addon list go to the Trash. You can put them back from there.")
        }
        .task { model.loadBackups() }
    }

    private var footer: String {
        let schedule = model.prefs.backupSchedule
        let keep = model.prefs.backupsToKeep
        let first = switch (schedule, keep) {
        case (.off, _): String(localized: "Automatic backups are off.")
        case (.daily, 0): String(localized: "Backs up every day, keeping all of them.")
        case (.daily, _): String(localized: "Backs up every day, keeping the newest \(keep).")
        case (.weekly, 0): String(localized: "Backs up every week, keeping all of them.")
        case (.weekly, _): String(localized: "Backs up every week, keeping the newest \(keep).")
        }
        return first + " " + String(localized: "Minion uses this folder too. Change it in Settings > Backups.")
    }
}

/// Putting back one damaged file (from Problems): the backups that hold it, newest first, each with a button
/// that restores only that file.
private struct RestoreOneFileSection: View {
    @Environment(AppModel.self) private var model
    let file: String

    var body: some View {
        Section {
            if let holding = model.backupsHoldingFocus {
                let matching = model.backups.filter { holding.contains($0.id) }
                if matching.isEmpty {
                    Text("No backup has \(file) yet.").foregroundStyle(.secondary)
                }
                // Their own IDs: the list below shows the same backups, and shared IDs make the list reuse those rows.
                ForEach(matching, id: \.restoreFileRowID) { backup in
                    HStack(spacing: Space.md) {
                        Label(backup.title, systemImage: backup.kind == .initial ? "archivebox.fill" : "clock.arrow.circlepath")
                        Spacer()
                        Button("Restore This File") { Task { await model.restoreFile(file, from: backup) } }
                            .disabled(model.backupBusy != nil || model.gameIsRunning)
                            .help(model.gameIsRunning ? "Quit Elder Scrolls Online first"
                                  : String(localized: "Save what you have now, then put back \(file) from this backup"))
                    }
                    .readableRow()
                }
            } else {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Looking through your backups…").foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Restore \(file)")
                Spacer()
                Button("Done") { model.backupFocus = nil }
                    .keyboardShortcut(.cancelAction)
                    .help("Stop restoring this file and show every backup")
            }
            .readableRow()
        } footer: {
            Text("Puts back this one file and leaves your other files as they are. First, MacMinion saves what you have now in \(model.restoreSafetyFolder.path(percentEncoded: false)).")
                .foregroundStyle(.secondary)
        }
    }
}

extension Backup {
    fileprivate var restoreFileRowID: String { "restore-file|" + id }

    /// "Saturday, 7 November 2026", or "Minion's First Backup".
    var title: String {
        if kind == .initial { return String(localized: "Minion's First Backup") }
        return date?.formatted(date: .complete, time: .omitted) ?? name
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
                Button("Move to Trash…", role: .destructive) { model.pendingBackupDeletion = backup }
            }
        }
    }

    private var title: String { backup.title }

    private var detail: String {
        if backup.kind == .initial {
            return String(localized: "The whole AddOns folder · \(backup.bytes.formatted(.byteCount(style: .file)))")
                + (backup.date.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
        }
        let count = backup.addonIDs.count
        var parts = [String(localized: "\(count) addons")]
        if backup.zip != nil { parts.append(String(localized: "settings and SavedVariables, \(backup.bytes.formatted(.byteCount(style: .file)))")) }
        else { parts.append(String(localized: "addon list only")) }
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
                        Text(backup.kind == .initial ? String(localized: "AddOns folders from the backup") : String(localized: "SavedVariables and settings files"))
                        Text(backup.kind == .initial ? String(localized: "Each addon folder in the backup replaces the one you have; yours go to the Trash.")
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
                .disabled(model.gameIsRunning || (!options.files && !options.reinstallMissing && !options.removeOthers))
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
                LabeledContent("Keep", value: prefs.backupsToKeep == 0 ? String(localized: "Every backup") : String(localized: "Newest \(prefs.backupsToKeep)"))
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
        panel.prompt = String(localized: "Use Folder")
        if panel.runModal() == .OK, let url = panel.url {
            model.prefs.backupDir = url.path
            model.loadBackups()
        }
    }
}
