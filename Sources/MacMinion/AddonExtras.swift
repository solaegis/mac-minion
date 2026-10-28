import MacMinionKit
import SwiftUI

/// Thumbs up and down for any addon. The AI favors addons like the liked ones; a thumbs down keeps
/// that addon out of suggestions and search results.
struct RatingButtons: View {
    @Environment(AppModel.self) private var model
    let id: Int

    var body: some View {
        let rating = model.rating(id)
        HStack(spacing: Space.xs) {
            Button { model.setRating(id, rating == .up ? nil : .up) } label: {
                Image(systemName: rating == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .foregroundStyle(rating == .up ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
            .help(rating == .up ? "Remove thumbs up" : "Thumbs up: suggest more addons like this")
            .accessibilityLabel("Thumbs up")
            .accessibilityAddTraits(rating == .up ? .isSelected : [])
            Button { model.setRating(id, rating == .down ? nil : .down) } label: {
                Image(systemName: rating == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .foregroundStyle(rating == .down ? AnyShapeStyle(Palette.negative) : AnyShapeStyle(.secondary))
            .help(rating == .down ? "Remove thumbs down" : "Thumbs down: never suggest this, and fewer like it")
            .accessibilityLabel("Thumbs down")
            .accessibilityAddTraits(rating == .down ? .isSelected : [])
        }
        .buttonStyle(.borderless)
    }
}

/// Thumbs up and down as menu items, for context menus.
struct RatingMenuItems: View {
    @Environment(AppModel.self) private var model
    let id: Int

    var body: some View {
        Toggle("Thumbs Up", systemImage: "hand.thumbsup",
               isOn: Binding(get: { model.rating(id) == .up }, set: { model.setRating(id, $0 ? .up : nil) }))
        Toggle("Thumbs Down", systemImage: "hand.thumbsdown",
               isOn: Binding(get: { model.rating(id) == .down }, set: { model.setRating(id, $0 ? .down : nil) }))
    }
}

/// Install any release ESOUI still has. Older ones are pinned (updates ignored).
struct VersionMenu: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon
    @State private var versions: [ArchivedVersion] = []
    @State private var failed = false

    var body: some View {
        let installedVersion = model.installed(addon.id)?.installedVersion
        Menu {
            if versions.isEmpty {
                Text(failed ? "ESOUI's version list isn't available" : "Loading versions…")
            }
            ForEach(versions) { v in
                Button {
                    Task { await model.install(addon.id, version: v) }
                } label: {
                    let latest = VersionText.same(v.version, addon.version)
                    let current = installedVersion.map { VersionText.same($0, v.version) } ?? false
                    Text("\(v.version)\(latest ? " (latest)" : "")\(current ? " ✓" : "")")
                    Text([v.date, v.size].filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
        } label: {
            Label("Version", systemImage: "clock.arrow.circlepath")
        }
        .fixedSize()
        .disabled(model.busy.contains(addon.id))
        .help("Install another version from ESOUI. An older version is pinned: Update All skips it until you install the latest.")
        .task {
            do { versions = try await model.loadVersions(addon.id) } catch { failed = true }
            if versions.isEmpty { failed = true }
        }
    }
}

// MARK: - AI search

/// "Describe what you want" at the top of the Overview, when an AI provider is set.
struct AISearchBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.md) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title3)
                .foregroundStyle(Palette.accentText)
            TextField("Describe the addon you want, like “track my crafting writs” or “a cleaner combat HUD”",
                      text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { Task { await model.aiSearch(model.searchQuery) } }
            if model.searchStage != nil {
                ProgressView().controlSize(.small)
            } else if !model.searchQuery.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { model.clearSearch() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Ask") { Task { await model.aiSearch(model.searchQuery) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.prefs.aiConfig.problem != nil)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .cardSurface(Radius.card, selected: focused)
        .help("Ask \(model.aiSource) to find catalog addons for what you describe")
    }
}

/// What the AI search found.
struct SearchResultsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let query = model.searchedFor {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Label("For “\(query)”", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                    Spacer()
                    if let stage = model.searchStage {
                        Text(stage).font(.caption).foregroundStyle(.secondary)
                    } else if !model.searchResults.isEmpty {
                        Text("\(model.aiSource) · thumbs up or down to steer it").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.searchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.negative)
                } else if model.searchResults.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Space.lg, alignment: .top)], spacing: Space.md) {
                        ForEach(model.searchResults, id: \.addon.id) { r in
                            AddonPickRow(addon: r.addon, reason: r.reason)
                        }
                    }
                }
            }
            .padding(Space.xl)
            .accentSurface(Radius.card)
        }
    }
}

/// One AI pick: thumbnail, name, why, thumbs, and Install (or its status when installed).
struct AddonPickRow: View {
    @Environment(AppModel.self) private var model
    let addon: CatalogAddon
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Thumbnail(url: addon.thumbnails.first, size: 44)
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(addon.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: Space.xs) {
                if model.busy.contains(addon.id) {
                    ProgressView().controlSize(.small)
                } else if let installed = model.installed(addon.id) {
                    StatusChip(status: installed.status, version: installed.installedVersion ?? addon.version)
                } else {
                    Button("Install") { Task { await model.install(addon.id) } }
                        .controlSize(.small)
                        .disabled(model.offline && model.details[addon.id] == nil)
                }
                RatingButtons(id: addon.id)
            }
        }
        .contentShape(.rect)
        .onTapGesture { model.open(.findMore, selecting: addon.id) }
        .contextMenu { RatingMenuItems(id: addon.id) }
    }
}
