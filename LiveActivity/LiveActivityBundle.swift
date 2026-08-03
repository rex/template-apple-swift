import SwiftUI
import WidgetKit

/// A separate extension target from `HomeWidget`, so it carries its own
/// `@main`. The iOS 18 floor is well above `ActivityConfiguration`'s 16.1
/// availability, so no `@available` guard is needed anywhere in this target.
@main
@MainActor
struct LiveActivityBundle: WidgetBundle {
    init() {
        Theme.registerFonts()
    }

    var body: some Widget {
        SessionLiveActivity()
    }
}
