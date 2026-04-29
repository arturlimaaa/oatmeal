import SwiftUI

/// Centralized speaker-color mapping for the Oatmeal design system.
///
/// Any surface that shows a speaker (transcript, notes, summary, citation
/// pills) should resolve its color through this mapping so speaker identity
/// stays visually consistent across the whole app.
public enum OatmealSpeakerColor {

    /// Deterministic color for a speaker name. Names are bucketed into five
    /// brand-palette slots so adding a new speaker does not shift existing
    /// speakers to new colors.
    public static func color(for name: String) -> Color {
        let slots: [Color] = [
            .om.ring,    // 0 — warm brown
            .om.sage2,   // 1 — moss green
            .om.oat2,    // 2 — toasted oat
            .om.ember,   // 3 — ember red
            .om.ink2,    // 4 — dark ink
        ]
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return .om.ink2 }
        var hash: UInt = 5381
        for scalar in trimmed.unicodeScalars {
            hash = (hash &* 33) &+ UInt(scalar.value)
        }
        return slots[Int(hash % UInt(slots.count))]
    }
}
