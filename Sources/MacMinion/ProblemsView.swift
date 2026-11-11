import AppKit
import MacMinionKit
import SwiftUI

extension AppModel {
    /// The installed addon in this folder.
    func installedAddon(folder: String) -> InstalledAddon? {
        installed.first { $0.record.dirs.contains { $0.caseInsensitiveCompare(folder) == .orderedSame } }
    }

    /// The ESOUI entries that install these library folders.
    func libraries(for folders: [String]) -> [MissingLibrary] {
        folders.compactMap { folder in
            if let known = allMissingLibraries.first(where: { $0.folder.caseInsensitiveCompare(folder) == .orderedSame }) { return known }
            guard let addon = catalog.first(where: { $0.dirs.contains { $0.caseInsensitiveCompare(folder) == .orderedSame } }) else { return nil }
            return MissingLibrary(folder: folder, addon: addon, wantedBy: [], required: true)
        }
    }

    /// The links of the addon selected on Installed or Updates, for the Addons menu.
    var selectedAddonLinks: (name: String, dirs: [String], links: AddonLinks)? {
        guard sidebar == .installed || sidebar == .updates else { return nil }
        let entry: (String, [String])? = switch selection {
        case .addon(let id)?: installed(id).map { ($0.catalog.name, $0.record.dirs) }
        case .folder(let folder)? where folder != CompanionData.folderName:
            (unmatched.first { $0.folder == folder }?.title ?? folder, [folder])
        default: nil
        }
        guard let (name, dirs) = entry else { return nil }
        return (name, dirs, gameFolder.addonLinkIndex().links(for: dirs))
    }
}

/// What's wrong in the game folder, one card per cause, worst first (S-052). Double-click a card to open its
/// first problem; Details lists the raw checks.
struct ProblemsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let filter = model.gameFolder.problemsAddonFilter
        let all = model.gameFolder.healthFindings
        let findings = filter.map { all.filter($0.matches) } ?? all
        let main = findings.filter(\.isMain), more = findings.filter { !$0.isMain }
        List(selection: Bindable(model.gameFolder).problemsSelection) {
            ForEach(HealthFinding.Tier.allCases, id: \.self) { tier in
                let items = main.filter { $0.tier == tier }
                if !items.isEmpty {
                    Section(tier.title) {
                        ForEach(items) { finding in
                            FindingRow(finding: finding, prominent: model.gameFolder.problemsSelection == finding.id).readableRow().tag(finding.id)
                        }
                    }
                }
            }
            if !more.isEmpty {
                Section {
                    if model.gameFolder.problemsMoreExpanded {
                        ForEach(more) { finding in
                            FindingRow(finding: finding, prominent: false).readableRow().tag(finding.id)
                        }
                    }
                } header: {
                    DisclosureButton(title: String(localized: "Nothing to do here (\(more.count))"),
                                     expanded: model.gameFolder.problemsMoreExpanded) { model.gameFolder.problemsMoreExpanded.toggle() }
                }
            }
        }
        .contextMenu(forSelectionType: HealthFinding.ID.self) { ids in
            if let finding = findings.first(where: { $0.id == ids.first }) {
                if let action = finding.action, !model.gameFolder.isDisabled(action) {
                    Button(model.gameFolder.title(for: action), role: action.isCleanUp ? .destructive : nil) { model.gameFolder.run(action, in: finding) }
                    Divider()
                }
                Button(model.gameFolder.problemsExpanded.contains(finding.id) ? "Hide Details" : "Show Details") { model.gameFolder.toggleDetails(finding.id) }
                if let first = finding.problems.first {
                    if let url = first.url {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } else {
                        Button("Show in Inspector") { Task { await model.gameFolder.revealProblem(first) } }
                    }
                }
            }
        } primaryAction: { ids in
            guard let first = findings.first(where: { $0.id == ids.first })?.problems.first else { return }
            Task { await model.gameFolder.openProblem(first) }
        }
        .overlay {
            if model.gameFolder.svProblems == nil, model.gameFolder.fileProblems.isEmpty {
                InspectorLoadingView(model: model)
            } else if findings.isEmpty, let filter {
                ContentUnavailableView {
                    Label(String(localized: "No Problems with \(filter.name)"), systemImage: "checkmark.seal")
                } description: {
                    Text("Nothing in the game folder points at this addon.")
                } actions: {
                    Button("Show All") { model.gameFolder.problemsAddonFilter = nil }
                }
            } else if findings.isEmpty {
                ContentUnavailableView("No Problems", systemImage: "checkmark.seal",
                                       description: Text("Every SavedVariables file is in use, reads cleanly, and matches what its addon declares."))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !findings.isEmpty {
                HStack(spacing: Space.md) {
                    Text(model.gameFolder.healthSummary(findings))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .gridProbe("problems-summary-text", area: "problems-summary")
                    Spacer(minLength: Space.md)
                    // Clean Up All reaches every file, so it waits until the list shows every finding.
                    let tidy = model.gameFolder.fileProblems
                    if !tidy.isEmpty, filter == nil {
                        Button("Clean Up All…") { model.gameFolder.askToCleanUp(tidy) }
                            .disabled(model.gameIsRunning || model.backupBusy != nil)
                            .help(model.gameIsRunning ? "Quit Elder Scrolls Online first"
                                  : String(localized: "Back up, then move every file here to the Trash (\(tidy.reduce(0) { $0 + $1.bytes }.formatted(.byteCount(style: .file))))"))
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.sm)
                .background(.bar)
                .gridArea("problems-summary")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let filter {
                AddonFilterBar(title: String(localized: "Problems with \(filter.name)"), clear: String(localized: "Show All"),
                               area: "problems-filter") { model.gameFolder.problemsAddonFilter = nil }
            }
        }
    }
}

/// "Problems with Dustman" or "Files for Dustman" above a list narrowed to one addon, with a way back.
struct AddonFilterBar: View {
    let title: String
    let clear: String
    let area: String
    /// Off while another Escape button shows, like the Inspector's Done.
    var escape = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Label(title, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .gridProbe("\(area)-text", area: area)
                Spacer(minLength: Space.md)
                Button(clear, action: action)
                    .keyboardShortcut(escape ? .cancelAction : nil)
                    .help(escape ? String(localized: "\(clear) (Escape)") : clear)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.sm)
            .background(.bar)
            .gridArea(area)
            Divider()
        }
    }
}

