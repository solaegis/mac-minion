import MacMinionKit
import SwiftUI

/// Which page a filter menu or chip row belongs to.
enum FilterScope { case installed, findMore }

/// The toolbar Filter menu for Installed and Find More. Its icon fills while any filter is on.
struct FilterMenu: ToolbarContent {
    @Environment(AppModel.self) private var model
    let scope: FilterScope

    var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                FilterMenuItems(scope: scope)
            } label: {
                Label("Filter", systemImage: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
            }
            .help(scope == .installed ? String(localized: "Filter installed addons by category, status, or rating, and sort them")
                  : String(localized: "Filter the catalog by category, age, game version, or rating, and sort it"))
        }
    }

    private var active: Bool { scope == .installed ? model.installedFilter.isActive : model.findMoreFilter.isActive }
}

struct FilterMenuItems: View {
    @Environment(AppModel.self) private var model
    let scope: FilterScope

    var body: some View {
        @Bindable var model = model
        let filter = scope == .installed ? $model.installedFilter : $model.findMoreFilter
        Picker("Category", selection: filter.category) {
            Text("All Categories").tag(Int?.none)
            Divider()
            if scope == .installed {
                ForEach(model.installedCategories, id: \.category.id) { c in
                    Text("\(c.category.title) (\(c.count))").tag(Int?.some(c.category.id))
                }
            } else {
                ForEach(model.categories.sorted { $0.title < $1.title }) { c in
                    Text("\(c.title) (\(c.fileCount.formatted()))").tag(Int?.some(c.id))
                }
            }
        }
        if scope == .installed {
            Picker("Status", selection: filter.status) {
                Text("Any Status").tag(AddonStatus?.none)
                Divider()
                ForEach([AddonStatus.updateAvailable, .upToDate, .ignored, .versionUnknown], id: \.self) { s in
                    Text(s.label).tag(AddonStatus?.some(s))
                }
            }
        } else {
            Picker("Updated", selection: filter.recency) {
                ForEach(Recency.allCases) { Text($0.title).tag($0) }
            }
        }
        Picker("Rating", selection: filter.rating) {
            ForEach(RatingFilter.allCases) { Text($0.title).tag($0) }
        }
        Toggle(model.currentGame.map { String(localized: "Works with \($0.name) (\($0.version))") } ?? String(localized: "Works with the Current Game Version"),
               isOn: filter.compatibleOnly)
        Toggle("Hide Libraries", isOn: filter.hideLibraries)
        Divider()
        if scope == .installed {
            Picker("Sort By", selection: $model.installedSort) {
                ForEach(InstalledSort.allCases) { Text($0.title).tag($0) }
            }
        } else {
            Picker("Sort By", selection: $model.sort) {
                ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
            }
        }
        Divider()
        Button("Clear Filters") { scope == .installed ? model.clearInstalledFilters() : model.clearFindMoreFilters() }
            .disabled(scope == .installed ? !model.installedFiltered : !model.findMoreFilter.isActive && model.search.isEmpty)
    }
}

/// The filters that are on, as chips above the results. Click a chip's × to turn that one off.
struct FilterChips: View {
    @Environment(AppModel.self) private var model
    let scope: FilterScope

    var body: some View {
        let chips = self.chips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(chips, id: \.title) { chip in
                        Button(action: chip.clear) {
                            HStack(spacing: Space.xs) {
                                Text(chip.title).lineLimit(1)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .font(.callout)
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.xs)
                            .foregroundStyle(Palette.accentText)
                            .background(Palette.accentWash, in: .capsule)
                            .overlay { Capsule().strokeBorder(Palette.accentEdge) }
                        }
                        .buttonStyle(.plain)
                        .help("Turn off this filter")
                    }
                    if chips.count > 1 {
                        Button("Clear All") { scope == .installed ? model.clearInstalledFilters() : model.clearFindMoreFilters() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.sm)
            }
            .background(.bar)
        }
    }

    private struct Chip {
        let title: String
        let clear: () -> Void
    }

    private var chips: [Chip] {
        let f = scope == .installed ? model.installedFilter : model.findMoreFilter
        func set(_ change: @escaping (inout BrowseFilter) -> Void) -> () -> Void {
            { [model, scope] in
                if scope == .installed { change(&model.installedFilter) } else { change(&model.findMoreFilter) }
            }
        }
        var out: [Chip] = []
        if let id = f.category, let c = model.categories.first(where: { $0.id == id }) {
            out.append(Chip(title: c.title, clear: set { $0.category = nil }))
        }
        if let s = f.status { out.append(Chip(title: s.label, clear: set { $0.status = nil })) }
        if f.recency != .any { out.append(Chip(title: String(localized: "Updated \(f.recency.title.localizedLowercase)"), clear: set { $0.recency = .any })) }
        if f.rating != .any { out.append(Chip(title: f.rating.title, clear: set { $0.rating = .any })) }
        if f.compatibleOnly { out.append(Chip(title: String(localized: "Current game version"), clear: set { $0.compatibleOnly = false })) }
        if f.hideLibraries { out.append(Chip(title: String(localized: "No libraries"), clear: set { $0.hideLibraries = false })) }
        if let author = f.author { out.append(Chip(title: String(localized: "By \(author)"), clear: set { $0.author = nil })) }
        return out
    }
}

/// "No addons match" with a way out, for a filtered page that came up empty.
struct NoMatches: View {
    @Environment(AppModel.self) private var model
    let scope: FilterScope

    var body: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No addons match these filters.")
        } actions: {
            Button("Clear Filters") { scope == .installed ? model.clearInstalledFilters() : model.clearFindMoreFilters() }
        }
    }
}

extension AppModel {
    /// Shows only addons by this creator (S-065): on Find More (and from the Overview) every one they publish on
    /// ESOUI, elsewhere the installed ones. A chip clears it.
    func showAddons(by author: String) {
        if sidebar == .findMore || sidebar == .overview {
            if sidebar != .findMore { open(.findMore) }
            findMoreFilter.author = author
        } else {
            if sidebar != .installed { open(.installed) }
            installedFilter.author = author
        }
    }

    /// The selected addon's creator, for Addons › Show Addons by Creator.
    var selectedAuthor: String? {
        guard case .addon(let id)? = selection else { return nil }
        return catalog.first { $0.id == id }?.author
    }
}

/// A creator's name that filters the page to their addons. Styled by the caller, like the text it replaces.
struct AuthorLink: View {
    @Environment(AppModel.self) private var model
    let author: String
    /// "by sirinsidiator" in the detail panel; the name alone elsewhere.
    var prefixed = false
    @State private var hovering = false

    var body: some View {
        Button { model.showAddons(by: author) } label: {
            Text(prefixed ? String(localized: "by \(author)") : author)
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Show every addon by \(author) (Option-Command-A)"))
    }
}
