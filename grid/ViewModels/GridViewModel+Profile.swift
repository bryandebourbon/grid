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
    func setCurrentUserProfile(_ profile: UserProfile) {
        self.currentUserProfile = profile
        updateUserActivityAndLocation(profile) // NEW: Use activity-based saving
        placeCurrentUserOnGrid()
        print("GridViewModel: Set current user profile for device ID \(profile.deviceID) (user: \(profile.userID))")

        bootstrapSession(for: profile)

        // Subscribe to message changes immediately
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        
        // Check for deferred navigation
        if let pendingDeviceID = pendingChatNavigationDeviceID {
            print("GridViewModel: Handling deferred navigation to chat with deviceID: \(pendingDeviceID)")
            selectChatPartner(partnerDeviceID: pendingDeviceID)
            pendingChatNavigationDeviceID = nil // Clear after handling
        }
    }
    
    // Enhanced: Fetch ALL messages for the current device (for all conversations)
    func fetchAllMessagesForCurrentDevice(deviceID: String) {
        print("GridViewModel: Fetching ALL messages for device \\(deviceID) to preload chats...")
        
        messagingService.fetchMessages(forDeviceID: deviceID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fetchedMessages): // MODIFIED: Changed fetchedCKRecords to fetchedMessages, expecting [Message]
                // Assuming messages from MessagingService are already correctly initialized with status
                // Apply read receipts to fetched messages
                var updatedMessages = fetchedMessages
                for index in updatedMessages.indices {
                    if self.readReceipts.contains(updatedMessages[index].id) {
                        updatedMessages[index].status = .sent
                    }
                }
                
                self.messages = updatedMessages.sorted(by: { $0.timestamp < $1.timestamp })
                
                print("GridViewModel: Preloaded \(self.messages.count) messages for instant chat access. Statuses set.")
                
                // Group messages by conversation for debugging
                let conversations = Dictionary(grouping: self.messages) { message in
                    let otherDeviceID = message.senderDeviceID == deviceID ? message.recipientDeviceID : message.senderDeviceID
                    return otherDeviceID
                }
                print("GridViewModel: Messages organized into \(conversations.count) conversations:")
                for (otherDeviceID, conversationMessages) in conversations {
                    let displayName = otherDeviceID == deviceID ? "My Notes" : "Device \(String(otherDeviceID.prefix(8)))"
                    print("  - \(displayName): \(conversationMessages.count) messages")
                }
                
            case .failure(let error):
                print("GridViewModel: Error preloading messages for device \\(deviceID): \\(error.localizedDescription)")
                // Don't fail the login process, just log the error
            }
        }
    }
    
    // NEW: Get messages for a specific conversation (already loaded)
    func getMessagesForConversation(with deviceID: String) -> [Message] {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return [] }
        return MessageConversationLogic.messages(
            inConversationWith: deviceID,
            currentDeviceID: currentDeviceID,
            from: messages
        )
    }

    func getConversationList() -> [(deviceID: String, displayName: String, lastMessage: Message?, messageCount: Int)] {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return [] }
        return MessageConversationLogic.conversationList(
            currentDeviceID: currentDeviceID,
            messages: messages,
            displayNameLookup: { [weak self] otherDeviceID in
                guard let self = self else {
                    return ProfileDisplayNameLogic.chatTitle(
                        recipientDeviceID: otherDeviceID,
                        currentDeviceID: nil,
                        gridNodes: []
                    )
                }
                return self.displayName(forDeviceID: otherDeviceID)
            }
        )
        .map { ($0.deviceID, $0.displayName, $0.lastMessage, $0.messageCount) }
    }
    
    func updateCurrentProfileImage(newPhotoData: Data?) {
        guard currentUserProfile != nil else {
            print("Cannot update profile image, currentUserProfile is nil.")
            return
        }
        guard let photoData = newPhotoData else {
            currentUserProfile?.profileImage = nil
            print("Profile image removed.")
            persistAndUpdateProfileAndGrid()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try photoData.write(to: tempFileURL)
            let photoAsset = CKAsset(fileURL: tempFileURL)
            currentUserProfile?.profileImage = photoAsset
            print("Profile image updated. Temp file: \(tempFileURL.path)")
            persistAndUpdateProfileAndGrid()
        } catch {
            print("Error creating CKAsset for profile image: \\(error.localizedDescription)")
             try? FileManager.default.removeItem(at: tempFileURL)
        }
    }
    
    func persistAndUpdateProfileAndGrid(completion: ((Bool) -> Void)? = nil) {
        guard let profile = currentUserProfile else { 
            completion?(false)
            return 
        }
        // Only save if location is valid (not 0.0, 0.0)
        if let lat = profile.latitude, let lon = profile.longitude, lat != 0.0, lon != 0.0 {
            print("[CloudKit Save] Valid location detected: lat=\(lat), lon=\(lon). Proceeding with save.")
            print("Profile data changed. Updating user activity and CloudKit.")
            
            // Using proximityService.updateUserActivity which saves the profile to CloudKit
            proximityService.updateUserActivity(profile) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success(let savedProfile):
                        self.currentUserProfile = savedProfile // Update with the potentially modified profile from server
                        self.placeCurrentUserOnGrid() // Update local grid display
                        print("User profile successfully updated in CloudKit and local grid refreshed.")
                        completion?(true)
                    case .failure(let error):
                        print("Error updating user profile in CloudKit: \(error.localizedDescription)")
                        
                        // Check if this is a CloudKit daemon connection error
                        if self.isCloudKitDaemonConnectionError(error) {
                            print("⚠️ CloudKit daemon connection error detected. This is common on new devices or when iCloud is syncing.")
                            
                            // Check CloudKit availability before retrying
                            self.checkCloudKitAvailability { isAvailable, errorMessage in
                                if isAvailable {
                                    // If CloudKit is available, retry the operation after a short delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        print("🔄 Retrying profile update after CloudKit daemon connection error...")
                                        self.persistAndUpdateProfileAndGrid(completion: completion)
                                    }
                                } else {
                                    print("❌ CloudKit is not available: \(errorMessage ?? "Unknown error")")
                                    completion?(false)
                                }
                            }
                        } else {
                            completion?(false)
                        }
                    }
                }
            }
        } else {
            print("[CloudKit Save] Location not available or invalid (lat=\(profile.latitude ?? -1), lon=\(profile.longitude ?? -1)). Skipping CloudKit save. Will retry when location is updated.")
            completion?(false)
        }
    }

    func isCloudKitDaemonConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 4099 {
            return true
        }
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("cloudd") ||
            errorDescription.contains("daemon") ||
            (errorDescription.contains("connection") && errorDescription.contains("cloudkit"))
    }
}
