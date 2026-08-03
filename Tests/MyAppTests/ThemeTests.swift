import SwiftUI
import Testing

@testable import MyApp

/// Token sanity, not pixel assertions. These catch the two mistakes that
/// actually happen when someone re-skins the app: an out-of-order scale, and a
/// token that silently became zero.
@Suite("Theme tokens")
nonisolated struct ThemeTests {
    @Test("the spacing scale is strictly increasing")
    func spacingScale() {
        let scale: [CGFloat] = [
            Theme.spacing.xxs,
            Theme.spacing.xs,
            Theme.spacing.small,
            Theme.spacing.medium,
            Theme.spacing.large,
            Theme.spacing.xl,
            Theme.spacing.xxl,
        ]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
        #expect(scale.allSatisfy { $0 > 0 })
    }

    @Test("the radius scale is strictly increasing and positive")
    func radiusScale() {
        let scale: [CGFloat] = [
            Theme.radius.small,
            Theme.radius.medium,
            Theme.radius.large,
            Theme.radius.xl,
            Theme.radius.pill,
        ]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
        #expect(scale.allSatisfy { $0 > 0 })
    }

    @Test("stroke widths and control sizes are positive")
    func strokeAndSize() {
        #expect(Theme.stroke.hairline > 0)
        #expect(Theme.stroke.thin >= Theme.stroke.hairline)
        #expect(Theme.stroke.medium >= Theme.stroke.thin)
        #expect(Theme.stroke.thick >= Theme.stroke.medium)

        // Apple's minimum hit target.
        #expect(Theme.size.control >= 44)
        #expect(Theme.size.icon > 0)
    }

    @Test("opacity tokens stay inside 0...1")
    func opacityRange() {
        for value in [Theme.opacity.disabled, Theme.opacity.secondary, Theme.opacity.primary] {
            #expect((0.0...1.0).contains(value))
        }
        #expect(Theme.opacity.disabled < Theme.opacity.secondary)
        #expect(Theme.opacity.secondary < Theme.opacity.primary)
    }

    /// Compiles only if `Theme` really is `nonisolated`: this test function is
    /// not main-actor isolated, and widget timeline providers read tokens from
    /// exactly this kind of context.
    @Test("tokens and the font seam are reachable from a nonisolated context")
    func nonisolatedReachability() {
        Theme.registerFonts()
        #expect(Theme.spacing.medium > 0)
        #expect(Theme.color.accent != Theme.color.background)
    }
}
