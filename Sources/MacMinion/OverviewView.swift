import Charts
import MacMinionKit
import SwiftUI

/// The home page: how the addons stand today and how MacMinion (and Minion before it) has kept them current.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var customizing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                // The order and visibility come from Settings > Layout (or Customize in the toolbar).
                ForEach(model.prefs.visibleOverview) { section in
                    content(section)
                        .contextMenu { menu(section) }
                }
                if model.prefs.visibleOverview.isEmpty {
                    ContentUnavailableView {
                        Label("Every Section Is Hidden", systemImage: "eye.slash")
                    } actions: {
                        Button("Customize Overview…") { customizing = true }
                    }
                }
            }
            .padding(Space.section)
            .frame(maxWidth: 1240)
            .gridArea("overview", inset: Space.section)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .toolbar {
            RefreshButton()
            ToolbarItem {
                Button("Customize Overview", systemImage: "slider.horizontal.3") { customizing = true }
                    .help("Choose which sections the Overview shows, and their order")
            }
        }
        .sheet(isPresented: $customizing) { OverviewCustomizeSheet() }
    }

    @ViewBuilder
    private func content(_ section: OverviewSection) -> some View {
        switch section {
        case .banner: OverviewHero()
        case .libraries: if !model.missingLibraries.isEmpty { LibrariesCard() }
        case .stats: StatTiles()
        case .recommended: if model.prefs.aiEnabled { SuggestionsCard() }
        case .search:
            if model.prefs.aiEnabled {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    AISearchBar()
                    SearchResultsCard()
                }
            }
        case .history:
            // Side by side, each card as tall as its neighbour.
            Grid(horizontalSpacing: Space.lg) {
                GridRow {
                    ActivityChartCard()
                    CategoryCard()
                }
            }
        case .activity:
            Grid(horizontalSpacing: Space.lg) {
                GridRow {
                    RecentActivityCard()
                    MostUpdatedCard()
                }
            }
        case .popular: PopularCard()
        }
    }

    @ViewBuilder
    private func menu(_ section: OverviewSection) -> some View {
        let prefs = model.prefs
        let visible = prefs.visibleOverview
        Button("Move Up", systemImage: "arrow.up") { prefs.moveOverview(section, by: -1) }
            .disabled(visible.first == section)
        Button("Move Down", systemImage: "arrow.down") { prefs.moveOverview(section, by: 1) }
            .disabled(visible.last == section)
        Button("Hide \(section.title)", systemImage: "eye.slash") { prefs.setOverview(section, visible: false) }
        Divider()
        Button("Customize Overview…") { customizing = true }
    }
}

/// The sections, in order, each with a show toggle and up/down buttons. Used in the Customize sheet
/// and in Settings > Layout.
struct OverviewSectionRows: View {
    @Environment(AppModel.self) private var model
    /// Drag to reorder, inside a List.
    var draggable = false

    var body: some View {
        let prefs = model.prefs
        ForEach(Array(prefs.overviewOrder.enumerated()), id: \.element) { index, section in
            HStack(spacing: Space.md) {
                Toggle(isOn: Binding(get: { !prefs.overviewHidden.contains(section) },
                                     set: { prefs.setOverview(section, visible: $0) })) {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title)
                            if let note = section.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: section.symbol).foregroundStyle(Palette.accentText)
                    }
                }
                .toggleStyle(.checkbox)
                Spacer()
                Button("Move Up", systemImage: "chevron.up") { prefs.moveOverview(section, by: -1) }
                    .labelStyle(.iconOnly)
                    .help("Move \(section.title) up")
                    .disabled(index == 0)
                Button("Move Down", systemImage: "chevron.down") { prefs.moveOverview(section, by: 1) }
                    .labelStyle(.iconOnly)
                    .help("Move \(section.title) down")
                    .disabled(index == prefs.overviewOrder.count - 1)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
        }
        .onMove(perform: draggable ? { prefs.moveOverview(from: $0, to: $1) } : nil)
    }
}

private struct OverviewCustomizeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Customize Overview").font(.title2.bold())
            Text("Show or hide each section, and drag or use the arrows to change the order.")
                .foregroundStyle(.secondary)
            List {
                OverviewSectionRows(draggable: true)
            }
            .frame(minHeight: 340)
            HStack {
                Button("Reset to Default") { model.prefs.resetOverview() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 520)
        .noInitialFocus()
    }
}