/// A chevron and a title that show or hide what follows: Details on a card, and Nothing to Do Here.
private struct DisclosureButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: expanded ? "chevron.down" : "chevron.right")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
    }
}

private extension HealthFinding.Action {
    var isCleanUp: Bool { if case .cleanUp = self { true } else { false } }
}

/// One finding: its cause, what it means in game, what it touches, and one button. Details shows the raw checks.
private struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: HealthFinding
    /// The selected card's button is the prominent one, so the list has one at a time.
    let prominent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Label {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(finding.title).font(.body.weight(.semibold))
                    Text(finding.impact).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let summary = finding.summary { Text(summary).font(.callout) }
                    if let line = names(finding.affected.filter { if case .character = $0 { false } else { true } }) {
                        Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let line = names(finding.affected.filter { if case .character = $0 { true } else { false } }) {
                        Text(String(localized: "On \(line)")).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if finding.certainty != .certain {
                        Text(certainty).font(.caption).foregroundStyle(.secondary)
                    }
                    if !finding.problems.isEmpty {
                        let expanded = model.gameFolder.problemsExpanded.contains(finding.id)
                        DisclosureButton(title: String(localized: "Details (\(finding.problems.count))"), expanded: expanded) {
                            model.gameFolder.toggleDetails(finding.id)
                        }
                        if expanded {
                            ForEach(finding.problems) { problem in
                                ProblemRow(problem: problem) { EmptyView() }
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { Task { await model.gameFolder.openProblem(problem) } }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { Task { await model.gameFolder.openProblem(problem) } }
                            }
                        }
                    }
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Spacer(minLength: Space.md)
            if let action = finding.action {
                Group {
                    if prominent {
                        Button(model.gameFolder.title(for: action)) { model.gameFolder.run(action, in: finding) }.buttonStyle(.borderedProminent)
                    } else {
                        Button(model.gameFolder.title(for: action)) { model.gameFolder.run(action, in: finding) }.buttonStyle(.bordered)
                    }
                }
                .disabled(model.gameFolder.isDisabled(action))
                .help(model.gameFolder.help(for: action))
            }
        }
        .padding(.vertical, Space.xs)
    }

    /// "WritWorthy, HarvestMap, LibDebugLogger, and 4 more"; nil when there are none.
    private func names(_ subjects: [HealthFinding.Subject]) -> String? {
        guard !subjects.isEmpty else { return nil }
        let shown = subjects.prefix(3).map(\.name)
        let rest = subjects.count - shown.count
        return rest > 0 ? String(localized: "\(shown.formatted(.list(type: .and, width: .narrow))) and \(rest) more")
            : shown.formatted(.list(type: .and))
    }

    private var certainty: String {
        if let note = finding.certaintyNote { return note }
        return finding.certainty == .likely ? String(localized: "Likely, from what the files show.")
            : String(localized: "Possibly; check before acting.")
    }

    private var symbol: String {
        switch finding.tier {
        case .broken: "xmark.octagon.fill"
        case .dataAtRisk: "exclamationmark.triangle.fill"
        case .outOfDate: "clock.arrow.circlepath"
        case .clutter: "trash"
        case .size: "chart.bar"
        case .info: "info.circle"
        }
    }

    private var color: AnyShapeStyle {
        switch finding.tier {
        case .broken: AnyShapeStyle(Palette.negative)
        case .dataAtRisk: AnyShapeStyle(Palette.caution)
        default: AnyShapeStyle(.secondary)
        }
    }
}

