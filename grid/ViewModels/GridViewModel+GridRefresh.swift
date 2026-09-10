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
    // MARK: - Grid Refresh Methods
    
    /// Pull-to-refresh: reload nearby people and every conversation, then drop the spinner.
    func refreshPeopleAndMessages() async {
        guard !locksGridToFixtures else { return }
        locationService.requestLocationOnce()
        recordInterestFootsteps(for: currentUserProfile)
        refreshInterestHeatmap()
        async let people: Void = refreshNearbyPeople()
        async let messages: Void = refreshAllConversations()
        async let catalog: Void = refreshSharedInterestCatalogAsync()
        _ = await (people, messages, catalog)
    }

    private func refreshSharedInterestCatalogAsync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refreshSharedInterestCatalog {
                continuation.resume()
            }
        }
    }

    private func refreshNearbyPeople() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard hasLocationAccess else {
                continuation.resume()
                return
            }
            let location = locationService.currentLocation ?? currentUserProfile?.location
            proximityService.fetchAllUsers(currentUserLocation: location) {
                continuation.resume()
            }
        }
    }

    private func refreshAllConversations() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let deviceID = currentUserProfile?.deviceID else {
                continuation.resume()
                return
            }
            refreshIncomingMessages {
                continuation.resume()
            }
        }
    }

    // Simplified refresh - upload my location, get all users sorted by distance
    func refreshPublicGrid() {
        print("GridViewModel: Starting simple refresh - upload my location, get all users sorted by distance")
        if locksGridToFixtures { return }
        guard hasLocationAccess else { return }

        guard let profile = currentUserProfile else {
            print("No current user profile for refresh")
            return
        }
        
        // Request fresh location once
        locationService.requestLocationOnce()
        
        // Wait a moment for location update, then proceed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Get fresh location from location service and update
            if let currentLocation = self.locationService.currentLocation {
                // Manually trigger location update and grid refresh
                self.handleLocationUpdate(currentLocation)
            } else {
                // No current location available, just refresh with existing profile location
                print("No current location available, refreshing with last known position")
                
                // Upload current status and get all users
                self.proximityService.updateUserActivity(profile) { result in
                    switch result {
                    case .success(let updatedProfile):
                        print("Successfully uploaded my status to CloudKit")
                        self.currentUserProfile = self.mergingSavedProfile(updatedProfile)
                        
                        // Get all users sorted by distance
                        self.proximityService.fetchAllUsers(currentUserLocation: updatedProfile.location)
                        
                    case .failure(let error):
                        print("Error uploading my status: \\(error.localizedDescription)")
                        // Still try to fetch others even if upload failed
                        self.proximityService.fetchAllUsers(currentUserLocation: profile.location)
                    }
                }
            }
        }
    }
    
    // Enhanced: Handle app lifecycle events with auto-refresh
    func handleAppDidBecomeActive() {
        if locksGridToFixtures { return }
        guard var profile = currentUserProfile else { return }
        profile.markAsActive()
        self.currentUserProfile = profile
        
        print("App became active - updating activity status only")
        
        // REMOVED: Don't restart location updates
        // locationService.requestLocationPermission()
        
        // Update activity status in CloudKit (without refreshing the grid)
        updateUserActivityAndLocation(profile)
        syncFootstepTracking()

        refreshIncomingMessages(includeFullHistory: false)
    }
    
    func handleAppWillResignActive() {
        guard let profile = currentUserProfile else { return }
        
        // Mark user as inactive in CloudKit
        proximityService.markUserAsInactive(deviceID: profile.deviceID) { result in
            switch result {
            case .success():
                print("Successfully marked user as inactive")
            case .failure(let error):
                print("Error marking user as inactive: \\(error.localizedDescription)")
            }
        }
        
        // Stop location updates to save battery
        locationService.stopLocationUpdates()
        
        print("App will resign active - marked user as inactive and stopped location updates")
    }
    
    // NEW: Get unread message count from a specific device
    func getUnreadMessageCount(from deviceID: String) -> Int {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return 0 }
        return MessageReadLogic.unreadCount(
            from: deviceID,
            currentDeviceID: currentDeviceID,
            messages: readableMessages(),
            readReceipts: readReceipts
        )
    }

    func incomingUnreadCount(excludingDeviceID: String? = nil) -> Int {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return 0 }
        return MessageReadLogic.incomingUnreadCount(
            currentDeviceID: currentDeviceID,
            messages: readableMessages(),
            readReceipts: readReceipts,
            excludingSenderDeviceID: excludingDeviceID
        )
    }
    
    // NEW: Mark messages as read when opening a chat
    func markMessagesAsRead(from deviceID: String) {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return }
        if LocalLLMIdentity.isLLM(deviceID) {
            for index in messages.indices where
                messages[index].senderDeviceID == deviceID &&
                messages[index].recipientDeviceID == currentDeviceID {
                messages[index].status = .sent
                readReceipts.insert(messages[index].id)
            }
            ReadReceiptStore.save(readReceipts)
            objectWillChange.send()
            return
        }
        
        var newReadReceipts: [ReadReceipt] = []
        
        // Find all unread messages from this device
        for index in messages.indices {
            if messages[index].senderDeviceID == deviceID && 
               messages[index].recipientDeviceID == currentDeviceID && 
               !readReceipts.contains(messages[index].id) {
                // Mark as read locally
                messages[index].status = .sent // Update visual status
                readReceipts.insert(messages[index].id)
                
                // Create a read receipt
                let receipt = ReadReceipt(deviceID: currentDeviceID, messageID: messages[index].id)
                newReadReceipts.append(receipt)
            }
        }
        
        objectWillChange.send()
        ReadReceiptStore.save(readReceipts)
        
        // Persist the new receipts
        readReceiptService.saveReceipts(newReadReceipts)
    }
    
    // Load star/block relationships from CloudKit (both outgoing and incoming blocks)
    func loadStarBlockRelationships(forUserID userID: String, completion: @escaping () -> Void = {}) {
        relationshipService.loadRelationships(forUserID: userID) { [weak self] data in
            guard let self = self else { return }
            self.starredUsers = data.starred
            self.blockedUsers = data.blocked
            self.usersWhoBlockedMe = data.blockedBy
            print("GridViewModel: loaded \(self.starredUsers.count) starred, \(self.blockedUsers.count) blocked, \(self.usersWhoBlockedMe.count) blocked-by")

            // Refresh the grid to apply blocking filters
            self.updateGridWithAllProfiles(self.proximityService.activeNearbyProfiles)
            self.objectWillChange.send()
            completion()
        }
    }
    
    // Load read receipts from CloudKit
    func loadReadReceipts(forDeviceID deviceID: String, completion: @escaping () -> Void = {}) {
        readReceiptService.loadReceipts(forDeviceID: deviceID) { [weak self] messageIDs in
            guard let self = self else {
                completion()
                return
            }
            self.readReceipts.formUnion(messageIDs)
            ReadReceiptStore.save(self.readReceipts)
            print("GridViewModel: loaded \(self.readReceipts.count) read receipts")

            // Update message statuses based on read receipts
            for index in self.messages.indices {
                if self.readReceipts.contains(self.messages[index].id) &&
                   self.messages[index].recipientDeviceID == deviceID {
                    self.messages[index].status = .sent
                }
            }

            self.objectWillChange.send()
            completion()
        }
    }
    
    // NEW: Star/unstar a user
    func toggleStar(for deviceID: String) {
        guard let currentUserID = currentUserProfile?.userID,
              let targetUserID = getUserID(forDeviceID: deviceID) else { return }

        guard let next = FavoritePinLogic.toggling(targetUserID, in: starredUsers) else {
            presentUserFacingAlert(FavoritePinLogic.pinLimitMessage)
            return
        }

        let wasStarred = starredUsers.contains(targetUserID)
        starredUsers = next

        if wasStarred {
            relationshipService.deleteRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .star) { success in
                print("Star deletion \(success ? "successful" : "failed") for user: \(targetUserID)")
            }
        } else {
            relationshipService.saveRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .star)
        }

        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        objectWillChange.send()
    }
    
    func toggleBlock(for deviceID: String) {
        guard let currentUserID = currentUserProfile?.userID,
              let targetUserID = getUserID(forDeviceID: deviceID) else { return }

        if blockedUsers.contains(targetUserID) {
            blockedUsers.remove(targetUserID)
            relationshipService.deleteRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .block) { [weak self] success in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if !success {
                        self.blockedUsers.insert(targetUserID)
                    }
                    self.refreshGridWithCurrentState()
                }
            }
        } else {
            blockedUsers.insert(targetUserID)
            relationshipService.saveRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .block)
            updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        }

        objectWillChange.send()
    }
    
    // Helper to get userID from deviceID
    func getUserID(forDeviceID deviceID: String) -> String? {
        // Check current user first
        if let currentProfile = currentUserProfile, currentProfile.deviceID == deviceID {
            return currentProfile.userID
        }
        
        for grid in [allGridNodes, favoriteGridNodes, gridNodes]
            + Array(customGroupNodes.values)
            + Array(interestGridNodes.values) {
            for row in grid {
                for node in row {
                    if let profile = node.userProfile, profile.deviceID == deviceID {
                        return profile.userID
                    }
                }
            }
        }

        if let message = messages.last(where: { $0.senderDeviceID == deviceID }) {
            return message.senderUserID
        }
        if let message = messages.last(where: { $0.recipientDeviceID == deviceID }) {
            return message.recipientUserID
        }

        return nil
    }
    
    // Check if a user is starred (by deviceID)
    func isStarred(_ deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return starredUsers.contains(userID)
            || customGroups.contains { $0.memberUserIDs.contains(userID) }
    }
    
    // Check if a user is blocked (by deviceID)
    func isBlocked(_ deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return blockedUsers.contains(userID)
    }
    
    // Check if a user has blocked me (by deviceID)
    func hasBlockedMe(_ deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return usersWhoBlockedMe.contains(userID)
    }
    
    // Check if there's mutual blocking (either direction)
    func hasMutualBlocking(_ deviceID: String) -> Bool {
        return isBlocked(deviceID) || hasBlockedMe(deviceID)
    }
    
    // Get blocked user IDs for the blocked users view
    func getBlockedUserIDs() -> Set<String> {
        return blockedUsers
    }
    
    func unblockUser(userID: String) {
        guard let currentUserID = currentUserProfile?.userID,
              blockedUsers.contains(userID) else { return }

        blockedUsers.remove(userID)
        relationshipService.deleteRelationship(userID: currentUserID, targetUserID: userID, actionType: .block) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success {
                    self.forceRefreshGrid()
                } else {
                    self.blockedUsers.insert(userID)
                }
                self.objectWillChange.send()
            }
        }
    }
    
    // Force refresh the grid by fetching all users again
    func forceRefreshGrid() {
        #if DEBUG
        print("GridViewModel: forceRefreshGrid blocked=\(blockedUsers.count) blockedMe=\(usersWhoBlockedMe.count)")
        #endif
        guard hasLocationAccess else { return }

        if let currentLocation = locationService.currentLocation {
            proximityService.fetchAllUsers(currentUserLocation: currentLocation)
        } else {
            proximityService.fetchAllUsers()
        }
    }

    /// Re-layout the grid from cached nearby profiles (no CloudKit round-trip).
    func refreshGridWithCurrentState() {
        #if DEBUG
        print("GridViewModel: refreshGridWithCurrentState profiles=\(proximityService.activeNearbyProfiles.count)")
        #endif
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
    }
    
    func checkAndAddNewSenderToGrid(senderDeviceID: String, senderUserID: String) {
        guard hasLocationAccess else { return }
        if LocalLLMIdentity.isLLM(senderDeviceID) { return }
        if hasProfileOnAnyGrid(deviceID: senderDeviceID) { return }
        guard senderProfileFetchesInFlight.insert(senderDeviceID).inserted else { return }

        print("GridViewModel: New message from device not in grid: \(senderDeviceID). Fetching their profile...")

        let recordID = CKRecord.ID(recordName: senderDeviceID)
        CKContainer.default().publicCloudDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.senderProfileFetchesInFlight.remove(senderDeviceID)
                if self.hasProfileOnAnyGrid(deviceID: senderDeviceID) { return }

                if let record, let profile = UserProfile(record: record) {
                    print("GridViewModel: Successfully fetched profile for new sender: \(profile.displayName)")
                    self.addProfileToGrid(profile)
                    return
                }

                if let error {
                    print("GridViewModel: Error fetching profile for new sender: \(error.localizedDescription)")
                }
                let minimalProfile = UserProfile(
                    userID: senderUserID,
                    deviceID: senderDeviceID,
                    deviceName: ProfileDisplayNameLogic.fallbackTitle
                )
                self.addProfileToGrid(minimalProfile)
            }
        }
    }

    func hasProfileOnAnyGrid(deviceID: String) -> Bool {
        let grids = [allGridNodes, favoriteGridNodes, gridNodes]
            + Array(customGroupNodes.values)
            + Array(interestGridNodes.values)
        return grids.contains { grid in
            grid.flatMap { $0 }.contains { $0.userProfile?.deviceID == deviceID }
        }
    }

    func addProfileToGrid(_ profile: UserProfile) {
        guard profile.deviceID != currentUserProfile?.deviceID else { return }
        guard !hasProfileOnAnyGrid(deviceID: profile.deviceID) else { return }
        if allGridNodes.isEmpty {
            allGridNodes = GridPlacementLogic.makeEmptyGrid()
        }
        guard let slot = GridPlacementLogic.firstEmptySlot(in: allGridNodes) else {
            print("GridViewModel: Grid is full, cannot add new sender")
            return
        }
        GridPlacementLogic.place(profile: profile, in: &allGridNodes, at: slot.row, col: slot.col)
        gridNodes = nodes(for: peopleTab)
        SenderNameCache.store(profile.deviceName, for: profile.deviceID)
        print("GridViewModel: Added new sender to grid at position (\(slot.row), \(slot.col))")
        objectWillChange.send()
    }
    
    // NEW: Get distance string for UI display
    func getDistanceString(to deviceID: String) -> String? {
        guard let currentProfile = currentUserProfile,
              let targetProfile = findNode(forDeviceID: deviceID)?.userProfile else {
            return nil
        }
        
        // Try to get distance from profiles
        if let distance = currentProfile.distance(from: targetProfile) {
            return proximityService.formatDistance(distance)
        }
        
        // Fallback: If one profile is missing location, try using LocationService's current location
        if let currentLocation = locationService.currentLocation,
           let targetLocation = targetProfile.location {
            let distance = currentLocation.distance(from: targetLocation)
            return proximityService.formatDistance(distance)
        }
        
        // If current profile has location but target doesn't, show that we can't calculate
        if currentProfile.location != nil && targetProfile.location == nil {
            return "N/A"
        }
        
        return nil
    }
    
    // NEW: Check if messaging is allowed (for UI state)
    func canMessageUser(deviceID: String) -> (allowed: Bool, reason: String) {
        if LocalLLMIdentity.isLLM(deviceID) {
            return (true, "On this phone")
        }

        guard let currentProfile = currentUserProfile,
              let targetProfile = findNode(forDeviceID: deviceID)?.userProfile else {
            return (false, "Profile not found")
        }
        
        let proximity = proximityService.canMessage(from: currentProfile, to: targetProfile)
        return GridMessagingLogic.canMessage(
            isBlocked: isBlocked(deviceID),
            proximityAllowed: proximity.allowed,
            proximityReason: proximity.reason
        )
    }
}
