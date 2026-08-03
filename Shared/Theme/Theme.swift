// Theme — the design-token chokepoint.
//
// Every view reads Theme.color / Theme.font / Theme.spacing / Theme.radius /
// Theme.stroke / Theme.animation / Theme.opacity. Never Color(hex:), never
// .padding(12), never .font(.system(size: 17)). Re-skinning the app is editing
// this file and ColorPalette.swift; nothing else changes.
//
// `nonisolated` on every namespace is load-bearing: widget and complication
// views are built inside `nonisolated` TimelineProvider contexts, and a
// main-actor-isolated token would be unreadable from there. Nesting does not
// inherit isolation, so each namespace carries its own annotation.

import SwiftUI

public nonisolated enum Theme {

    // MARK: - Color

    public nonisolated enum color {
        public static var background: Color { ColorPalette.background }
        public static var surface: Color { ColorPalette.surface }
        public static var foreground: Color { ColorPalette.foreground }
        public static var muted: Color { ColorPalette.muted }
        public static var accent: Color { ColorPalette.accent }
        public static var success: Color { ColorPalette.success }
        public static var warning: Color { ColorPalette.warning }
        public static var danger: Color { ColorPalette.danger }

        public static var separator: Color { foreground.opacity(0.12) }
    }

    // MARK: - Font
    //
    // System faces only. Dynamic Type scales the text-style-based entries;
    // `hero` is fixed-size on purpose because it renders a timer that must not
    // reflow at accessibility sizes.

    public nonisolated enum font {
        public static var hero: Font { .system(size: 48, weight: .light, design: .rounded).monospacedDigit() }
        public static var title: Font { .system(.title2, design: .rounded).weight(.semibold) }
        public static var headline: Font { .system(.headline) }
        public static var body: Font { .system(.body) }
        public static var label: Font { .system(.subheadline).weight(.medium) }
        public static var caption: Font { .system(.caption2, design: .monospaced) }
    }

    // MARK: - Spacing (4-pt baseline scale)

    public nonisolated enum spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    // MARK: - Radius

    public nonisolated enum radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 20
        public static let xl: CGFloat = 28
        public static let pill: CGFloat = 9_999
    }

    // MARK: - Size
    //
    // `control` is Apple's 44-pt minimum hit target; anything interactive that
    // is not already a system control should meet it.

    public nonisolated enum size {
        public static let control: CGFloat = 44
        public static let icon: CGFloat = 24
    }

    // MARK: - Stroke

    public nonisolated enum stroke {
        public static let hairline: CGFloat = 0.5
        public static let thin: CGFloat = 1
        public static let medium: CGFloat = 2
        public static let thick: CGFloat = 4
    }

    // MARK: - Animation
    //
    // Computed rather than stored so the tokens carry no global storage.
    // Live Activities forbid continuous/repeating animations — value-keyed
    // implicit transitions only.

    public nonisolated enum animation {
        public static var snap: Animation { .spring(response: 0.28, dampingFraction: 0.85) }
        public static var smooth: Animation { .easeInOut(duration: 0.22) }
        public static var slow: Animation { .easeOut(duration: 0.45) }
    }

    // MARK: - Opacity

    public nonisolated enum opacity {
        public static let disabled: Double = 0.35
        public static let secondary: Double = 0.6
        public static let primary: Double = 1.0
    }

    // MARK: - Font registration seam

    /// Deliberately a no-op.
    ///
    /// The template ships system faces only — no bundled `.ttf`, no
    /// `CTFontManagerRegisterFontsForURL`. Every `@main` entry point and every
    /// `WidgetBundle.init()` already calls this, so adding a custom face later
    /// is one function body rather than an archaeology exercise across eight
    /// targets. Keep the call sites even while this stays empty.
    public static func registerFonts() {}
}
