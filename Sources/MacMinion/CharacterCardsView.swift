import AppKit
import MacMinionKit
import SwiftUI

/// One addon's data about one character: where it is and how big.
struct CharacterPlace: Identifiable {
    let file: String
    let addon: String
    let bytes: Int
    /// The character's table in that file, to open in the Inspector.
    let path: [LuaKey]
    var id: String { file }
}

/// Characters as cards (S-049): server, class, and level when MacMinion Companion is installed, and how
/// much addons keep about each. Characters no file names show apart. Click a card for its data by addon.
struct CharacterCardsView: View {
    let model: AppModel
    @State private var opened: SVUsage.Bucket?

    var body: some View {
        let characters = (model.gameFolder.usage?.characters ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let named = characters.filter { !$0.flagged }, unknown = characters.filter(\.flagged)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if !named.isEmpty { section(String(localized: "Your Characters"), named, probe: "characters-title") }
                if !unknown.isEmpty {
                    section(String(localized: "No Name Found"), unknown, probe: "unknown-title",
                            note: String(localized: "No file names these characters any more: deleted or renamed. What addons kept about them is still here."))
                }
            }
            .padding(Space.margin)
            .gridArea("characters")
        }
        .overlay {
            if model.gameFolder.usage == nil { InspectorLoadingView(model: model) }
            else if characters.isEmpty {
                ContentUnavailableView("No Characters Yet", systemImage: "person.2",
                                       description: Text("Addons save data about a character once you've played them."))
            }
        }
        .sheet(item: $opened) { CharacterSheet(model: model, bucket: $0) }
    }

    private func section(_ title: String, _ buckets: [SVUsage.Bucket], probe: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.headline)
                if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Space.md)], spacing: Space.md) {
                ForEach(buckets) { bucket in
                    Button { opened = bucket } label: { CharacterCard(model: model, bucket: bucket) }
                        .buttonStyle(.plain)
                        .help("Show what each addon keeps about \(bucket.title)")
                }
            }
        }
        .gridProbe(probe, area: "characters")
    }
}

/// "NA · Nightblade 50", or the server alone without the companion.
@MainActor func characterLine(_ model: AppModel, _ bucket: SVUsage.Bucket) -> String {
    let roster = model.gameFolder.roster?[bucket.id]
    let server = (roster?.server).map { [$0] } ?? bucket.servers
    var parts = server.map { $0.replacingOccurrences(of: " Megaserver", with: "") }
    if let roster {
        let who = [roster.className, roster.level.map { "\($0)" }].compactMap { $0 }.joined(separator: " ")
        if !who.isEmpty { parts.append(who) }
        if let cp = roster.champion, cp > 0 { parts.append("CP \(cp.formatted())") }
    }
    return parts.isEmpty ? "Server not saved" : parts.joined(separator: " · ")
}

private struct CharacterCard: View {
    let model: AppModel
    let bucket: SVUsage.Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Avatar(title: bucket.title, flagged: bucket.flagged)
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(bucket.flagged ? String(localized: "Unknown Character") : bucket.title).font(.headline).lineLimit(1)
                    Text(bucket.flagged ? bucket.id : characterLine(model, bucket))
                        .font(.caption)
                        .foregroundStyle(bucket.flagged ? AnyShapeStyle(Palette.negative) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            Text("\(Int64(bucket.bytes).formatted(.byteCount(style: .file))) in \(bucket.files) \(bucket.files == 1 ? "addon" : "addons")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(bucket.flagged ? AnyShapeStyle(Palette.negativeEdge) : AnyShapeStyle(.separator),
                                                                          style: StrokeStyle(lineWidth: 1, dash: bucket.flagged ? [4, 4] : [])))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
    }
}

private struct Avatar: View {
    let title: String
    let flagged: Bool

    var body: some View {
        ZStack {
            Circle().fill(flagged ? AnyShapeStyle(Palette.negativeWash) : AnyShapeStyle(Palette.accentWash))
            if flagged {
                Image(systemName: "person.fill.questionmark").foregroundStyle(Palette.negative)
            } else {
                Text(initials).font(.callout.weight(.semibold)).foregroundStyle(Palette.accentText)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = title.split(separator: " ").filter { $0.first?.isLetter == true }
        return String((words.count > 1 ? [words[0], words[words.count - 1]] : words).compactMap(\.first)).uppercased()
    }
}

/// What each addon keeps about one character, largest first; each opens in the Inspector.
private struct CharacterSheet: View {
    let model: AppModel
    let bucket: SVUsage.Bucket
    @Environment(\.dismiss) private var dismiss
    @State private var places: [CharacterPlace]?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Avatar(title: bucket.title, flagged: bucket.flagged)
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text(bucket.flagged ? String(localized: "Unknown Character") : bucket.title).font(.title2.bold())
                    Text(bucket.flagged ? "\(bucket.id) · " + String(localized: "no file names this character") : characterLine(model, bucket))
                        .foregroundStyle(.secondary)
                }
            }
            List {
                ForEach(places ?? []) { place in
                    HStack(spacing: Space.md) {
                        VStack(alignment: .leading, spacing: Space.xs / 2) {
                            Text(place.addon)
                            Text(place.file).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Int64(place.bytes).formatted(.byteCount(style: .file))).monospacedDigit().foregroundStyle(.secondary)
                        Button("Show") { show(place) }
                            .help("Open this in the Inspector")
                    }
                    .padding(.vertical, Space.xs / 2)
                }
            }
            .fitsContent(max: 480)
            .overlay { if places == nil { ProgressView() } }
            HStack {
                Text("\(Int64(bucket.bytes).formatted(.byteCount(style: .file))) in \(bucket.files) \(bucket.files == 1 ? "addon" : "addons")")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Connections") {
                    dismiss()
                    Task { await model.gameFolder.showConnections(SVTarget(.character, bucket.id)) }
                }
                .help("Show what's connected to this character, as a map")
                Button("Find Everywhere") {
                    dismiss()
                    Task { await model.gameFolder.findEverywhere(SVTarget(.character, bucket.id)) }
                }
                .help("List every place this character appears")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 560)
        .task { places = await model.gameFolder.characterPlaces(bucket) }
        .noInitialFocus()
        .onExitCommand { dismiss() }
    }

    private func show(_ place: CharacterPlace) {
        dismiss()
        Task { await model.gameFolder.reveal(file: place.file, path: place.path) }
    }
}
