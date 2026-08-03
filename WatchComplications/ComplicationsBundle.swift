import SwiftUI
import WidgetKit

/// watchOS complications are WidgetKit accessory widgets — ClockKit is dead
/// from watchOS 10 onward. Two kinds so a user can place the running timer and
/// the day's count independently.
@main
@MainActor
struct ComplicationsBundle: WidgetBundle {
    init() {
        Theme.registerFonts()
    }

    var body: some Widget {
        SessionComplication()
        TodayCountComplication()
    }
}
