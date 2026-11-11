import AppKit
import MacMinionKit
import SwiftUI

/// One node around the middle: a file that mentions the ID, or another ID stored with it.
private enum ConnectionNode: Identifiable {
    case file(String, Int)
    case neighbor(SVTarget, Int)

    var id: String {
        switch self {
        case .file(let name, _): "file|\(name)"
        case .neighbor(let t, _): "id|\(t.description)"
        }
    }
}

/// The map: the ID in the middle, the files that mention it and the IDs stored with it around it,
/// lines thicker for more mentions. Click an ID to follow it; click a file to open it there.
struct ConnectionsView: View {
    let model: AppModel

    var body: some View {
        if let hood = model.gameFolder.inspectorConnections {
            let nodes = (hood.files.prefix(SVNeighborhood.limit / 2).map { ConnectionNode.file($0.file, $0.count) })
                + hood.neighbors.prefix(SVNeighborhood.limit).map { ConnectionNode.neighbor($0.target, $0.count) }
            let most = max(1, nodes.map(weight).max() ?? 1)
            VStack(spacing: 0) {
                ZStack {
                    ConnectionSpokes(
                        count: nodes.count,
                        colors: nodes.map(color),
                        widths: nodes.map { 1 + 3 * CGFloat(weight($0)) / CGFloat(most) }
                    )
                    RadialLayout {
                        CenterNode(
                            title: model.gameFolder.connectionTitle(hood.target),
                            kind: centerKind(hood.target),
                            id: model.gameFolder.connectionTitle(hood.target).contains(hood.target.id) ? nil : hood.target.id,
                            symbol: hood.target.kind.symbol
                        )
                        ForEach(nodes) { node in
                            Button { Task { await open(node, from: hood.target) } } label: {
                                NodeLabel(title: title(node), detail: detail(node), color: color(node),
                                          symbol: symbol(node))
                            }
                            .buttonStyle(.plain)
                            .help(help(node))
                            .contextMenu {
                                if case .neighbor(let t, _) = node {
                                    Button("Show Connections") { Task { await model.gameFolder.showConnections(t) } }
                                    Button("Find Everywhere") { Task { model.gameFolder.closeConnections(); await model.gameFolder.findEverywhere(t) } }
                                }
                                if case .file(let name, _) = node {
                                    Button("Show in Tree") { Task { await model.gameFolder.revealFirst(hood.target, in: name) } }
                                }
                            }
                        }
                    }
                }
                .padding(Space.xl)
                .overlay {
                    if nodes.isEmpty {
                        ContentUnavailableView("Nothing Connected", systemImage: "point.3.connected.trianglepath.dotted",
                                               description: Text("No SavedVariables mention this."))
                    }
                }
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Space.lg) {
            legendItem(String(localized: "Files that mention it"), Palette.series2)
                .gridProbe("connections-legend-first", area: "connections-legend", edge: nil)
            legendItem(String(localized: "Characters and accounts"), Palette.accent)
            legendItem(String(localized: "Items, places, and other things"), Palette.series3)
            Spacer()
            Text("Click a thing to follow it. Thicker lines mean more mentions.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.sm)
        .background(.bar)
        .gridArea("connections-legend")
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        Label { Text(title) } icon: {
            RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)
                .fill(color.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)
                        .strokeBorder(color.opacity(0.55))
                }
                .frame(width: Space.md, height: Space.md)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func centerKind(_ target: SVTarget) -> String {
        if target.kind == .character { return characterHubLine(model, target.id) }
        return target.kind.title
    }

    private func symbol(_ node: ConnectionNode) -> String {
        switch node {
        case .file: "doc.text.fill"
        case .neighbor(let t, _): t.kind.symbol
        }
    }

    private func weight(_ node: ConnectionNode) -> Int {
        switch node {
        case .file(_, let n), .neighbor(_, let n): n
        }
    }

    private func color(_ node: ConnectionNode) -> Color {
        switch node {
        case .file: Palette.series2
        case .neighbor(let t, _): t.kind == .character || t.kind == .account ? Palette.accent : Palette.series3
        }
    }

    private func title(_ node: ConnectionNode) -> String {
        switch node {
        case .file(let name, _):
            // The file's own addon, not the folder it ships in: a library's data is its own.
            let base = String(name.dropLast(4))
            return model.addonTitle(folder: base.hasPrefix("ZO_") ? "ZO_" : base)
        case .neighbor(let t, _): return model.gameFolder.connectionTitle(t)
        }
    }

    private func detail(_ node: ConnectionNode) -> String {
        switch node {
        case .file(let name, let n): "\(name) · \(n == 1 ? "1 mention" : "\(n.formatted()) mentions")"
        case .neighbor(let t, let n): "\(t.kind.title) · \(n == 1 ? "1 time" : "\(n.formatted()) times")"
        }
    }

    private func help(_ node: ConnectionNode) -> String {
        switch node {
        case .file: String(localized: "Open this file where it mentions it")
        case .neighbor(let t, _): String(localized: "Show what's connected to \(model.gameFolder.connectionTitle(t))")
        }
    }

    private func open(_ node: ConnectionNode, from target: SVTarget) async {
        switch node {
        case .file(let name, _): await model.gameFolder.revealFirst(target, in: name)
        case .neighbor(let t, _): await model.gameFolder.showConnections(t)
        }
    }
}

struct CenterNode: View {
    let title: String
    let kind: String
    /// The ID the title names. Kept in the tooltip, not on the face — a 17-digit
    /// number in a circle is what made the hub unreadable.
    var id: String?
    var symbol: String = "circle.fill"

    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Palette.accentText)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(kind)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(Space.lg)
        .frame(width: RadialLayout.centerSize, height: RadialLayout.centerSize)
        .background(Palette.accentWash, in: Circle())
        .background(.background, in: Circle())
        .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
        .help(id.map { "\(title)\n\(kind)\n\($0)" } ?? "\(title)\n\(kind)")
    }
}

struct NodeLabel: View {
    let title: String
    let detail: String
    let color: Color
    var symbol: String = "circle.fill"

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: Space.xxl, height: Space.xxl)
                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.bar, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: RadialLayout.chipWidth, alignment: .leading)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        // An opaque base, so the lines behind stop at the node instead of running through its text.
        .background(.background, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(color.opacity(0.55)))
        .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .help("\(title)\n\(detail)")
    }
}

