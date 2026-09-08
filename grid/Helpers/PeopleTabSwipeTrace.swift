import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Swipe debugging for All ↔ Favorites. Filter the console for `[people-tab]`.
@MainActor
enum PeopleTabSwipeTrace {
    static func log(_ event: String) {
        AppLog.grid.debug("\(event, privacy: .public)")
        print("[people-tab] \(event)")
    }

    static func drag(_ phase: String, translation: CGSize, canSwipe: Bool, tab: GridPeopleTab) {
        log(
            "swiftui.\(phase) dx=\(Int(translation.width)) dy=\(Int(translation.height)) " +
            "canSwipe=\(canSwipe) tab=\(tab.rawValue)"
        )
    }
}
