// ColorPalette — the ONE place raw color literals live.
//
// Views never read this directly; they read Theme.color.*, which delegates
// here. A design swap is this file plus Theme.swift.
//
// The shipped palette is a single fixed (dark) scheme, which is what watchOS
// and every accessory widget family render against anyway. Two documented
// upgrade paths when the app needs light mode: move each token to a Color Set
// in Assets.xcassets and read `Color("Accent", bundle: .main)`, or add a
// dynamic-provider helper (UIColor(dynamicProvider:) on iOS,
// NSColor(name:dynamicProvider:) on macOS — neither exists on watchOS, hence
// the fixed default).

import SwiftUI

internal nonisolated enum ColorPalette {
    // Surfaces.
    static let background = Color(hex: 0x15141A)
    static let surface = Color(hex: 0x1F1E24)
    static let foreground = Color(hex: 0xF5F4FA)

    // Hierarchy.
    static let muted = Color(hex: 0xA8A6B3)
    static let accent = Color(hex: 0x6CE5FF)

    // Semantic.
    static let success = Color(hex: 0x4FD680)
    static let warning = Color(hex: 0xFFB454)
    static let danger = Color(hex: 0xFF6B6B)
}
