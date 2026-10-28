import MacMinionKit
import SwiftUI

// MARK: - Layout

/// The span a card asks for. Read by BentoLayout.
nonisolated private struct SpanKey: LayoutValueKey {
    static let defaultValue = BentoSpan.small
}

extension View {
    func bentoSpan(_ span: BentoSpan) -> some View { layoutValue(key: SpanKey.self, value: span) }
}

/// A grid of equal cells where cards span one or two cells each way, packed densely (BentoPacker).
nonisolated struct BentoLayout: Layout {
    var minCellWidth: CGFloat
    var cellHeight: CGFloat
    var spacing: CGFloat = Space.md

    private func columns(for width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (minCellWidth + spacing)))
    }

    private func cellWidth(_ width: CGFloat, _ columns: Int) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // SwiftUI also asks with nil and infinite widths while it measures; answer for four columns then.
        let proposed = proposal.width ?? .infinity
        let width = proposed.isFinite ? proposed : minCellWidth * 4 + spacing * 3
        let (_, rows) = BentoPacker.place(subviews.map { $0[SpanKey.self] }, columns: columns(for: width))
        return CGSize(width: width, height: rows == 0 ? 0 : CGFloat(rows) * (cellHeight + spacing) - spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(for: bounds.width)
        let cw = cellWidth(bounds.width, cols)
        let (slots, _) = BentoPacker.place(subviews.map { $0[SpanKey.self] }, columns: cols)
        for (view, slot) in zip(subviews, slots) {
            let size = CGSize(width: CGFloat(slot.span.width) * cw + CGFloat(slot.span.width - 1) * spacing,
                              height: CGFloat(slot.span.height) * cellHeight + CGFloat(slot.span.height - 1) * spacing)
            let origin = CGPoint(x: bounds.minX + CGFloat(slot.column) * (cw + spacing),
                                 y: bounds.minY + CGFloat(slot.row) * (cellHeight + spacing))
            view.place(at: origin, proposal: ProposedViewSize(size))
        }
    }
}

/// A titled run of bento cards.
struct BentoSection<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let count: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(title).font(.title3.bold())
                Text(count.formatted())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            BentoLayout(minCellWidth: model.prefs.cardSize.minWidth, cellHeight: model.prefs.cardSize.cellHeight) {
                content
            }
        }
    }
}

// MARK: - Cards

