import Foundation
import os

/// Privacy helper for Grid.
///
/// Grid does **not** perform cross-app tracking and does **not** read the IDFA,
/// so there is no App Tracking Transparency prompt (and no
/// `NSUserTrackingUsageDescription` in Info.plist). `trackEvent` is a local,
/// no-op analytics hook — kept so existing call sites remain valid — that only
/// logs in debug builds. Wire it to a real, privacy-compliant analytics
/// provider here if one is ever added, and update the App Privacy labels
/// accordingly.
@MainActor
class PrivacyService: ObservableObject {
    private let log = Logger(subsystem: "com.bryandebourbon.grid", category: "Privacy")

    func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        log.debug("analytics event (not transmitted): \(eventName, privacy: .public)")
        #endif
    }
}
