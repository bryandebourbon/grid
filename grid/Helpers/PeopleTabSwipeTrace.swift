import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// All ↔ Favorites swipe hook. Left silent so it does not add input latency.
@MainActor
enum PeopleTabSwipeTrace {
    static func log(_ event: String) {}

    static func drag(_ phase: String, translation: CGSize, canSwipe: Bool, tab: GridPeopleTab) {}
}
