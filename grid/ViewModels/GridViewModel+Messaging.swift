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
    // MARK: - Messaging Methods

    func selectChatPartner(partnerDeviceID: String) {
        self.currentChatRecipientDeviceID = partnerDeviceID
        print("Selected chat partner device: \(partnerDeviceID)")
    }

    // Simplified sendMessage - can message anyone you can see
    func sendMessage(text: String, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else { return }
        guard let recipientProfile = recipientProfile(for: recipientDeviceID, sender: senderProfile) else { return }

        let optimisticMessage = EncryptedMessageBuilder.buildTextMessage(
            text: text,
            sender: senderProfile,
            recipientDeviceID: recipientDeviceID,
            recipient: recipientProfile,
            encryptionProfiles: encryptionProfiles
        )
        let temporaryID = optimisticMessage.id
        messages.append(optimisticMessage)
        messages.sort { $0.timestamp < $1.timestamp }

        messagingService.sendMessage(optimisticMessage) { [weak self] result in
            guard let self else { return }
            OptimisticMessageSync.applySendResult(messages: &self.messages, temporaryID: temporaryID, result: result)
        }
    }

    func recipientProfile(for recipientDeviceID: String, sender: UserProfile) -> UserProfile? {
        if recipientDeviceID == sender.deviceID { return sender }
        return findNode(forDeviceID: recipientDeviceID)?.userProfile
    }

    // NEW: Auto-refresh when location is obtained or app state changes
    func autoRefreshGrid(with location: CLLocation? = nil) {
        print("Auto-refreshing grid with current location...")
        let locationToUse = location ?? locationService.currentLocation
        proximityService.fetchAllUsers(currentUserLocation: locationToUse)
    }

    // NEW: Call this when grid appears (from GridView)
    func handleGridAppeared() {
        print("Grid appeared - getting current location and refreshing...")
        
        // Ensure location services are active
        locationService.requestLocationPermission()
        
        // Request location once for this grid refresh
        locationService.requestLocationOnce()
        
        // Wait a moment for location to be available, then refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            if let currentLocation = self.locationService.currentLocation {
                // Manually trigger location update and grid refresh
                self.handleLocationUpdate(currentLocation)
            } else {
                // No location yet, just refresh with existing data
                print("No location available yet, refreshing with existing data")
                self.autoRefreshGrid()
            }
        }
    }

    func sendImageMessage(imageData: Data, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else { return }
        guard let recipientProfile = recipientProfile(for: recipientDeviceID, sender: senderProfile) else { return }

        let built = EncryptedMessageBuilder.buildImageMessage(
            imageData: imageData,
            sender: senderProfile,
            recipientDeviceID: recipientDeviceID,
            recipient: recipientProfile,
            encryptionProfiles: encryptionProfiles
        )
        let temporaryID = built.message.id
        messages.append(built.message)
        messages.sort { $0.timestamp < $1.timestamp }

        messagingService.sendMessage(built.message) { [weak self] result in
            guard let self else {
                if let url = built.cleanupURL { try? FileManager.default.removeItem(at: url) }
                return
            }
            OptimisticMessageSync.applySendResult(messages: &self.messages, temporaryID: temporaryID, result: result)
            if let url = built.cleanupURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    func performFullAccountDeletion(completion: @escaping (Error?) -> Void) {
        guard let userIDToDelete = currentUserProfile?.userID else {
            print("GridViewModel: UserID not found, cannot perform account deletion.")
            completion(NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found."]))
            return
        }

        print("GridViewModel: Starting full account deletion for userID: \(userIDToDelete)")
        accountDeletionService.deleteAllRecords(
            forUserID: userIDToDelete,
            deviceID: currentUserProfile?.deviceID ?? ""
        ) { error in
            if error == nil {
                print("GridViewModel: Successfully deleted all user-owned records for userID: \(userIDToDelete)")
            }
            completion(error)
        }
    }

    func updateUserProfileBio(bio: String, completion: @escaping (Bool) -> Void) {
        guard var userProfile = self.currentUserProfile else {
            print("No current user profile to update bio for.")
            completion(false)
            return
        }

        userProfile.bio = bio

        // Optimistically update local profile
        self.currentUserProfile?.bio = bio
        
        // Save to CloudKit using proximityService
        proximityService.updateUserActivity(userProfile) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedProfile):
                    // Update local profile with the one returned from save (might have updated recordID etc.)
                    self?.currentUserProfile = savedProfile
                    self?.objectWillChange.send() // Notify views
                    print("User bio updated and saved successfully.")
                    completion(true)
                case .failure(let error):
                    print("Error saving user profile bio to CloudKit: \\(error.localizedDescription)")
                    // Revert optimistic update on failure
                    self?.currentUserProfile?.bio = userProfile.bio // Restore previous value
                    completion(false)
                }
            }
        }
    }
    
    func updateUserProfileInterests(interests: [Interest], completion: @escaping (Bool) -> Void) {
        guard var userProfile = self.currentUserProfile else {
            print("No current user profile to update interests for.")
            completion(false)
            return
        }

        let oldInterests = userProfile.interests
        userProfile.interests = interests

        // Optimistically update local profile
        self.currentUserProfile?.interests = interests
        
        // Save to CloudKit using proximityService
        proximityService.updateUserActivity(userProfile) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedProfile):
                    // Update local profile with the one returned from save
                    self?.currentUserProfile = savedProfile
                    self?.objectWillChange.send() // Notify views
                    print("User interests updated and saved successfully. New interests: \(interests.map { $0.rawValue })")
                    
                    // Update the proximityService.activeNearbyProfiles array with the updated profile
                    if let proximityService = self?.proximityService {
                        // Find and update the current user's profile in the activeNearbyProfiles array
                        if let index = proximityService.activeNearbyProfiles.firstIndex(where: { $0.deviceID == savedProfile.deviceID }) {
                            proximityService.activeNearbyProfiles[index] = savedProfile
                        }
                        
                        // Now refresh the grid with the updated profiles
                        self?.updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
                    }
                    
                    completion(true)
                case .failure(let error):
                    print("Error saving user profile interests to CloudKit: \(error.localizedDescription)")
                    // Revert optimistic update on failure
                    self?.currentUserProfile?.interests = oldInterests
                    completion(false)
                }
            }
        }
    }

    // NEW: Check CloudKit availability before attempting operations
    func checkCloudKitAvailability(completion: @escaping (Bool, String?) -> Void) {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    completion(true, nil)
                case .noAccount:
                    completion(false, "No iCloud account found. Please sign in to iCloud in Settings.")
                case .restricted:
                    completion(false, "iCloud access is restricted on this device.")
                case .couldNotDetermine:
                    completion(false, "Could not determine iCloud status. Please try again.")
                case .temporarilyUnavailable:
                    completion(false, "iCloud is temporarily unavailable. Please try again later.")
                @unknown default:
                    completion(false, "Unknown iCloud status.")
                }
            }
        }
    }
}
