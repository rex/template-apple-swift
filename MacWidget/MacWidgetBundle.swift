import SwiftUI
import WidgetKit

@main
@MainActor
struct MacWidgetBundle: WidgetBundle {
    init() {
        Theme.registerFonts()
    }

    var body: some Widget {
        MacWidget()
    }
}
