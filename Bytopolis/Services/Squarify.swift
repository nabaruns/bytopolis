import Foundation
import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing & van Wijk, 2000).
///
/// Packs weighted items into a rectangle so each tile's area is proportional to its
/// value while keeping tiles close to square (readable). Returns one `CGRect` per id.
enum Squarify {
    static func layout(items: [(id: String, value: Double)], in rect: CGRect) -> [String: CGRect] {
        let positive = items.filter { $0.value > 0 }
        let total = positive.reduce(0) { $0 + $1.value }
        guard total > 0, rect.width > 0, rect.height > 0 else { return [:] }

        // Scale values so the sum of areas equals the rectangle's pixel area.
        let scale = Double(rect.width * rect.height) / total
        var remaining = positive.map { (id: $0.id, area: $0.value * scale) }
        var result: [String: CGRect] = [:]
        var free = rect
        var row: [(id: String, area: Double)] = []

        func shortSide(_ r: CGRect) -> CGFloat { min(r.width, r.height) }

        /// Worst (largest) aspect ratio in a row laid along `side`.
        func worst(_ row: [(id: String, area: Double)], _ side: CGFloat) -> Double {
            guard !row.isEmpty, side > 0 else { return .greatestFiniteMagnitude }
            let areas = row.map { $0.area }
            let sum = areas.reduce(0, +)
            let maxA = areas.max() ?? 0
            let minA = areas.min() ?? 0
            guard minA > 0 else { return .greatestFiniteMagnitude }
            let s2 = sum * sum
            let side2 = Double(side * side)
            return max(side2 * maxA / s2, s2 / (side2 * minA))
        }

        func layoutRow(_ row: [(id: String, area: Double)], in container: inout CGRect) {
            let sum = row.reduce(0) { $0 + $1.area }
            guard sum > 0 else { return }
            if container.width >= container.height {
                let w = CGFloat(sum) / container.height        // column on the left
                var y = container.minY
                for cell in row {
                    let h = container.height * CGFloat(cell.area / sum)
                    result[cell.id] = CGRect(x: container.minX, y: y, width: w, height: h)
                    y += h
                }
                container = CGRect(x: container.minX + w, y: container.minY,
                                   width: container.width - w, height: container.height)
            } else {
                let h = CGFloat(sum) / container.width          // row on the top
                var x = container.minX
                for cell in row {
                    let w = container.width * CGFloat(cell.area / sum)
                    result[cell.id] = CGRect(x: x, y: container.minY, width: w, height: h)
                    x += w
                }
                container = CGRect(x: container.minX, y: container.minY + h,
                                   width: container.width, height: container.height - h)
            }
        }

        while !remaining.isEmpty {
            let next = remaining[0]
            let side = shortSide(free)
            let withNext = worst(row + [next], side)
            let current = row.isEmpty ? Double.greatestFiniteMagnitude : worst(row, side)

            if row.isEmpty || withNext <= current {
                row.append(next)
                remaining.removeFirst()
            } else {
                layoutRow(row, in: &free)
                row = []
            }
        }
        if !row.isEmpty { layoutRow(row, in: &free) }
        return result
    }
}