// MARK: - Hero

private struct OverviewHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let updates = model.updates.count
        HStack(alignment: .center, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Elder Scrolls Online")
                    .font(.callout.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.8)
                Text(headline(updates))
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .gridProbe("hero-title", area: "overview")
                Text(detail)
                    .font(.body)
                    .opacity(0.85)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.lg)
            VStack(alignment: .trailing, spacing: Space.sm) {
                if model.batch != nil {
                    ProgressView().controlSize(.large).tint(Palette.onAccent)
                } else if updates > 0 {
                    Button { Task { await model.updateAll() } } label: {
                        Label("Update All", systemImage: "arrow.down.circle.fill")
                            .padding(.horizontal, Space.xs)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Palette.onAccent)
                    .help("Update every addon that has an update (Command-U)")
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityLabel("Up to date")
                }
            }
        }
        .foregroundStyle(Palette.onAccent)
        .padding(Space.section)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .background(alignment: .trailing) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 220))
                .foregroundStyle(Palette.onAccent.opacity(0.08))
                .rotationEffect(.degrees(-12))
                .accessibilityHidden(true)
        }
        .background(Palette.accent.gradient)
        .clipShape(.rect(cornerRadius: Radius.hero))
    }

    private func headline(_ updates: Int) -> String {
        if model.installed.isEmpty { return "No addons yet" }
        if updates == 0 { return "Everything's up to date" }
        return "\(updates) update\(updates == 1 ? "" : "s") ready"
    }

    private var detail: String {
        var parts = ["\(model.installed.count + model.unmatched.count) addons in \(model.addonsFolder.deletingLastPathComponent().lastPathComponent)/\(model.addonsFolder.lastPathComponent)"]
        if let date = model.catalogDate {
            parts.append("checked \(date.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tiles

private struct StatTiles: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let libraries = model.installed.filter { $0.catalog.categoryID == AddonCategory.librariesID }.count
        let ignored = model.installed.filter { $0.record.ignored }.count
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: Space.md)], spacing: Space.md) {
            StatTile(value: model.installed.count.formatted(), label: "From ESOUI", symbol: "puzzlepiece.extension") {
                model.open(.installed)
            }
            StatTile(value: model.updates.count.formatted(), label: "Updates Ready", symbol: "arrow.down.circle",
                     highlighted: !model.updates.isEmpty) {
                model.open(.updates)
            }
            StatTile(value: libraries.formatted(), label: "Libraries", symbol: "books.vertical") {
                model.open(.installed)
            }
            StatTile(value: model.unmatched.count.formatted(), label: "Not on ESOUI", symbol: "folder") {
                model.open(.installed)
            }
            StatTile(value: ignored.formatted(), label: "Ignored", symbol: "bell.slash") {
                model.open(.installed)
            }
            StatTile(value: model.addonsSize.map { $0.formatted(.byteCount(style: .file)) } ?? "–",
                     label: "On Disk", symbol: "internaldrive") {
                model.showInFinder()
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var highlighted = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(highlighted ? Palette.onAccent : Palette.accentText)
                    .frame(width: 32, height: 32)
                    .background(highlighted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.accentWash),
                                in: .circle)
                Text(value)
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(Radius.tile, selected: highlighted)
            .scaleEffect(Motion.hoverScale(hovering, reduceMotion: reduceMotion))
            .animation(Motion.hover, value: hovering)
            .contentShape(.rect(cornerRadius: Radius.tile))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

private struct OverviewCard<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .labelStyle(CardLabelStyle())
                Spacer()
                accessory
            }
            content
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

extension OverviewCard where Accessory == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

private struct CardLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.sm) {
            configuration.icon.foregroundStyle(Palette.accentText)
            configuration.title
        }
    }
}

