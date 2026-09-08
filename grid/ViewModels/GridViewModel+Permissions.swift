import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension GridViewModel {
    func refreshGridAfterLocationAccessGranted() {
        shouldRefreshGridOnNextLocation = true
        locationService.requestLocationOnce()
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        let location = locationService.currentLocation ?? currentUserProfile?.location
        proximityService.fetchAllUsers(currentUserLocation: location)
    }

    func enableLocationFromOnboarding() {
        switch LocationOnboardingLogic.enableAction(for: locationService.authorizationStatus) {
        case .requestPermission:
            locationService.requestLocationPermission()
        case .openSettings:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        case .none:
            break
        }
    }

    func considerNotificationPermission(for event: NotificationPermissionLogic.ChatEvent) {
        guard !GridUITestHarness.isActive, !locksGridToFixtures else { return }
        let already = UserDefaults.standard.bool(forKey: NotificationPermissionLogic.requestedDefaultsKey)
        guard NotificationPermissionLogic.shouldRequest(alreadyRequested: already, event: event) else { return }
        NotificationPermissionService.requestAfterFirstChatIfNeeded()
    }
}
