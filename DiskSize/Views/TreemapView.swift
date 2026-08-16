import SwiftUI

/// A squarified treemap of the current folder's immediate children. Rectangle area
/// is proportional to byte size; fill color reflects reclaimability. Click a tile to
/// drill in (folders) or reveal (files). One level at a time — drilling recomputes.
struct TreemapView: View {
    @ObservedObject var model: ScanModel
    @State private var hover: DiskItem.ID?

    /// Only sized items with real bytes contribute tiles.
    private var items: [DiskItem] {
        model.sortedChildren.filter { $0.sizeKnown && $0.byteSize > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = Squarify.layout(items: items.map { ($0.id, Double($0.byteSize)) },
                                        in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    if let rect = tiles[item.id] {
                        tile(for: item, rect: rect)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func tile(for item: DiskItem, rect: CGRect) -> some View {
        let isHover = hover == item.id
        return RoundedRectangle(cornerRadius: 3)
            .fill(item.reclaim.color.opacity(item.reclaim == .keep ? 0.28 : 0.55))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.background, lineWidth: 1))
            .overlay(alignment: .topLeading) { label(for: item, rect: rect) }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(isHover ? 0.9 : 0), lineWidth: 2))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .help("\(item.name) — \(item.formattedSize)\(item.category.map { " · \($0.name)" } ?? "")")
            .onHover { hover = $0 ? item.id : (hover == item.id ? nil : hover) }
            .onTapGesture { model.open(item) }
    }

    @ViewBuilder
    private func label(for item: DiskItem, rect: CGRect) -> some View {
        if rect.width > 54 && rect.height > 26 {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.caption).bold().lineLimit(1)
                Text(item.formattedSize).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(4)
            .frame(maxWidth: rect.width, alignment: .leading)
        }
    }
}
