import Foundation
import SwiftUI

/// How safe an item is to delete.
enum Reclaimability: String, Codable {
    case keep       // user data / apps — do not suggest deleting
    case caution    // often reclaimable but verify first
    case safe       // caches / build output — regenerated on demand

    var label: String {
        switch self {
        case .keep: return "Keep"
        case .caution: return "Caution"
        case .safe: return "Safe to clear"
        }
    }

    var color: Color {
        switch self {
        case .keep: return .secondary
        case .caution: return .orange
        case .safe: return .green
        }
    }

    /// Sort weight so "safe" reclaimable items rank first.
    var priority: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .keep: return 2
        }
    }
}

/// The classification of a filesystem entry: what it is and whether it's reclaimable.
struct ReclaimCategory: Hashable {
    let name: String            // e.g. "npm packages", "Xcode DerivedData", "App cache"
    let reclaim: Reclaimability
    let reason: String          // short human explanation
    let reproducible: Bool      // can be regenerated (npm install, rebuild, re-download)

    static let unknown = ReclaimCategory(
        name: "—", reclaim: .keep, reason: "Unclassified", reproducible: false)
}