/// Spokes and faint guide rings that share RadialLayout's points, so lines meet the chips.
struct ConnectionSpokes: View {
    let count: Int
    let colors: [Color]
    let widths: [CGFloat]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let ring = RadialLayout.points(count: count, in: rect)
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let (rx, ry) = RadialLayout.radii(in: rect, count: count)
            let outer = Path(ellipseIn: CGRect(x: middle.x - rx, y: middle.y - ry, width: rx * 2, height: ry * 2))
            context.stroke(outer, with: .style(Color.secondary.opacity(0.20)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
            if RadialLayout.staggers(count, in: rect) {
                let scale = RadialLayout.innerScale
                let inner = Path(ellipseIn: CGRect(x: middle.x - rx * scale, y: middle.y - ry * scale,
                                                   width: rx * scale * 2, height: ry * scale * 2))
                context.stroke(inner, with: .style(Color.secondary.opacity(0.12)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
            }
            for i in ring.indices {
                guard let (start, end) = RadialLayout.spoke(from: middle, to: ring[i]) else { continue }
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .style(colors[i].opacity(0.55)),
                               style: StrokeStyle(lineWidth: widths[i], lineCap: .round))
            }
        }
    }
}

/// The first subview in the middle, the rest evenly around an ellipse, starting at the top.
/// Crowded maps use a second inner ring so labels stay on the canvas and do not overlap.
struct RadialLayout: Layout {
    static let centerSize: CGFloat = 192
    static let chipWidth: CGFloat = 168
    static let chipHeight: CGFloat = 44
    static let innerScale: CGFloat = 0.76
    private static let staggerFrom = 8

    static func radii(in rect: CGRect, count: Int = 12) -> (CGFloat, CGFloat) {
        let insetX = chipWidth / 2 + Space.xl
        let insetY = chipHeight / 2 + Space.xl
        let rx = max(0, rect.width / 2 - insetX)
        let ry = max(0, rect.height / 2 - insetY)
        // A handful of chips on a wide ellipse sit at the poles and look lost.
        // Keep those maps circular and closer in; busy maps keep the full oval.
        if count <= 3 {
            let r = min(rx, ry) * 0.62
            return (r, r)
        }
        if count <= 6 { return (rx * 0.80, ry * 0.80) }
        return (rx, ry)
    }

    static func staggers(_ count: Int, in rect: CGRect) -> Bool {
        let (rx, ry) = radii(in: rect, count: count)
        let innerMin = centerSize / 2 + Space.lg + chipHeight / 2
        return count >= staggerFrom && min(rx, ry) * innerScale > innerMin
    }

    static func points(count: Int, in rect: CGRect) -> [CGPoint] {
        guard count > 0 else { return [] }
        let (rx, ry) = radii(in: rect, count: count)
        let stagger = staggers(count, in: rect)
        return (0..<count).map { i in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
            let scale: CGFloat = stagger && !i.isMultiple(of: 2) ? innerScale : 1
            return CGPoint(x: rect.midX + rx * scale * CGFloat(cos(angle)),
                           y: rect.midY + ry * scale * CGFloat(sin(angle)))
        }
    }

    static func spoke(from middle: CGPoint, to point: CGPoint) -> (CGPoint, CGPoint)? {
        let dx = point.x - middle.x, dy = point.y - middle.y
        let dist = hypot(dx, dy)
        let startR = centerSize / 2 + Space.xs
        let endR = chipHeight / 2 + Space.xs
        guard dist > startR + endR else { return nil }
        let ux = dx / dist, uy = dy / dist
        return (CGPoint(x: middle.x + ux * startR, y: middle.y + uy * startR),
                CGPoint(x: point.x - ux * endR, y: point.y - uy * endR))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 760, height: 560))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let center = subviews.first else { return }
        center.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                     proposal: ProposedViewSize(width: Self.centerSize, height: Self.centerSize))
        let ring = Self.points(count: subviews.count - 1, in: bounds)
        for (subview, point) in zip(subviews.dropFirst(), ring) {
            subview.place(at: point, anchor: .center, proposal: ProposedViewSize(width: Self.chipWidth, height: nil))
        }
    }
}

extension SVName.Kind {
    var symbol: String {
        switch self {
        case .character: "person.fill"
        case .account: "person.crop.square.fill"
        case .guild: "shield.fill"
        case .item: "shippingbox.fill"
        case .set: "square.stack.fill"
        case .zone, .map: "map.fill"
        case .quest: "flag.fill"
        case .achievement: "trophy.fill"
        }
    }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}