/// One addon as a bento card. What it shows grows with its span.
struct AddonCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let addon: CatalogAddon
    let installed: InstalledAddon?
    let span: BentoSpan
    @State private var hovering = false

    private var selected: Bool { model.selection == .addon(addon.id) }
    private var isLarge: Bool { span.height > 1 }
    private var isWide: Bool { span.width > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if isLarge && model.prefs.showThumbnails {
                Thumbnail(url: addon.images.first ?? addon.thumbnails.first, size: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: Radius.card - Space.md))
            }
            HStack(alignment: .top, spacing: Space.md) {
                if model.prefs.showThumbnails && !isLarge {
                    Thumbnail(url: addon.thumbnails.first, size: isWide ? 56 : 36)
                }
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(addon.name)
                        .font(isWide ? .headline : .body.weight(.semibold))
                        .lineLimit(isWide || isLarge ? 1 : 2)
                    Text(addon.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !isLarge { Spacer(minLength: 0) }
            footer
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(isWide || isLarge ? Radius.card : Radius.tile, selected: selected)
        .scaleEffect(Motion.hoverScale(hovering, reduceMotion: reduceMotion))
        .animation(Motion.hover, value: hovering)
        .contentShape(.rect(cornerRadius: Radius.card))
        .onHover { hovering = $0 }
        .onTapGesture { model.selection = .addon(addon.id) }
        .contextMenu { if let installed { InstalledMenu(addon: installed) } else { FindMoreMenu(addon: addon) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: Space.sm) {
            if let error = model.errors[addon.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
                    .lineLimit(1)
            } else if let installed {
                StatusChip(status: installed.status, version: versionText(installed))
            } else {
                Label(addon.downloadsMonthly.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("\(addon.downloadsMonthly.formatted()) downloads this month")
                if isWide || isLarge {
                    Label(addon.favorites.formatted(.number.notation(.compactName)), systemImage: "heart")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            RatingButtons(id: addon.id)
            if let installed, !model.busy.contains(addon.id) {
                RemoveButton(name: addon.name) { model.pendingRemoval = installed }
            }
            action
        }
    }

    private func versionText(_ installed: InstalledAddon) -> String {
        if installed.status == .updateAvailable, isWide, let v = installed.installedVersion {
            return "\(v) → \(addon.version)"
        }
        return installed.installedVersion ?? addon.version
    }

    @ViewBuilder
    private var action: some View {
        if model.busy.contains(addon.id) {
            ProgressView().controlSize(.small)
        } else if installed?.status == .updateAvailable {
            Button("Update") { Task { await model.install(addon.id) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else if installed == nil, isWide || isLarge {
            Button("Install") { Task { await model.install(addon.id) } }
                .controlSize(.small)
                .disabled(model.offline && model.details[addon.id] == nil)
        }
    }
}

/// A folder no catalog entry lists, as a small card.
struct FolderCard: View {
    @Environment(AppModel.self) private var model
    let folder: UnmatchedFolder

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs / 2) {
            Label(folder.title, systemImage: "folder")
                .font(.body.weight(.semibold))
                .lineLimit(2)
            Text(folder.manifest?.author ?? folder.folder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack {
                if let version = folder.manifest?.version {
                    Text(version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                RemoveButton(name: folder.title) { model.pendingFolderRemoval = folder }
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(Radius.tile, selected: model.selection == .folder(folder.folder))
        .contentShape(.rect(cornerRadius: Radius.tile))
        .onTapGesture { model.selection = .folder(folder.folder) }
        .contextMenu {
            Button("Show in Finder") { model.showInFinder(folder.folder) }
            Divider()
            Button("Remove…", role: .destructive) { model.pendingFolderRemoval = folder }
        }
    }
}

/// A small trash button on an installed tile. It asks first; the folders go to the Trash.
struct RemoveButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove \(name)… Its folders go to the Trash; saved settings stay.")
        .accessibilityLabel("Remove \(name)")
    }
}

/// "Up to date 3.16.5" and friends, in one color scheme.
struct StatusChip: View {
    let status: AddonStatus
    let version: String

    var body: some View {
        Label {
            Text(version).monospacedDigit().lineLimit(1)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption)
        .foregroundStyle(color)
        .help(status.label)
    }

    private var symbol: String {
        switch status {
        case .upToDate: "checkmark.circle.fill"
        case .updateAvailable: "arrow.up.circle.fill"
        case .ignored: "bell.slash"
        case .versionUnknown: "questionmark.circle"
        }
    }

    private var color: AnyShapeStyle {
        switch status {
        case .upToDate: AnyShapeStyle(Palette.positive)
        case .updateAvailable: AnyShapeStyle(Palette.accentText)
        case .ignored, .versionUnknown: AnyShapeStyle(.secondary)
        }
    }
}

/// An ESOUI preview image, or a puzzle piece on an accent wash while it loads or when there is none.
struct Thumbnail: View {
    let url: URL?
    /// A square side, or nil to fill the space given.
    let size: CGFloat?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(size.map { .system(size: $0 * 0.45) } ?? .largeTitle)
                .foregroundStyle(Palette.accentText.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.accentWash)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: Radius.chip))
        .accessibilityHidden(true)
    }
}

struct FindMoreMenu: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon

    var body: some View {
        Button("Install") { Task { await model.install(addon.id) } }
            .disabled(model.busy.contains(addon.id))
        if let url = addon.infoURL {
            Link("Open on ESOUI", destination: url)
        }
        Divider()
        RatingMenuItems(id: addon.id)
    }
}

// MARK: - Pages

struct InstalledGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.prefs
        let shown = model.filteredInstalled
        let updates = prefs.featureUpdates ? shown.filter { $0.status == .updateAvailable } : []
        let rest = shown.filter { !updates.contains($0) }
        let libraries = prefs.groupLibraries ? rest.filter { $0.catalog.categoryID == AddonCategory.librariesID } : []
        let addons = rest.filter { !libraries.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if !updates.isEmpty {
                    BentoSection(title: "Updates Ready", count: updates.count) {
                        ForEach(updates) { card($0, span: .wide) }
                    }
                }
                if !addons.isEmpty {
                    BentoSection(title: prefs.groupLibraries ? "Addons" : "Installed", count: addons.count) {
                        ForEach(addons) { card($0, span: .small) }
                    }
                }
                if !libraries.isEmpty {
                    BentoSection(title: "Libraries", count: libraries.count) {
                        ForEach(libraries) { card($0, span: .small) }
                    }
                }
                if !model.filteredUnmatched.isEmpty {
                    BentoSection(title: "Not on ESOUI", count: model.filteredUnmatched.count) {
                        ForEach(model.filteredUnmatched) { FolderCard(folder: $0) }
                    }
                }
            }
            .padding(Space.margin)
            .gridArea("grid")
        }
        .overlay {
            if model.installedFiltered && shown.isEmpty && model.filteredUnmatched.isEmpty {
                NoMatches(scope: .installed)
            } else if model.installed.isEmpty && model.unmatched.isEmpty {
                ContentUnavailableView {
                    Label("No Addons Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text(model.catalog.isEmpty ? "The ESOUI catalog hasn't loaded yet." : "Nothing is installed in \(model.addonsFolder.path).")
                } actions: {
                    SettingsLink { Text("Choose Folder…") }
                }
            }
        }
    }

    private func card(_ addon: InstalledAddon, span: BentoSpan) -> some View {
        AddonCard(addon: addon.catalog, installed: addon, span: span).bentoSpan(span)
    }
}

struct FindMoreGrid: View {
    @Environment(AppModel.self) private var model
    /// Cards shown so far; Show More adds a page. The full catalog in one layout pass would stall.
    @State private var limit = 120

    /// How many results get wide cards in the featured section.
    static let featuredCount = 4

    var body: some View {
        let results = model.findMoreResults
        let featuring = model.prefs.featurePopular && model.search.isEmpty && model.sort != .name && !model.findMoreFilter.isActive
        let featured = featuring ? Array(results.prefix(Self.featuredCount)) : []
        let rest = Array(results.dropFirst(featured.count))
        let shown = Array(rest.prefix(limit))
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if !featured.isEmpty {
                    BentoSection(title: model.sort.title, count: featured.count) {
                        ForEach(featured) { card($0, span: .wide) }
                    }
                }
                // Every card in the main grid is the same size.
                BentoSection(title: featured.isEmpty ? "Results" : "More Addons", count: rest.count) {
                    ForEach(shown) { card($0, span: .small) }
                }
                if rest.count > shown.count {
                    Button("Show More (\((rest.count - shown.count).formatted()) left)") { limit += 120 }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Space.margin)
            .gridArea("grid")
        }
        .onChange(of: model.search) { limit = 120 }
        .onChange(of: model.category) { limit = 120 }
        .overlay {
            if results.isEmpty {
                if model.findMoreFilter.isActive {
                    NoMatches(scope: .findMore)
                } else if !model.catalogResults(includeInstalled: true).isEmpty {
                    ContentUnavailableView("Already Installed", systemImage: "checkmark.circle",
                                           description: Text(model.search.isEmpty ? "You have every addon here. See Installed."
                                                             : "Everything matching “\(model.search)” is installed. See Installed."))
                } else if model.search.isEmpty {
                    ContentUnavailableView("No Addons", systemImage: "magnifyingglass")
                } else {
                    ContentUnavailableView.search(text: model.search)
                }
            }
        }
    }

    private func card(_ addon: CatalogAddon, span: BentoSpan) -> some View {
        AddonCard(addon: addon, installed: model.installed(addon.id), span: span).bentoSpan(span)
    }
}