private struct ActivityChartCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = Usage.weekly(model.history, weeks: 26)
        let total = weeks.reduce(0) { $0 + $1.count }
        OverviewCard(title: "Updates Installed", symbol: "chart.bar.xaxis") {
            Text("\(total) in 26 weeks")
                .font(.callout)
                .foregroundStyle(.secondary)
        } content: {
            if total == 0 {
                CardEmpty(text: "Installs and updates show here as they happen.")
            } else {
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Updates", week.count))
                        .foregroundStyle(Palette.accent.gradient)
                        .cornerRadius(Radius.bar)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
            }
        }
    }
}

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = categories
        OverviewCard(title: "By Category", symbol: "square.stack.3d.up") {
            if rows.isEmpty {
                CardEmpty(text: "Categories show once the catalog loads.")
            } else {
                Chart(rows) { row in
                    BarMark(x: .value("Addons", row.count), y: .value("Category", row.name))
                        .foregroundStyle(Palette.accent.gradient)
                        .cornerRadius(Radius.bar)
                        .annotation(position: .trailing, spacing: Space.xs) {
                            Text("\(row.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: 180)
            }
        }
    }

    private var categories: [Usage.NameCount] {
        var counts: [String: Int] = [:]
        for addon in model.installed {
            let title = model.categories.first { $0.id == addon.catalog.categoryID }?.title ?? "Other"
            counts[title, default: 0] += 1
        }
        let sorted = counts.map { Usage.NameCount(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        guard sorted.count > 5 else { return sorted }
        let rest = sorted.dropFirst(4).reduce(0) { $0 + $1.count }
        return Array(sorted.prefix(4)) + [Usage.NameCount(name: "Everything Else", count: rest)]
    }
}

private struct RecentActivityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let events = Array(model.history.prefix(7))
        OverviewCard(title: "Recent Activity", symbol: "clock.arrow.circlepath") {
            if events.isEmpty {
                CardEmpty(text: "Nothing installed or updated yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        EventRow(event: event)
                        if event.id != events.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: HistoryEvent

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(event.kind == .remove ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.accentText))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(Usage.shortName(event.name)).lineLimit(1)
                Text(versions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            Text(event.date.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Space.sm)
        .contentShape(.rect)
        .onTapGesture {
            if let id = event.addonID ?? model.catalog.first(where: { $0.name == event.name })?.id {
                model.open(model.installed(id) == nil ? .findMore : .installed, selecting: id)
            }
        }
    }

    private var symbol: String {
        switch event.kind {
        case .install: "plus.circle.fill"
        case .update: "arrow.up.circle.fill"
        case .remove: "trash.circle.fill"
        }
    }

    private var versions: String {
        let kind = switch event.kind {
        case .install: "Installed"
        case .update: "Updated"
        case .remove: "Removed"
        }
        var text = kind
        if let from = event.previousVersion, let to = event.version, event.kind == .update {
            text += " \(from) → \(to)"
        } else if let to = event.version {
            text += " \(to)"
        }
        if event.fromMinion { text += " · by Minion" }
        return text
    }
}

private struct MostUpdatedCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = Usage.mostUpdated(model.history, limit: 7)
        let top = max(rows.first?.count ?? 1, 1)
        OverviewCard(title: "Updated Most Often", symbol: "flame") {
            if rows.isEmpty {
                CardEmpty(text: "The addons that change the most show here.")
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(rows) { row in
                        HStack(spacing: Space.md) {
                            Text(Usage.shortName(row.name))
                                .lineLimit(1)
                                .frame(width: 168, alignment: .leading)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Palette.accent.gradient)
                                    .frame(width: max(Space.sm, geo.size.width * CGFloat(row.count) / CGFloat(top)))
                            }
                            .frame(height: Space.sm)
                            Text("\(row.count)×")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                        .frame(height: 20)
                    }
                }
            }
        }
    }
}

/// Libraries the installed addons ask for that aren't installed: required ones first, flagged, then
/// optional ones that unlock extra features (logging, settings menus, chat output).
private struct LibrariesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let libraries = model.missingLibraries
        let required = libraries.filter(\.required).count
        OverviewCard(title: "Libraries for Installed Addons", symbol: "books.vertical") {
            HStack(spacing: Space.sm) {
                Text(summary(libraries.count, required)).font(.caption).foregroundStyle(.secondary)
                if model.installingLibraries {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Install All") { Task { await model.installLibraries() } }
                        .controlSize(.small)
                        .help("Install every library listed here")
                }
            }
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Space.lg, alignment: .top)], spacing: Space.md) {
                ForEach(libraries) { LibraryRow(library: $0) }
            }
        }
    }

    /// "Missing: 1 required, 3 optional".
    private func summary(_ count: Int, _ required: Int) -> String {
        let parts = [required > 0 ? "\(required) required" : nil, count > required ? "\(count - required) optional" : nil]
        return "Missing: " + parts.compactMap { $0 }.joined(separator: ", ")
    }
}

private struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let library: MissingLibrary

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: library.required ? "exclamationmark.triangle.fill" : "books.vertical")
                .foregroundStyle(library.required ? AnyShapeStyle(Palette.negative) : AnyShapeStyle(Palette.accentText))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(library.addon.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(wantedBy)
                    .font(.caption)
                    .foregroundStyle(library.required ? AnyShapeStyle(Palette.negative) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                if let error = model.errors[library.addon.id] {
                    Text(error).font(.caption).foregroundStyle(Palette.negative).lineLimit(1)
                }
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: Space.xs) {
                if model.busy.contains(library.addon.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Install") { Task { await model.install(library.addon.id) } }
                        .controlSize(.small)
                        .disabled(model.offline && model.details[library.addon.id] == nil)
                }
                RatingButtons(id: library.addon.id)
            }
        }
        .contentShape(.rect)
        .onTapGesture { model.open(.findMore, selecting: library.addon.id) }
        .help(library.required ? "\(library.wantedBy.joined(separator: ", ")) won't load without it, so it shows even with a thumbs down"
              : "Optional: \(library.wantedBy.joined(separator: ", ")) can use it for extra features. A thumbs down hides it.")
    }

    private var wantedBy: String {
        let names = library.wantedBy.prefix(3).joined(separator: ", ") + (library.wantedBy.count > 3 ? " and \(library.wantedBy.count - 3) more" : "")
        return library.required ? "Required by \(names)" : "Optional for \(names)"
    }
}

private struct PopularCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let installedIDs = Set(model.installed.map(\.id))
        let picks = model.catalog
            .filter { !installedIDs.contains($0.id) && $0.categoryID != AddonCategory.librariesID }
            .sorted { $0.downloadsMonthly > $1.downloadsMonthly }
            .prefix(6)
        OverviewCard(title: "Popular This Month", symbol: "sparkles") {
            Button("Find More") { model.open(.findMore) }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentText)
        } content: {
            if picks.isEmpty {
                CardEmpty(text: "You have every popular addon already.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Space.lg)], spacing: Space.md) {
                    ForEach(Array(picks)) { addon in
                        PopularRow(addon: addon)
                    }
                }
            }
        }
    }
}

/// The AI's picks from the catalog, given what is installed.
private struct SuggestionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let picks = model.suggestions
        OverviewCard(title: "Recommended for You", symbol: "sparkles") {
            HStack(spacing: Space.sm) {
                if model.isSuggesting {
                    ProgressView().controlSize(.small)
                } else if let date = model.suggestionsDate {
                    Text("\(model.aiSource) · \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(picks.isEmpty ? "Suggest Addons" : "Suggest Again") { Task { await model.suggestAddons() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accentText)
                    .disabled(model.isSuggesting || model.prefs.aiConfig.problem != nil)
                    .help("Ask \(model.aiSource) which popular addons would add something to the ones you have")
            }
        } content: {
            if let problem = model.prefs.aiConfig.problem {
                CardEmpty(text: problem)
            } else if let error = model.suggestError, picks.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.negative)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if picks.isEmpty {
                CardEmpty(text: model.isSuggesting ? "Reading your \(model.installed.count) addons…"
                          : "Suggestions based on the addons you have show here.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Space.lg, alignment: .top)], spacing: Space.md) {
                    ForEach(picks, id: \.addon.id) { pick in
                        AddonPickRow(addon: pick.addon, reason: pick.reason)
                    }
                }
            }
        }
        .task {
            // Ask on its own once a week; never in test or snapshot runs.
            if !model.offline, model.prefs.aiConfig.problem == nil, model.suggestionsStale, !model.installed.isEmpty {
                await model.suggestAddons()
            }
        }
    }
}

private struct PopularRow: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon

    var body: some View {
        HStack(spacing: Space.md) {
            Thumbnail(url: addon.thumbnails.first, size: 44)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(addon.name).lineLimit(1)
                Text("\(addon.author) · \(addon.downloadsMonthly.formatted(.number.notation(.compactName))) this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            if model.busy.contains(addon.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Install") { Task { await model.install(addon.id) } }
                    .controlSize(.small)
                    .disabled(model.offline && model.details[addon.id] == nil)
            }
        }
        .contentShape(.rect)
        .onTapGesture { model.open(.findMore, selecting: addon.id) }
    }
}

private struct CardEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
