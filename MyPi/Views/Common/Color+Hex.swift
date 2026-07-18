import SwiftUI

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string — the format the MyPi
    /// server stores as each Pi-hole instance's display color. Returns nil
    /// for anything else so callers can fall back to a local palette.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
