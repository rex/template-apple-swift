// ColorHex — hex-literal Color initializer.
//
// Exists so ColorPalette.swift can read as a palette. This is the only
// permitted caller; a `Color(hex:)` anywhere else is a Theme violation.

import SwiftUI

// nonisolated: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor would otherwise
// isolate this init, and the nonisolated ColorPalette statics call it.
nonisolated extension Color {
    /// Initialize from a 24-bit RGB or 32-bit ARGB literal.
    ///
    ///     Color(hex: 0x15141A)      // RGB
    ///     Color(hex: 0xFF15141A)    // ARGB
    internal init(hex: UInt32, alpha: Double = 1.0) {
        let hasAlpha = hex > 0xFF_FFFF
        let a = hasAlpha ? Double((hex >> 24) & 0xFF) / 255.0 : alpha
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
