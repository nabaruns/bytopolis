import SwiftUI

/// A squarified treemap of the current folder's immediate children, drawn with a
/// `Canvas` so tiles are clipped strictly to the view (no overflow). Tile area is
/// proportional to size; color is graded — hue by reclaimability, saturation and
/// depth by relative size. Click a tile to drill in; hover highlights it.
struct TreemapView: View {
    @ObservedObject var model: ScanModel
    @State private var hoverID: DiskItem.ID?

    /// Only sized items with real bytes get a tile.
    private var items: [DiskItem] {
        model.sortedChildren.filter { $0.sizeKnown && $0.byteSize > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = Squarify.layout(items: items.map { ($0.id, Double($0.byteSize)) },
                                        in: CGRect(origin: .zero, size: geo.size))
            Canvas { ctx, _ in
                for item in items {
                    guard let r = tiles[item.id], r.width > 1, r.height > 1 else { continue }
                    draw(item, in: r.insetBy(dx: 0.75, dy: 0.75), ctx: &ctx)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                if let item = hit(g.location, tiles) { model.open(item) }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverID = hit(p, tiles)?.id
                case .ended: hoverID = nil
                }
            }
            .overlay(alignment: .bottomLeading) { legend.padding(8) }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Drawing

    private func draw(_ item: DiskItem, in rect: CGRect, ctx: inout GraphicsContext) {
        let frac = model.largest > 0 ? Double(item.byteSize) / Double(model.largest) : 0
        let (fill, dark) = Self.tileColor(reclaim: item.reclaim, sizeFraction: frac)
        let path = Path(roundedRect: rect, cornerRadius: 3)

        // Subtle vertical gradient for depth.
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [fill.opacity(0.92), fill]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)
        if item.id == hoverID {
            ctx.stroke(path, with: .color(.primary), lineWidth: 2)
        }

        guard rect.width > 54, rect.height > 26 else { return }
        let labelColor: Color = dark ? .white : .black.opacity(0.85)
        ctx.draw(Text(item.name).font(.caption).bold().foregroundColor(labelColor),
                 at: CGPoint(x: rect.minX + 6, y: rect.minY + 5), anchor: .topLeading)
        var sub = item.formattedSize
        if let cat = item.category, cat.reclaim != .keep { sub += " · " + cat.name }
        ctx.draw(Text(sub).font(.caption2).foregroundColor(labelColor.opacity(0.75)),
                 at: CGPoint(x: rect.minX + 6, y: rect.minY + 19), anchor: .topLeading)
    }

    private func hit(_ point: CGPoint, _ tiles: [DiskItem.ID: CGRect]) -> DiskItem? {
        for item in items {
            if let r = tiles[item.id], r.contains(point) { return item }
        }
        return nil
    }

    /// Hue from reclaimability; saturation + depth graded by relative size.
    /// Returns the fill color and whether it's dark enough to need light text.
    static func tileColor(reclaim: Reclaimability, sizeFraction frac: Double) -> (Color, Bool) {
        let f = max(0, min(1, frac))
        let hue: Double
        switch reclaim {
        case .keep:    hue = 0.58   // cool blue-grey
        case .caution: hue = 0.08   // orange
        case .safe:    hue = 0.38   // green
        }
        let saturation = (reclaim == .keep ? 0.10 : 0.30) + 0.55 * f
        let brightness = 0.96 - 0.34 * f
        return (Color(hue: hue, saturation: saturation, brightness: brightness), brightness < 0.6)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([Reclaimability.safe, .caution, .keep], id: \.self) { r in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.tileColor(reclaim: r, sizeFraction: 0.7).0)
                        .frame(width: 11, height: 11)
                    Text(r.label).font(.caption2)
                }
            }
            Text("· darker = larger").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}
