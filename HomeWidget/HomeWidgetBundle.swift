import SwiftUI
import WidgetKit

/// Exactly one `@main` per extension target. The Live Activity is a separate
/// target with its own bundle — merging them would put two `@main` types in
/// one module.
@main
@MainActor
struct HomeWidgetBundle: WidgetBundle {
    init() {
        // `WidgetBundle.init()` is the widget process's only launch hook, so it
        // is where the font seam has to be called.
        Theme.registerFonts()
    }

    var body: some Widget {
        HomeWidget()
    }
}
