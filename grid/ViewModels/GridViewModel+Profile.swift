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
        loadCustomGroups()
        loadInterestPages()

        // Subscribe to message changes immediately
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        
        // Check for deferred navigation
        if let pendingDeviceID = pendingChatNavigationDeviceID {
            print("GridViewModel: Handling deferred navigation to chat with deviceID: \(pendingDeviceID)")
            selectChatPartner(partnerDeviceID: pendingDeviceID)
            pendingChatNavigationDeviceID = nil // Clear after handling
        }
    }
    
    func loadPersistedInbox() {
        let stored = MessageInboxStore.load()
        guard stored.isEmpty == false else { return }
        messages = MessageInboxLogic.merge(local: messages, incoming: stored)
        mergeLocalLLMMessages()
        warmDecryptionCache()
    }

    func applyIncomingMessages(_ incoming: [Message]) {
        guard incoming.isEmpty == false else {
            mergeLocalLLMMessages()
            return
        }
        var updated = incoming
        for index in updated.indices where readReceipts.contains(updated[index].id) {
            updated[index].status = .sent
        }
        guard MessageInboxLogic.hasNewOrChanged(local: messages, incoming: updated) else {
            mergeLocalLLMMessages()
            return
        }
        messages = MessageInboxLogic.merge(local: messages, incoming: updated)
        mergeLocalLLMMessages()
        MessageInboxStore.save(messages)
        warmDecryptionCache()
        objectWillChange.send()
    }

    func ingestIncomingMessage(_ message: Message) {
        let currentDeviceID = currentUserProfile?.deviceID
        guard currentDeviceID == nil
                || message.senderDeviceID == currentDeviceID
                || message.recipientDeviceID == currentDeviceID else {
            MessageDeliveryTrace.log("ingest.skip id=\(message.id.prefix(8)) not for this device")
            return
        }
        MessageDeliveryTrace.log("ingest id=\(message.id.prefix(8)) from=\(message.senderDeviceID.prefix(8))")
        applyIncomingMessages([message])
        if let currentDeviceID, message.senderDeviceID != currentDeviceID {
            checkAndAddNewSenderToGrid(
                senderDeviceID: message.senderDeviceID,
                senderUserID: message.senderUserID
            )
            if message.timestamp > sessionStartedAt.addingTimeInterval(-5) {
                considerNotificationPermission(for: .received(
                    fromCurrentUser: false,
                    isLLM: LocalLLMIdentity.isLLM(message.senderDeviceID)
                ))
            }
        }
    }

    func refreshIncomingMessages(includeFullHistory: Bool = false, completion: (() -> Void)? = nil) {
        guard let deviceID = currentUserProfile?.deviceID else {
            completion?()
            return
        }
        messagingService.fetchPendingRecords(currentDeviceID: deviceID) { [weak self] pending in
            guard let self else {
                completion?()
                return
            }
            self.applyIncomingMessages(pending)
            let since = includeFullHistory
                ? nil
                : MessageInboxLogic.querySince(newestLocal: self.messages.map(\.timestamp).max())
            self.fetchAllMessagesForCurrentDevice(deviceID: deviceID, since: since, completion: completion)
        }
    }

    func fetchAllMessagesForCurrentDevice(deviceID: String, since: Date? = nil, completion: (() -> Void)? = nil) {
        guard !isFetchingAllMessages else {
            completion?()
            return
        }
        isFetchingAllMessages = true
        messagingService.fetchMessages(forDeviceID: deviceID, since: since) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            self.isFetchingAllMessages = false
            switch result {
            case .success(let fetchedMessages):
                self.applyIncomingMessages(fetchedMessages)
            case .failure:
                self.mergeLocalLLMMessages()
            }
            completion?()
        }
    }

    func getMessagesForConversation(with deviceID: String) -> [Message] {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return [] }
        let thread = MessageConversationLogic.messages(
            inConversationWith: deviceID,
            currentDeviceID: currentDeviceID,
            from: messages
        )
        return thread.filter(messageIsReadable)
    }

    func getConversationList() -> [MessageConversationLogic.ConversationSummary] {
        getMessagesHome().conversations
    }

    func getMessagesHome() -> (
        pinned: [MessageConversationLogic.PinnedPerson],
        conversations: [MessageConversationLogic.ConversationSummary]
    ) {
        guard let current = currentUserProfile else { return ([], []) }
        return MessageConversationLogic.messagesHome(
            currentDeviceID: current.deviceID,
            currentUserID: current.userID,
            messages: readableMessages(),
            readReceipts: readReceipts,
            starredUserIDs: starredUsers,
            profiles: knownProfiles(),
            displayNameLookup: { [weak self] otherDeviceID in
                guard let self else {
                    return ProfileDisplayNameLogic.chatTitle(
                        recipientDeviceID: otherDeviceID,
                        currentDeviceID: nil,
                        gridNodes: []
                    )
                }
                return self.displayName(forDeviceID: otherDeviceID)
            },
            filter: MessageConversationLogic.HomeFilter(
                visibleUserIDs: visibleUserIDs(for: peopleTab),
                pinnedUserIDs: pinnedUserIDs(for: peopleTab),
                blockedUserIDs: blockedUsers.union(usersWhoBlockedMe),
                hiddenAt: hiddenConversations
            )
        )
    }

    func knownProfiles() -> [UserProfile] {
        var seen = Set<String>()
        var result: [UserProfile] = []
        if let currentUserProfile {
            result.append(currentUserProfile)
            seen.insert(currentUserProfile.deviceID)
        }
        let grids = [allGridNodes, favoriteGridNodes, gridNodes]
            + Array(customGroupNodes.values)
            + Array(interestGridNodes.values)
        for grid in grids {
            for node in grid.flatMap({ $0 }) {
                guard let profile = node.userProfile, seen.insert(profile.deviceID).inserted else { continue }
                result.append(profile)
            }
        }
        return result
    }

    func profile(forDeviceID deviceID: String) -> UserProfile? {
        if deviceID == currentUserProfile?.deviceID {
            return currentUserProfile
        }
        if LocalLLMIdentity.isLLM(deviceID) {
            return LocalLLMIdentity.profile
        }
        let grids = [allGridNodes, favoriteGridNodes, gridNodes]
            + Array(customGroupNodes.values)
            + Array(interestGridNodes.values)
        for grid in grids {
            if let profile = ProfileDisplayNameLogic.profile(forDeviceID: deviceID, in: grid) {
                return profile
            }
        }
        return nil
    }

    func refreshCurrentUserPhotoOnGrid() {
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
    }

    func mergingSavedProfile(_ saved: UserProfile) -> UserProfile {
        guard let local = currentUserProfile else { return saved }
        var merged = saved
        if ProfileImageRefreshLogic.shouldKeepLocalPhoto(
            localURL: local.profileImage?.fileURL,
            savedURL: saved.profileImage?.fileURL
        ) {
            merged.profileImage = local.profileImage
        }
        if merged.deviceName.isEmpty {
            merged.deviceName = local.deviceName
        }
        return merged
    }
    
    func updateCurrentProfileImage(newPhotoData: Data?) {
        guard var profile = currentUserProfile else {
            print("Cannot update profile image, currentUserProfile is nil.")
            return
        }
        guard let photoData = newPhotoData else {
            profile.profileImage = nil
            currentUserProfile = profile
            print("Profile image removed.")
            refreshCurrentUserPhotoOnGrid()
            persistAndUpdateProfileAndGrid()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try photoData.write(to: tempFileURL)
            profile.profileImage = CKAsset(fileURL: tempFileURL)
            currentUserProfile = profile
            print("Profile image updated. Temp file: \(tempFileURL.path)")
            refreshCurrentUserPhotoOnGrid()
            persistAndUpdateProfileAndGrid()
        } catch {
            print("Error creating CKAsset for profile image: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
        }
    }
    
    func updatePersonName(_ name: String, completion: ((Bool) -> Void)? = nil) {
        guard let trimmed = ProfileDisplayNameLogic.normalizedPersonName(name) else {
            completion?(false)
            return
        }
        guard var profile = currentUserProfile else {
            completion?(false)
            return
        }
        profile.deviceName = trimmed
        currentUserProfile = profile
        SenderNameCache.store(trimmed, for: profile.deviceID)
        ProfileDisplayNameLogic.clearPendingPersonName()
        persistAndUpdateProfileAndGrid(completion: completion)
    }

    func persistAndUpdateProfileAndGrid(completion: ((Bool) -> Void)? = nil) {
        guard let profile = currentUserProfile else { 
            completion?(false)
            return 
        }
        print("[CloudKit Save] Updating profile. lat=\(profile.latitude ?? -1), lon=\(profile.longitude ?? -1)")
        proximityService.updateUserActivity(profile) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let savedProfile):
                    self.currentUserProfile = self.mergingSavedProfile(savedProfile)
                    self.refreshCurrentUserPhotoOnGrid()
                    print("User profile successfully updated in CloudKit and local grid refreshed.")
                    completion?(true)
                case .failure(let error):
                    print("Error updating user profile in CloudKit: \(error.localizedDescription)")

                    if self.isCloudKitDaemonConnectionError(error) {
                        self.checkCloudKitAvailability { isAvailable, errorMessage in
                            if isAvailable {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    print("Retrying profile update after CloudKit daemon connection error...")
                                    self.persistAndUpdateProfileAndGrid(completion: completion)
                                }
                            } else {
                                print("CloudKit is not available: \(errorMessage ?? "Unknown error")")
                                completion?(false)
                            }
                        }
                    } else {
                        completion?(false)
                    }
                }
            }
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
