import Combine
import SwiftUI
import CloudKit
import CoreLocation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension GridViewModel {
    func setupMessagingHandlers() {
        messagingService.newMessageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.ingestIncomingMessage(message)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .didIngestCloudKitMessage)
            .compactMap { $0.object as? Message }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.ingestIncomingMessage(message)
            }
            .store(in: &cancellables)
    }
    
    func setupLocationHandlers() {
        locationService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleLocationAuthorizationChange(status)
            }
            .store(in: &cancellables)

        locationService.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self, self.hasLocationAccess else { return }
                self.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    func setupProximityHandlers() {
        // Listen for all users updates (sorted by distance)
        proximityService.$activeNearbyProfiles
            .sink { [weak self] allProfiles in
                guard let self = self else { return }
                // All messaging is now encrypted by default
                self.updateGridWithAllProfiles(allProfiles)
            }
            .store(in: &cancellables)
    }
    
    func setupNavigationHandlers() {
        NotificationCenter.default.publisher(for: .didTapPushNotificationForChat)
            .compactMap { notification -> String? in
                notification.userInfo?["senderDeviceID"] as? String
            }
            .receive(on: DispatchQueue.main) // Ensure UI updates on main thread
            .sink { [weak self] senderDeviceID in
                print("GridViewModel: Received navigation request for chat with senderDeviceID: \(senderDeviceID)")
                guard let self = self else { return }
                
                if self.currentUserProfile != nil {
                    // Profile is available, proceed with navigation
                    self.selectChatPartner(partnerDeviceID: senderDeviceID) 
                } else {
                    // Profile not yet available, store for deferred navigation
                    print("GridViewModel: Current user profile not available. Deferring navigation for senderDeviceID: \(senderDeviceID)")
                    self.pendingChatNavigationDeviceID = senderDeviceID
                }
            }
            .store(in: &cancellables)
    }
    
    func setupPrivacyHandlers() {
        // Add any additional setup for privacy handlers if needed
        // This could include setting up notifications, handling privacy policy acceptance, etc.
        // For now, we'll just add a placeholder for these handlers.
        print("GridViewModel: Setting up privacy handlers...")
    }
    
    func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location,
              var profile = currentUserProfile else { return }
        
        print("DEBUG: Updating profile with location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Update profile with new location
        profile.updateLocation(location)
        self.currentUserProfile = profile
        
        print("DEBUG: Profile after location update - lat: \(profile.latitude ?? 0), lon: \(profile.longitude ?? 0)")
        
        updateUserActivityAndLocation(profile)
        syncFootstepTracking()
        refreshPlaceHeatmapIfNeeded()

        if shouldRefreshGridOnNextLocation {
            shouldRefreshGridOnNextLocation = false
            proximityService.fetchAllUsers(currentUserLocation: location)
        }

        print("Location updated and shared to iCloud: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationPermissionStatus = "Location permission not requested"
        case .denied, .restricted:
            locationPermissionStatus = "Location permission denied"
        case .authorizedWhenInUse:
            locationPermissionStatus = "Location permission granted"
        case .authorizedAlways:
            locationPermissionStatus = "Location permission granted (always)"
        @unknown default:
            locationPermissionStatus = "Unknown location permission status"
        }

        guard !locksGridToFixtures else { return }

        needsLocationOnboarding = LocationOnboardingLogic.shouldShowWelcome(status: status)

        if LocationOnboardingLogic.shouldShowNearbyPeople(status: status) {
            refreshGridAfterLocationAccessGranted()
            syncFootstepTracking()
        } else {
            updateGridWithAllProfiles([])
            locationService.stopWalkUpdates()
        }
    }
}