private struct ProblemRow<Action: View>: View {
    let problem: SVProblem
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                HStack(spacing: Space.sm) {
                    Text(problem.kind.title).font(.body.weight(.semibold))
                    Text(where_).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Text(problem.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.md)
            action()
        }
        .padding(.vertical, Space.xs)
    }

    private var where_: String {
        ([problem.file] + problem.path.map(\.description)).joined(separator: " › ")
    }

    private var symbol: String {
        switch problem.severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note: "info.circle"
        }
    }

    private var color: AnyShapeStyle {
        switch problem.severity {
        case .error: AnyShapeStyle(Palette.negative)
        case .warning: AnyShapeStyle(Palette.caution)
        case .note: AnyShapeStyle(.secondary)
        }
    }
}

// MARK: - Links from other tabs (S-058)

// MARK: - Links from Installed (S-059)

/// One addon, by the folders it installs: what the Inspector's file list and Problems narrow to.
struct AddonFilter: Equatable {
    let name: String
    /// Lowercased folder names.
    let folders: Set<String>

    init(name: String, dirs: [String]) {
        self.name = name
        folders = Set(dirs.map { $0.lowercased() })
    }

    func matches(_ finding: HealthFinding) -> Bool { !finding.addonFolders.isDisjoint(with: folders) }
}

/// What an installed addon's icons open: its SavedVariables files and the findings about it.
struct AddonLinks {
    var files: [String] = []
    var findings: [HealthFinding] = []
}

/// Every installed addon's links, built once per list: findings are too slow to build per row.
struct AddonLinkIndex {
    let main: [HealthFinding]
    let files: [String: [String]]

    static let empty = AddonLinkIndex(main: [], files: [:])

    func links(for dirs: [String]) -> AddonLinks {
        let filter = AddonFilter(name: "", dirs: dirs)
        return AddonLinks(files: filter.folders.sorted().flatMap { files[$0] ?? [] }.sorted(),
                          findings: main.filter(filter.matches))
    }
}

/// The two icons on an installed addon: its files in the Inspector, and its problems with a count.
/// Each shows only when there is something behind it.
struct AddonLinkButtons: View {
    let model: AppModel
    let name: String
    let dirs: [String]
    let links: AddonLinks
    /// Small cards have no room for the count; it stays in the help.
    var showsCount = true

    var body: some View {
        HStack(spacing: Space.sm) {
            if !links.files.isEmpty {
                Button("Show Files in Inspector", systemImage: "magnifyingglass") { model.gameFolder.showFiles(of: name, dirs: dirs) }
                    .labelStyle(.iconOnly)
                    .help(String(localized: "Show the SavedVariables files of \(name) in the Inspector (Shift-Command-I)"))
            }
            if !links.findings.isEmpty {
                Button { model.gameFolder.showProblems(of: name, dirs: dirs) } label: {
                    // The system's warning yellow on the triangle. The count is `Color.secondary`, not the `.secondary`
                    // style: inside a borderless button that style is a pale shade of the accent.
                    HStack(spacing: Space.xs) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow) // hig: ok the system warning sign
                        if showsCount {
                            Text("\(links.findings.count)").font(.caption.monospacedDigit()).foregroundStyle(Color.secondary)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "\(links.findings.count) problems"))
                .help((links.findings.map(\.title) + [String(localized: "Show them in Problems (Shift-Command-P)")]).joined(separator: "\n"))
            }
        }
        .buttonStyle(.borderless)
    }
}

/// "2 problems" beside an addon: opens Problems at the first. Never restates the problem itself.
struct ProblemLink: View {
    let model: AppModel
    let findings: [HealthFinding]

    var body: some View {
        if let first = findings.first {
            Button { model.gameFolder.showFinding(first.id) } label: {
                Label(String(localized: "\(findings.count) problems"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.accentText)
            }
            .buttonStyle(.plain)
            .help(findings.map(\.title).joined(separator: "\n"))
        }
    }
}
