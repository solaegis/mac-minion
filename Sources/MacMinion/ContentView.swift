import MacMinionKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        Group {
            if isWide {
                // The overview and the grids fill the window; details open in an inspector.
                NavigationSplitView {
                    sidebar
                } detail: {
                    widePage
                        .inspector(isPresented: inspectorShown) {
                            DetailColumn().inspectorColumnWidth(min: 280, ideal: 320, max: 520)
                        }
                }
            } else {
                browser
            }
        }
        .navigationSubtitle(model.sidebar == .gameFolder ? model.gameFolderStatusLine : model.statusLine)
        .toolbar {
            // Game Folder declares Help with its own page actions.
            if model.sidebar != .gameFolder {
                ToolbarItem { PageHelpButton() }
            }
        }
        .onChange(of: model.sidebar) { model.selection = model.pendingSelection; model.pendingSelection = nil }
        // Choosing an addon or folder shows its details, even after Hide Inspector.
        .onChange(of: model.selection) { _, new in if new != nil { model.inspectorHidden = false } }
        .alert(removalTitle, isPresented: removalShown, presenting: model.pendingRemoval) { addon in
            Button("Move to Trash", role: .destructive) { Task { await model.remove(addon) } }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("These folders go to the Trash: \(addon.record.dirs.joined(separator: ", ")). Saved settings stay.")
        }
        .alert("Move “\(model.pendingFolderRemoval?.title ?? "")” to the Trash?",
               isPresented: Binding(get: { model.pendingFolderRemoval != nil }, set: { if !$0 { model.pendingFolderRemoval = nil } }),
               presenting: model.pendingFolderRemoval) { folder in
            Button("Move to Trash", role: .destructive) { Task { await model.removeFolder(folder) } }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("The folder \(folder.folder) goes to the Trash. It isn't on ESOUI, so MacMinion can't reinstall it. Saved settings stay.")
        }
        .task {
            await Launch.run(model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var isWide: Bool {
        switch model.sidebar ?? .overview {
        case .overview, .backups, .gameFolder: true
        case .installed: model.prefs.installedLayout == .grid
        case .findMore: model.prefs.findMoreLayout == .grid
        case .updates: false
        }
    }

    @ViewBuilder
    private var widePage: some View {
        switch model.sidebar ?? .overview {
        case .installed, .findMore: BrowsePage(scope: browseScope)
        case .updates: UpdatesList()
        case .overview: OverviewView()
        case .backups: BackupsPage()
        case .gameFolder: GameFolderPage()
        }
    }

    private var browseScope: FilterScope { model.sidebar == .findMore ? .findMore : .installed }

    private var inspectorShown: Binding<Bool> {
        // SwiftUI writes false here whenever the inspector closes, including when it closes on its own
        // because nothing is selected or the page has none; only a close the person made hides it.
        Binding(get: { model.inspectorAvailable && !model.inspectorHidden },
                set: { if model.inspectorAvailable { model.inspectorHidden = !$0 } })
    }

    private var browser: some View {
        NavigationSplitView {
            sidebar
        } content: {
            Group {
                switch model.sidebar ?? .installed {
                case .installed, .findMore, .overview: BrowsePage(scope: browseScope)
                case .updates: UpdatesList()
                case .backups: BackupsPage()
                case .gameFolder: GameFolderPage()
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
            let row = Label {
                HStack(spacing: Space.xs) {
                    Text(page.title)
                    if page.isExperimental {
                        Image(systemName: "flask")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Experimental, work in progress")
                    }
                }
            } icon: {
                Image(systemName: page.symbol)
            }
            .badge(badge(for: page))
            .tag(page)
            if page.isExperimental {
                row.help("Game Folder is still a work in progress")
            } else {
                row
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }

    private func badge(for page: SidebarItem) -> Int {
        switch page {
        case .installed: model.addonCount
        case .updates: model.updates.count
        case .findMore, .overview, .backups, .gameFolder: 0
        }
    }
}

// MARK: - Pages

/// Installed and Find More, each a bento grid or a list per Settings > Layout.
/// One view for both pages, so switching between them keeps the toolbar's one
/// search field and only changes its text. Two `.searchable` pages swapping in
/// place put a second search field in the toolbar for a moment, and NSToolbar
/// throws on the duplicate (com.apple.SwiftUI.search) and the app quits.
struct BrowsePage: View {
    @Environment(AppModel.self) private var model
    let scope: FilterScope

    var body: some View {
        @Bindable var model = model
        @Bindable var prefs = model.prefs
        let installed = scope == .installed
        Group {
            switch (scope, installed ? prefs.installedLayout : prefs.findMoreLayout) {
            case (.installed, .grid): InstalledGrid()
            case (.installed, .list): InstalledList()
            case (.findMore, .grid): FindMoreGrid()
            case (.findMore, .list): FindMoreList()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FilterChips(scope: scope) }
        .searchable(text: installed ? $model.installedSearch : $model.search, placement: .toolbar,
                    prompt: installed ? String(localized: "Filter installed addons") : String(localized: "Search addons or authors"))
        .navigationTitle(installed ? "Installed" : "Find More")
        .toolbar {
            if installed { RefreshButton() }
            FilterMenu(scope: scope)
            LayoutSwitch(layout: installed ? $prefs.installedLayout : $prefs.findMoreLayout)
        }
    }
}

/// Grid or list, in the toolbar.
struct LayoutSwitch: ToolbarContent {
    @Binding var layout: BrowseLayout

    var body: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $layout) {
                ForEach(BrowseLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Show as a grid or a list (Option-Command-1, Option-Command-2)")
        }
    }
}

// MARK: - Lists

struct InstalledList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let links = model.gameFolder.addonLinkIndex()
        List(selection: $model.selection) {
            if model.showCompanion {
                Section("MacMinion Companion") {
                    CompanionRow()
                        .tag(Selection.folder(CompanionData.folderName))
                }
            }
            Section("From ESOUI") {
                ForEach(model.filteredInstalled) { addon in
                    AddonRow(addon: addon.catalog, installed: addon, links: links.links(for: addon.record.dirs))
                        .tag(Selection.addon(addon.id))
                        .contextMenu { InstalledMenu(addon: addon) }
                }
            }
            if !model.filteredUnmatched.isEmpty {
                Section("Not on ESOUI") {
                    ForEach(model.filteredUnmatched) { folder in
                        FolderRow(folder: folder, links: links.links(for: [folder.folder]))
                            .tag(Selection.folder(folder.folder))
                            .contextMenu {
                                let folderLinks = links.links(for: [folder.folder])
                                if !folderLinks.files.isEmpty {
                                    Button("Show Files in Inspector") { model.gameFolder.showFiles(of: folder.title, dirs: [folder.folder]) }
                                }
                                if !folderLinks.findings.isEmpty {
                                    Button("Show Problems") { model.gameFolder.showProblems(of: folder.title, dirs: [folder.folder]) }
                                }
                                Button("Show in Finder") { model.showInFinder(folder.folder) }
                            }
                    }
                }
            }
        }
        .overlay {
            if model.installedFiltered && model.filteredInstalled.isEmpty && model.filteredUnmatched.isEmpty {
                NoMatches(scope: .installed)
            } else if model.installed.isEmpty && model.unmatched.isEmpty && !model.companionInstalled {
                ContentUnavailableView {
                    Label("No Addons Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text(model.catalog.isEmpty ? String(localized: "The ESOUI catalog hasn't loaded yet.") : String(localized: "Nothing is installed in \(model.addonsFolder.path)."))
                } actions: {
                    SettingsLink { Text("Choose Folder…") }
                }
            }
        }
        .task { await model.gameFolder.readGameFolderForLinks() }
    }
}

struct UpdatesList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let links = model.gameFolder.addonLinkIndex()
        List(model.updates, selection: $model.selection) { addon in
            AddonRow(addon: addon.catalog, installed: addon, links: links.links(for: addon.record.dirs))
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
        .task { await model.gameFolder.readGameFolderForLinks() }
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
                .contextMenu { FindMoreMenu(addon: addon) }
        }
        .overlay {
            if results.isEmpty {
                if model.findMoreFilter.isActive {
                    NoMatches(scope: .findMore)
                } else if !model.catalogResults(includeInstalled: true).isEmpty {
                    ContentUnavailableView("Already Installed", systemImage: "checkmark.circle",
                                           description: Text(model.search.isEmpty ? String(localized: "You have every addon here. See Installed.")
                                                             : String(localized: "Everything matching “\(model.search)” is installed. See Installed.")))
                } else if model.search.isEmpty {
                    ContentUnavailableView("No Addons", systemImage: "magnifyingglass")
                } else {
                    ContentUnavailableView.search(text: model.search)
                }
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
        if !model.busy.contains(addon.id) {
            Button(addon.status == .updateAvailable ? String(localized: "Update") : String(localized: "Reinstall")) { Task { await model.install(addon.id) } }
        }
        Toggle("Ignore Updates", isOn: Binding(get: { addon.record.ignored }, set: { model.setIgnored(addon.id, $0) }))
        RatingMenuItems(id: addon.id)
        Divider()
        let links = model.gameFolder.addonLinkIndex().links(for: addon.record.dirs)
        if !links.files.isEmpty {
            Button("Show Files in Inspector") { model.gameFolder.showFiles(of: addon.catalog.name, dirs: addon.record.dirs) }
        }
        if !links.findings.isEmpty {
            Button("Show Problems") { model.gameFolder.showProblems(of: addon.catalog.name, dirs: addon.record.dirs) }
        }
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
    /// Its files and problems, on Installed and Updates (S-059).
    var links: AddonLinks?

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(addon.name).lineLimit(1)
                HStack(spacing: 0) {
                    AuthorLink(author: addon.author)
                    Text(verbatim: " · " + subtitle)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = model.errors[addon.id] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Palette.negative)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.sm)
            if let links, let installed {
                AddonLinkButtons(model: model, name: addon.name, dirs: installed.record.dirs, links: links)
            }
            trailing
        }
        .padding(.vertical, Space.xs / 2)
    }

    /// What follows the creator's name: version, then any Lua errors.
    private var subtitle: String {
        var parts: [String] = []
        if let installed, let v = installed.installedVersion, !VersionText.same(v, addon.version) {
            parts.append("\(v) → \(addon.version)")
        } else {
            parts.append(addon.version)
        }
        if let installed {
            let errors = model.companionErrorCount(for: installed)
            if errors > 0 { parts.append(String(localized: "\(errors) Lua errors")) }
            else if let state = model.companionState(for: installed), state.failedToLoad {
                parts.append(String(localized: "didn't load"))
            }
        }
        return parts.joined(separator: " · ")
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
                    .foregroundStyle(Palette.positive)
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
    @Environment(AppModel.self) private var model
    let folder: UnmatchedFolder
    var links: AddonLinks?

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(folder.title).lineLimit(1)
                Text([folder.manifest?.author, folder.manifest?.version, folder.folder].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            if let links {
                AddonLinkButtons(model: model, name: folder.title, dirs: [folder.folder], links: links)
            }
        }
        .padding(.vertical, Space.xs / 2)
    }
}

struct CompanionRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs / 2) {
            Text(CompanionData.displayName).lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, Space.xs / 2)
    }

    private var subtitle: String {
        var parts = ["solaegis"]
        if let version = model.companionManifest?.version { parts.append(version) }
        if let written = model.companionSnapshot?.written {
            parts.append(String(localized: "as of \(written.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "log in once to write a snapshot"))
        }
        return parts.joined(separator: " · ")
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
            if CompanionData.isCompanionFolder(name), model.companionInstalled {
                CompanionDetail()
            } else if let folder = model.unmatched.first(where: { $0.folder == name }) {
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
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.negative)
                }
                if let info {
                    text(String(localized: "Description"), BBCode.plainText(info.description))
                    text(String(localized: "Changes"), BBCode.plainText(info.changelog))
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
            do { info = try await model.loadDetails(addon.id) } catch { loadError = String(localized: "Details aren't available offline.") }
            if model.prefs.summarizeOnOpen, model.prefs.aiConfig.problem == nil, installed?.status == .updateAvailable,
               model.summaries[addon.id] == nil, info != nil {
                await model.summarize(addon.id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.lg) {
                Thumbnail(url: addon.thumbnails.first, size: 96)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(addon.name).font(.title2.bold()).textSelection(.enabled)
                    AuthorLink(author: addon.author, prefixed: true).foregroundStyle(.secondary)
                    RatingButtons(id: addon.id).padding(.top, Space.xs)
                }
                .gridProbe("title", area: "detail")
            }
            // Their own row, so a narrow inspector never squeezes the buttons into "…".
            HStack(spacing: Space.sm) {
                primaryButton.fixedSize()
                VersionMenu(addon: addon)
                if let url = addon.infoURL {
                    Link(destination: url) { Text("Open on ESOUI") }
                        .buttonStyle(.bordered)
                        .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.busy.contains(addon.id) {
            ProgressView().controlSize(.small)
        } else {
            let title = switch installed?.status {
            case nil: String(localized: "Install")
            case .updateAvailable: String(localized: "Update")
            default: String(localized: "Reinstall")
            }
            Button(title) { Task { await model.install(addon.id) } }
                .buttonStyle(.borderedProminent)
                .disabled(model.offline && model.details[addon.id] == nil)
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
            row(String(localized: "Latest version"), addon.version)
            if let installed {
                row("Installed", installed.installedVersion ?? String(localized: "Unknown"))
                row("Status", installed.status.label)
            }
            row("Updated", addon.date.formatted(date: .abbreviated, time: .omitted))
            row(String(localized: "Downloads"), String(localized: "\(addon.downloads.formatted()) (\(addon.downloadsMonthly.formatted()) this month)"))
            row(String(localized: "Favorites"), addon.favorites.formatted())
            if let category = model.categories.first(where: { $0.id == addon.categoryID }) {
                row("Category", category.title)
            }
            if !addon.compatibility.isEmpty {
                row(String(localized: "Works with"), addon.compatibility.map { "\($0.name) (\($0.version))" }.joined(separator: ", "))
            }
            row(String(localized: "Folders"), (installed?.record.dirs ?? addon.dirs).joined(separator: ", "))
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

struct CompanionDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Title", value: CompanionData.displayName)
                LabeledContent("Folder", value: CompanionData.folderName)
                LabeledContent("Author", value: model.companionManifest?.author ?? "solaegis")
                if let version = model.companionManifest?.version { LabeledContent("Version", value: version) }
                if let written = model.companionSnapshot?.written {
                    LabeledContent("Last snapshot", value: written.formatted(date: .abbreviated, time: .shortened))
                }
                if let env = model.companionSnapshot?.env {
                    if let game = env.gameVersion { LabeledContent("Game version", value: game) }
                    if let server = env.server { LabeledContent("Server", value: server) }
                }
                if let snap = model.companionSnapshot {
                    LabeledContent("Characters", value: snap.characters.count.formatted())
                    LabeledContent("Addons recorded", value: snap.addons.count.formatted())
                    if !snap.errors.isEmpty {
                        LabeledContent("Lua errors", value: snap.errors.reduce(0) { $0 + $1.count }.formatted())
                    }
                }
            } footer: {
                Text("MacMinion's in-game companion. After you log in, it writes the roster, which addons loaded, and Lua errors.")
                    .foregroundStyle(.secondary)
            }
            Button("Show in Finder") { model.showInFinder(CompanionData.folderName) }
        }
        .formStyle(.grouped)
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
                if folder.manifest?.isLibrary == true { LabeledContent("Kind", value: String(localized: "Library")) }
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
                    Button(model.summaries[addon.id] == nil ? String(localized: "Summarize Changes") : String(localized: "Summarize Again")) {
                        Task { await model.summarize(addon.id) }
                    }
                    .controlSize(.small)
                    .help(help)
                }
            }
            if let summary = model.summaries[addon.id] {
                Text(summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(model.summarizing.contains(addon.id) ? "\(model.aiSource) is writing…"
                     : String(localized: "Written by \(model.aiSource). Check the changelog before relying on it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = model.summaryErrors[addon.id] {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.negative)
            } else if model.summarizing.contains(addon.id) {
                Text("Waiting for \(model.aiSource)… A local model may take a minute to load.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(help).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentSurface()
    }

    private var help: String {
        if let installed = model.installed(addon.id)?.installedVersion, !VersionText.same(installed, addon.version) {
            return String(localized: "Summarize what changed from \(installed) to \(addon.version).")
        }
        return String(localized: "Summarize the latest changes in a few bullets.")
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
                if model.isDigesting && (model.digest ?? "").isEmpty {
                    VStack(spacing: Space.md) {
                        ProgressView()
                        Text("Reading \(model.updates.count) changelogs…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else if let error = model.digestError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.negative)
                } else if let digest = model.digest {
                    ScrollView {
                        Text(digest).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fitsContent(max: 420)
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

/// Help for the current page, as a plain symbol button like its toolbar neighbors. A bezeled `HelpLink` read as
/// the page's key action.
struct PageHelpButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Help for This Page", systemImage: "questionmark.circle") { Docs.open(Docs.page(for: model.sidebar)) }
            .help("Open the documentation for this page")
    }
}
