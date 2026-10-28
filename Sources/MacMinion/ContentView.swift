import MacMinionKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        Group {
            if model.sidebar == .overview {
                // The overview fills the window; it has no list or detail column.
                NavigationSplitView {
                    sidebar
                } detail: {
                    OverviewView()
                }
            } else {
                browser
            }
        }
        .navigationSubtitle(model.statusLine)
        .onChange(of: model.sidebar) { model.selection = model.pendingSelection; model.pendingSelection = nil }
        .alert(removalTitle, isPresented: removalShown, presenting: model.pendingRemoval) { addon in
            Button("Move to Trash", role: .destructive) { Task { await model.remove(addon) } }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("These folders go to the Trash: \(addon.record.dirs.joined(separator: ", ")). Saved settings stay.")
        }
        .task {
            await SeedData.insertIfRequested(into: model)
            await model.start()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var browser: some View {
        NavigationSplitView {
            sidebar
        } content: {
            Group {
                switch model.sidebar ?? .installed {
                case .installed, .overview: InstalledList()
                case .updates: UpdatesList()
                case .findMore: FindMoreList()
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            DetailColumn()
        }
    }

    private var removalTitle: String {
        "Move “\(model.pendingRemoval?.catalog.name ?? "")” to the Trash?"
    }

    private var removalShown: Binding<Bool> {
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .badge(badge(for: page))
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }

    private func badge(for page: SidebarItem) -> Int {
        switch page {
        case .installed: model.installed.count + model.unmatched.count
        case .updates: model.updates.count
        case .findMore, .overview: 0
        }
    }
}

// MARK: - Lists

struct InstalledList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("From ESOUI") {
                ForEach(model.installed) { addon in
                    AddonRow(addon: addon.catalog, installed: addon)
                        .tag(Selection.addon(addon.id))
                        .contextMenu { InstalledMenu(addon: addon) }
                }
            }
            if !model.unmatched.isEmpty {
                Section("Not on ESOUI") {
                    ForEach(model.unmatched) { folder in
                        FolderRow(folder: folder)
                            .tag(Selection.folder(folder.folder))
                            .contextMenu {
                                Button("Show in Finder") { model.showInFinder(folder.folder) }
                            }
                    }
                }
            }
        }
        .overlay {
            if model.installed.isEmpty && model.unmatched.isEmpty {
                ContentUnavailableView {
                    Label("No Addons Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text(model.catalog.isEmpty ? "The ESOUI catalog hasn't loaded yet." : "Nothing is installed in \(model.addonsFolder.path).")
                } actions: {
                    SettingsLink { Text("Choose Folder…") }
                }
            }
        }
        .navigationTitle("Installed")
        .toolbar { RefreshButton() }
    }
}

struct UpdatesList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(model.updates, selection: $model.selection) { addon in
            AddonRow(addon: addon.catalog, installed: addon)
                .tag(Selection.addon(addon.id))
                .contextMenu { InstalledMenu(addon: addon) }
        }
        .overlay {
            if model.updates.isEmpty {
                ContentUnavailableView("All Up to Date", systemImage: "checkmark.circle",
                                       description: Text("Every installed addon matches the latest version on ESOUI."))
            }
        }
        .navigationTitle("Updates")
        .sheet(isPresented: $model.showDigest) { DigestSheet() }
        .toolbar {
            RefreshButton()
            if model.prefs.aiEnabled {
                ToolbarItem {
                    Button("Summarize Updates", systemImage: "sparkles") { Task { await model.digestUpdates() } }
                        .disabled(model.updates.isEmpty || model.isDigesting)
                        .help("Ask the assistant what the pending updates bring (Option-Command-U)")
                }
            }
            ToolbarItem {
                Button("Update All", systemImage: "arrow.down.circle") { Task { await model.updateAll() } }
                    .disabled(model.updates.isEmpty || model.batch != nil)
                    .help("Update every addon that has an update (Command-U)")
            }
        }
    }
}

