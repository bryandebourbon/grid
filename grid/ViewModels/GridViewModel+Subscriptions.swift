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
            .sink { [weak self] newMessageFromSubscription in
                guard let self = self, let currentDeviceID = self.currentUserProfile?.deviceID else { return }

                // Check if the message is relevant to the current user
                guard newMessageFromSubscription.senderDeviceID == currentDeviceID || newMessageFromSubscription.recipientDeviceID == currentDeviceID else {
                    // This message isn't for or from the current user, ignore.
                    // This check might be redundant if MessagingService already filters, but good for safety.
                    return
                }
                
                // Determine if this is a confirmation of an optimistically sent message
                // or a brand new message from the other party.
                // The newMessageFromSubscription already has its ID set to the CKRecord.ID.recordName.
                
                if let index = self.messages.firstIndex(where: { $0.id == newMessageFromSubscription.id }) {
                    // This is a confirmation of an existing message (likely an optimistic one).
                    // Update its status and any server-authoritative fields.
                    // The newMessageFromSubscription is already initialized with status .sent or .received
                    // based on sender, so we can directly use its values.
                    var updatedMessage = newMessageFromSubscription
                    // Check if we have a read receipt for this message
                    if self.readReceipts.contains(newMessageFromSubscription.id) {
                        updatedMessage.status = .sent // Mark as read
                    }
                    self.messages[index] = updatedMessage
                    print("GridViewModel: Updated existing message (ID: \(newMessageFromSubscription.id)) from subscription with server data. Status: \(updatedMessage.status)")
                } else {
                    // This is a genuinely new message (e.g., from the other user, or one not optimistically added).
                    var newMessage = newMessageFromSubscription
                    // Check if we have a read receipt for this message
                    if self.readReceipts.contains(newMessage.id) {
                        newMessage.status = .sent
                    }
                    self.messages.append(newMessage)
                    print("GridViewModel: Added new message (ID: \(newMessage.id)) from subscription. Status: \(newMessage.status)")
                    
                    // Check if this message is from someone not currently in the grid
                    if newMessage.senderDeviceID != currentDeviceID {
                        self.checkAndAddNewSenderToGrid(senderDeviceID: newMessage.senderDeviceID,
                                                         senderUserID: newMessage.senderUserID)
                    }
                    
                    // Trigger UI update if this is an encrypted message
                    if newMessage.isEncrypted {
                        self.objectWillChange.send()
                    }
                }
                
                self.messages.sort(by: { $0.timestamp < $1.timestamp })
                // Consider calling objectWillChange.send() if direct array manipulation doesn't always trigger UI updates,
                // though @Published should handle appends and direct element replacements.
            }
            .store(in: &cancellables)
    }
    
    func setupLocationHandlers() {
        // Listen for location updates
        // REMOVED: We don't want automatic grid refresh on every location update
        // locationService.$currentLocation
        //     .sink { [weak self] location in
        //         self?.handleLocationUpdate(location)
        //     }
        //     .store(in: &cancellables)
        
        // Listen for authorization status changes
        locationService.$authorizationStatus
            .sink { [weak self] status in
                self?.handleLocationAuthorizationChange(status)
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
        
        // IMMEDIATELY share location to iCloud when we get it
        updateUserActivityAndLocation(profile)
        
        // Auto-refresh to get all users sorted by distance
        autoRefreshGrid(with: location)
        
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
    }
}
