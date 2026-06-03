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
    
    // Simplified refresh - upload my location, get all users sorted by distance
    func refreshPublicGrid() {
        print("GridViewModel: Starting simple refresh - upload my location, get all users sorted by distance")
        
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
                        self.currentUserProfile = updatedProfile
                        
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
        guard var profile = currentUserProfile else { return }
        profile.markAsActive()
        self.currentUserProfile = profile
        
        print("App became active - updating activity status only")
        
        // REMOVED: Don't restart location updates
        // locationService.requestLocationPermission()
        
        // Update activity status in CloudKit (without refreshing the grid)
        updateUserActivityAndLocation(profile)
        
        // REMOVED: We don't want to auto-refresh the grid when app becomes active
        // This should only happen on grid appear or manual refresh
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
            messages: messages,
            readReceipts: readReceipts
        )
    }
    
    // NEW: Mark messages as read when opening a chat
    func markMessagesAsRead(from deviceID: String) {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return }
        
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
        
        // Trigger UI update immediately
        objectWillChange.send()
        
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
            self.readReceipts = messageIDs
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
        
        if starredUsers.contains(targetUserID) {
            // Unstar
            starredUsers.remove(targetUserID)
            relationshipService.deleteRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .star) { success in
                print("Star deletion \(success ? "successful" : "failed") for user: \(targetUserID)")
            }
        } else {
            // Star
            starredUsers.insert(targetUserID)
            relationshipService.saveRelationship(userID: currentUserID, targetUserID: targetUserID, actionType: .star)
        }
        
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
        
        // Check grid nodes
        for row in gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == deviceID {
                    return profile.userID
                }
            }
        }
        
        return nil
    }
    
    // Check if a user is starred (by deviceID)
    func isStarred(_ deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return starredUsers.contains(userID)
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
    
    // NEW: Check if sender is in grid, if not fetch their profile and add them
    func checkAndAddNewSenderToGrid(senderDeviceID: String, senderUserID: String) {
        // Check if this sender is already in the grid
        let isInGrid = gridNodes.flatMap { $0 }.contains { node in
            node.userProfile?.deviceID == senderDeviceID
        }
        
        if !isInGrid {
            print("GridViewModel: New message from device not in grid: \(senderDeviceID). Fetching their profile...")
            
            // Fetch just this one user's profile from CloudKit
            let recordID = CKRecord.ID(recordName: senderDeviceID)
            let publicDB = CKContainer.default().publicCloudDatabase
            
            publicDB.fetch(withRecordID: recordID) { [weak self] record, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("GridViewModel: Error fetching profile for new sender: \(error.localizedDescription)")
                        // Create a minimal profile with just the info we have
                        let minimalProfile = UserProfile(
                            userID: senderUserID,
                            deviceID: senderDeviceID,
                            deviceName: "Unknown User"
                        )
                        self.addProfileToGrid(minimalProfile)
                    } else if let record = record, let profile = UserProfile(record: record) {
                        print("GridViewModel: Successfully fetched profile for new sender: \(profile.displayName)")
                        self.addProfileToGrid(profile)
                    }
                }
            }
        }
    }
    
    // Helper to add a profile to the grid
    func addProfileToGrid(_ profile: UserProfile) {
        // Find the first empty spot in the grid (skip position 0,0 which is for current user)
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Skip the top-left position (reserved for current user)
                if i == 0 && j == 0 {
                    continue
                }
                
                if gridNodes[i][j].userProfile == nil {
                    gridNodes[i][j].userProfile = profile
                    print("GridViewModel: Added new sender to grid at position (\(i), \(j))")
                    objectWillChange.send() // Trigger UI update
                    return
                }
            }
        }
        print("GridViewModel: Grid is full, cannot add new sender")
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