struct FindMoreList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let results = model.findMoreResults
        List(results, selection: $model.selection) { addon in
            AddonRow(addon: addon, installed: model.installed(addon.id))
                .tag(Selection.addon(addon.id))
        }
        .overlay {
            if results.isEmpty {
                if model.search.isEmpty {
                    ContentUnavailableView("No Addons", systemImage: "magnifyingglass")
                } else {
                    ContentUnavailableView.search(text: model.search)
                }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search addons or authors")
        .navigationTitle("Find More")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Category", selection: $model.category) {
                        Text("All Categories").tag(Int?.none)
                        Divider()
                        ForEach(model.categories.sorted { $0.title < $1.title }) { c in
                            Text(c.title).tag(Int?.some(c.id))
                        }
                    }
                    Picker("Sort By", selection: $model.sort) {
                        ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
                .help("Filter by category and choose the sort order")
            }
        }
    }
}

struct RefreshButton: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem {
            Button("Check for Updates", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isRefreshing || model.offline)
                .help("Download the ESOUI catalog again and look for updates (Command-R)")
        }
    }
}

struct InstalledMenu: View {
    @Environment(AppModel.self) private var model
    let addon: InstalledAddon

    var body: some View {
        Button(addon.status == .updateAvailable ? "Update" : "Reinstall") { Task { await model.install(addon.id) } }
            .disabled(model.busy.contains(addon.id))
        Toggle("Ignore Updates", isOn: Binding(get: { addon.record.ignored }, set: { model.setIgnored(addon.id, $0) }))
        Divider()
        Button("Show in Finder") { model.showInFinder(addon.record.dirs.first) }
        if let url = addon.catalog.infoURL {
            Link("Open on ESOUI", destination: url)
        }
        Divider()
        Button("Remove…", role: .destructive) { model.pendingRemoval = addon }
    }
}

// MARK: - Rows

struct AddonRow: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon
    let installed: InstalledAddon?

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(addon.name).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = model.errors[addon.id] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.sm)
            trailing
        }
        .padding(.vertical, Space.xs / 2)
    }

    private var subtitle: String {
        if let installed, let v = installed.installedVersion, !VersionText.same(v, addon.version) {
            return "\(addon.author) · \(v) → \(addon.version)"
        }
        return "\(addon.author) · \(addon.version)"
    }

    @ViewBuilder
    private var trailing: some View {
        if model.busy.contains(addon.id) {
            ProgressView().controlSize(.small)
        } else if let installed {
            switch installed.status {
            case .updateAvailable:
                Button("Update") { Task { await model.install(addon.id) } }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Up to date")
            case .ignored:
                Image(systemName: "bell.slash")
                    .foregroundStyle(.secondary)
                    .help("Updates are ignored")
            case .versionUnknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Installed outside MacMinion; reinstall to track its version")
            }
        } else if model.sidebar == .findMore {
            Text(addon.downloads.formatted(.number.notation(.compactName)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("\(addon.downloads.formatted()) downloads")
        }
    }
}

struct FolderRow: View {
    let folder: UnmatchedFolder

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs / 2) {
            Text(folder.title).lineLimit(1)
            Text([folder.manifest?.author, folder.manifest?.version, folder.folder].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, Space.xs / 2)
    }
}

// MARK: - Detail

