import CoreLocation
import Foundation

/// First-launch grid copy and when to ask for location.
enum LocationOnboardingLogic {
    static let title = "Welcome to Commons"
    static let subtitle = "A common-interest GPS chat service"
    static let profileStep = "Add content to your profile in the drawer"
    static let locationStep = "Enable location to see others on the grid"

    enum EnableAction: Equatable {
        case requestPermission
        case openSettings
        case none
    }

    static func shouldShowWelcome(status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return false
        default:
            return true
        }
    }

    static func shouldShowNearbyPeople(status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func enableAction(for status: CLAuthorizationStatus) -> EnableAction {
        switch status {
        case .notDetermined:
            return .requestPermission
        case .denied, .restricted:
            return .openSettings
        default:
            return .none
        }
    }

    static func enableButtonTitle(for status: CLAuthorizationStatus) -> String {
        switch enableAction(for: status) {
        case .openSettings:
            return "Open Settings"
        case .requestPermission, .none:
            return "Enable Location"
        }
    }
}
