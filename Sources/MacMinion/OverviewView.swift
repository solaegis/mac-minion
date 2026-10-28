import Charts
import MacMinionKit
import SwiftUI

/// The home page: how the addons stand today and how MacMinion (and Minion before it) has kept them current.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                OverviewHero()
                StatTiles()
                // Two by two, each card as tall as its neighbour.
                Grid(horizontalSpacing: Space.lg, verticalSpacing: Space.lg) {
                    GridRow {
                        ActivityChartCard()
                        CategoryCard()
                    }
                    GridRow {
                        RecentActivityCard()
                        MostUpdatedCard()
                    }
                }
                PopularCard()
            }
            .padding(Space.section)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
            .gridArea("overview", inset: Space.section)
        }
        .navigationTitle("Overview")
        .toolbar { RefreshButton() }
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
                .offset(x: 40, y: 24)
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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(highlighted ? Palette.onAccent : Palette.accentText)
                    .frame(width: 32, height: 32)
                    .background(highlighted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.accent.opacity(0.14)),
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
            .background(.background.secondary, in: .rect(cornerRadius: Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .strokeBorder(highlighted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.separator),
                                  lineWidth: highlighted ? 1.5 : 0.5)
            }
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.snappy(duration: 0.15), value: hovering)
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
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.separator, lineWidth: 0.5) }
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
                        .cornerRadius(Space.xs / 2)
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
                        .cornerRadius(Space.xs / 2)
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
                .buttonStyle(.link)
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

private struct PopularRow: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon

    var body: some View {
        HStack(spacing: Space.md) {
            AsyncImage(url: addon.thumbnails.first) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: Space.sm))
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