struct DetailColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.selection {
        case .addon(let id):
            if let addon = model.catalogAddon(id) {
                AddonDetail(addon: addon).id(id)
            } else {
                none
            }
        case .folder(let name):
            if let folder = model.unmatched.first(where: { $0.folder == name }) {
                FolderDetail(folder: folder)
            } else {
                none
            }
        case nil:
            none
        }
    }

    private var none: some View {
        ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                               description: Text("Select an addon to see its details."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddonDetail: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon
    @State private var info: AddonDetails?
    @State private var loadError: String?

    private var installed: InstalledAddon? { model.installed(addon.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                facts
                if model.prefs.aiEnabled, info != nil, !(info?.changelog.isEmpty ?? true) {
                    SummaryCard(addon: addon)
                }
                if let error = model.errors[addon.id] {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if let info {
                    text("Description", BBCode.plainText(info.description))
                    text("Changes", BBCode.plainText(info.changelog))
                } else if let loadError {
                    Label(loadError, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("detail")
        }
        .task {
            do { info = try await model.loadDetails(addon.id) } catch { loadError = "Details aren't available offline." }
            if model.prefs.summarizeOnOpen, model.prefs.aiConfig.problem == nil, installed?.status == .updateAvailable,
               model.summaries[addon.id] == nil, info != nil {
                await model.summarize(addon.id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            AsyncImage(url: addon.thumbnails.first) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96, height: 96)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: Space.sm))

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(addon.name).font(.title2.bold()).textSelection(.enabled)
                Text("by \(addon.author)").foregroundStyle(.secondary)
                HStack(spacing: Space.sm) {
                    primaryButton
                    if let url = addon.infoURL {
                        Link(destination: url) { Text("Open on ESOUI") }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, Space.sm)
            }
            .gridProbe("title", area: "detail")
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.busy.contains(addon.id) {
            ProgressView().controlSize(.small)
        } else {
            let title = switch installed?.status {
            case nil: "Install"
            case .updateAvailable: "Update"
            default: "Reinstall"
            }
            Button(title) { Task { await model.install(addon.id) } }
                .buttonStyle(.borderedProminent)
                .disabled(model.offline && model.details[addon.id] == nil)
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
            row("Latest version", addon.version)
            if let installed {
                row("Installed", installed.installedVersion ?? "Unknown")
                row("Status", installed.status.label)
            }
            row("Updated", addon.date.formatted(date: .abbreviated, time: .omitted))
            row("Downloads", "\(addon.downloads.formatted()) (\(addon.downloadsMonthly.formatted()) this month)")
            row("Favorites", addon.favorites.formatted())
            if let category = model.categories.first(where: { $0.id == addon.categoryID }) {
                row("Category", category.title)
            }
            if !addon.compatibility.isEmpty {
                row("Works with", addon.compatibility.map { "\($0.name) (\($0.version))" }.joined(separator: ", "))
            }
            row("Folders", (installed?.record.dirs ?? addon.dirs).joined(separator: ", "))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func text(_ title: String, _ body: String) -> some View {
        if !body.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(.headline)
                Text(body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FolderDetail: View {
    @Environment(AppModel.self) private var model
    let folder: UnmatchedFolder

    var body: some View {
        Form {
            Section {
                LabeledContent("Title", value: folder.title)
                LabeledContent("Folder", value: folder.folder)
                if let author = folder.manifest?.author { LabeledContent("Author", value: author) }
                if let version = folder.manifest?.version { LabeledContent("Version", value: version) }
                if folder.manifest?.isLibrary == true { LabeledContent("Kind", value: "Library") }
            } footer: {
                Text("No ESOUI entry lists this folder, so MacMinion can't update it. Addons you build or copy by hand land here.")
                    .foregroundStyle(.secondary)
            }
            Button("Show in Finder") { model.showInFinder(folder.folder) }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

/// "What's New": the assistant's summary of the changelog since the installed version.
struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Label("What's New", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Palette.accentText)
                Spacer()
                if model.summarizing.contains(addon.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.summaries[addon.id] == nil ? "Summarize Changes" : "Summarize Again") {
                        Task { await model.summarize(addon.id) }
                    }
                    .controlSize(.small)
                    .help(help)
                }
            }
            if let summary = model.summaries[addon.id] {
                Text(summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Written by \(source). Check the changelog before relying on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = model.summaryErrors[addon.id] {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if !model.summarizing.contains(addon.id) {
                Text(help).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08), in: .rect(cornerRadius: Radius.tile))
        .overlay { RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Palette.accent.opacity(0.3)) }
    }

    private var source: String {
        switch model.prefs.aiProvider {
        case .claude: model.prefs.claudeModel.title
        case .ollama: "\(model.prefs.ollamaModel) on Ollama"
        case .off: "the assistant"
        }
    }

    private var help: String {
        if let installed = model.installed(addon.id)?.installedVersion, !VersionText.same(installed, addon.version) {
            return "Summarize what changed from \(installed) to \(addon.version)."
        }
        return "Summarize the latest changes in a few bullets."
    }
}

/// The digest of every pending update, from the Updates page.
struct DigestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Label("What the Updates Bring", systemImage: "sparkles")
                .font(.title2.bold())
            Group {
                if model.isDigesting {
                    VStack(spacing: Space.md) {
                        ProgressView()
                        Text("Reading \(model.updates.count) changelogs…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else if let error = model.digestError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else if let digest = model.digest {
                    ScrollView {
                        Text(digest).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160, maxHeight: 420)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Update All") {
                    dismiss()
                    Task { await model.updateAll() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.updates.isEmpty || model.batch != nil)
            }
        }
        .padding(Space.xxl)
        .frame(width: 520)
        .noInitialFocus()
    }
}
