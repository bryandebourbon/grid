/*
 * GridViewModel.swift
 * 
 * CURRENT IMPLEMENTATION: Pure CloudKit location-based messaging (like Grindr)
 * - No MultipeerConnectivity/Bonjour local networking
 * - CloudKit public database for user profiles and locations
 * - Real-time location sharing and proximity-based messaging
 * - 5-mile radius for messaging
 * - Refresh = upload my location + download others' locations
 * 
 * COMMENTED OUT: MultipeerConnectivity system (see NetworkService.swift)
 * To re-enable local networking features:
 * 1. Uncomment NetworkService.swift
 * 2. Add networkService: NetworkService = NetworkService() to init
 * 3. Re-add setupNetworkHandlers() call
 * 4. Uncomment connectedPeersText @Published var
 * 5. Add back Bonjour services to Info.plist if needed
 */

import Combine
import SwiftUI
import CloudKit
import CoreLocation
import PhotosUI

class GridViewModel: ObservableObject {
    @Published var gridNodes: [[GridNode]] = []
    @Published var currentUserProfile: UserProfile?
    @Published var messages: [Message] = [] // For displaying messages
    @Published var currentChatRecipientDeviceID: String? // Device ID of who the current chat is with
    @Published var selfChatNewMessageText: String = "" // For SelfChatView input
    @Published var locationPermissionStatus: String = "Location permission not requested"
    @Published var chatRecipientToPresent: ChatRecipient?
    @Published var pendingChatNavigationDeviceID: String? = nil // For deferred navigation
    @Published var selectedUserProfileForReport: ProfileCardUser? = nil // For report dialog
    @Published var showingStarredOnly: Bool = false { // Toggle for showing only starred users
        didSet {
            // Refresh the grid when filter changes
            let profiles = proximityService.activeNearbyProfiles
            updateGridWithAllProfiles(profiles)
        }
    }
    
    // NEW: Encryption mode properties
    @Published var isEncryptionMode: Bool = false {
        didSet {
            if isEncryptionMode {
                enableEncryptionMode()
            } else {
                disableEncryptionMode()
            }
        }
    }
    @Published var encryptionProfiles: [String: EncryptionProfile] = [:] // deviceID -> EncryptionProfile
    @Published var hasEncryptionKeys: Bool = false
    
    // Track read receipts
    private var readReceipts: Set<String> = [] // Set of messageIDs that have been read
    
    // Track star and block relationships
    private var starredUsers: Set<String> = [] // Set of userIDs that are starred
    private var blockedUsers: Set<String> = [] // Set of userIDs that are blocked

    private var messagingService: MessagingService
    private var gridService: GridService // For public grid management (legacy)
    private var locationService: LocationService // NEW: Location tracking
    private var proximityService: ProximityService // NEW: Proximity-based user filtering
    private var cancellables = Set<AnyCancellable>()
    let gridSize = 5 // Max grid size for internal node storage

    init(messagingService: MessagingService = MessagingService(),
         gridService: GridService = GridService(),
         locationService: LocationService = LocationService(),
         proximityService: ProximityService = ProximityService(),
         initialProfile: UserProfile? = nil) {
        
        self.messagingService = messagingService
        self.gridService = gridService
        self.locationService = locationService
        self.proximityService = proximityService
        self.currentUserProfile = initialProfile
        initializeGrid()
        setupMessagingHandlers()
        setupLocationHandlers()
        setupProximityHandlers()
        setupNavigationHandlers()
        
        if let profile = initialProfile {
            updateUserActivityAndLocation(profile)
            placeCurrentUserOnGrid()
            
            // Load read receipts first, then messages
            loadReadReceipts(forDeviceID: profile.deviceID) { [weak self] in
                // Fetch messages after read receipts are loaded
                self?.fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
            }
            
            // Subscribe to new messages
            messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        }
        
        // Request location permission on init
        locationService.requestLocationPermission()
    }
    
    private func setupMessagingHandlers() {
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
                    if newMessage.isEncrypted && !self.isEncryptionMode {
                        self.objectWillChange.send()
                    }
                }
                
                self.messages.sort(by: { $0.timestamp < $1.timestamp })
                // Consider calling objectWillChange.send() if direct array manipulation doesn't always trigger UI updates,
                // though @Published should handle appends and direct element replacements.
            }
            .store(in: &cancellables)
    }
    
    private func setupLocationHandlers() {
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
    
    private func setupProximityHandlers() {
        // Listen for all users updates (sorted by distance)
        proximityService.$activeNearbyProfiles
            .sink { [weak self] allProfiles in
                guard let self = self else { return }
                // If in encryption mode, filter the profiles before updating grid
                if self.isEncryptionMode {
                    self.refreshGridForEncryptionMode()
                } else {
                    self.updateGridWithAllProfiles(allProfiles)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNavigationHandlers() {
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
                    self.chatRecipientToPresent = ChatRecipient(id: senderDeviceID) 
                } else {
                    // Profile not yet available, store for deferred navigation
                    print("GridViewModel: Current user profile not available. Deferring navigation for senderDeviceID: \(senderDeviceID)")
                    self.pendingChatNavigationDeviceID = senderDeviceID
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleLocationUpdate(_ location: CLLocation?) {
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
    
    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
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
    
    // Show all users on grid (sorted by distance if location available)
    private func updateGridWithAllProfiles(_ profiles: [UserProfile]) {
        // Clear the grid first
        initializeGrid()
        
        guard let currentUserDeviceID = currentUserProfile?.deviceID else {
            // If no current user, just place profiles normally
            for profile in profiles {
                placeProfileOnGrid(profile)
            }
            print("Updated grid with \(profiles.count) users")
            objectWillChange.send()
            return
        }
        
        // Separate current user from other profiles
        var currentUserProfile: UserProfile?
        var otherProfiles: [UserProfile] = []
        
        for profile in profiles {
            if profile.deviceID == currentUserDeviceID {
                currentUserProfile = profile
            } else {
                otherProfiles.append(profile)
            }
        }
        
        // Filter profiles if showing starred only
        if showingStarredOnly {
            otherProfiles = otherProfiles.filter { profile in
                starredUsers.contains(profile.userID)
            }
        }
        
        // Place current user first at position (0, 0)
        if let currentProfile = currentUserProfile {
            gridNodes[0][0].userProfile = currentProfile
            print("Placed current user '\(currentProfile.displayName)' at top-left position (0,0)")
        }
        
        // Place other profiles in remaining positions (sorted by distance if location available)
        for profile in otherProfiles {
            placeProfileOnGridSkippingPosition(profile, skipX: 0, skipY: 0)
        }
        
        let filterStatus = showingStarredOnly ? " (starred only)" : ""
        print("Updated grid with \(otherProfiles.count + 1) total users\(filterStatus) (current user at top-left)")
        objectWillChange.send()
    }
    
    // LEGACY: Keep for backwards compatibility but prefer proximity-based updates
    private func updateGridWithPublicProfiles(_ profiles: [UserProfile]) {
        // This method is now mainly for fallback when location is not available
        updateGridWithAllProfiles(profiles)
    }
    
    private func placeProfileOnGrid(_ profile: UserProfile) {
        // Find the first available spot and place the profile
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if gridNodes[i][j].userProfile == nil {
                    gridNodes[i][j].userProfile = profile
                    return
                }
            }
        }
        print("Grid is full! Cannot place device with ID \(profile.deviceID)")
    }

    private func placeProfileOnGridSkippingPosition(_ profile: UserProfile, skipX: Int, skipY: Int) {
        // Find the first available spot, skipping the specified position
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Skip the specified position
                if i == skipX && j == skipY {
                    continue
                }
                if gridNodes[i][j].userProfile == nil {
                    gridNodes[i][j].userProfile = profile
                    return
                }
            }
        }
        print("Grid is full! Cannot place device with ID \(profile.deviceID)")
    }

    private func updateUserActivityAndLocation(_ profile: UserProfile) {
        proximityService.updateUserActivity(profile) { result in
            switch result {
            case .success(let updatedProfile):
                print("Successfully updated user activity: \(updatedProfile.deviceName)")
            case .failure(let error):
                print("Error updating user activity: \(error.localizedDescription)")
            }
        }
    }
    
    private func placeCurrentUserOnGrid() {
        guard let profile = currentUserProfile else { return }
        // Remove current device from any previous position
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if gridNodes[i][j].userProfile?.deviceID == profile.deviceID {
                    gridNodes[i][j].userProfile = nil
                }
            }
        }
        var placed = false
        outerLoop: for i in 0..<gridSize {
            for j in 0..<gridSize {
                if gridNodes[i][j].userProfile == nil {
                    gridNodes[i][j].userProfile = profile
                    placed = true
                    break outerLoop
                }
            }
        }
        if !placed {
            print("Grid is full! Cannot place device with ID \(profile.deviceID)")
        }
        objectWillChange.send()
    }
    
    // LEGACY: Keep for backward compatibility but now uses preloaded messages
    func fetchMessagesForCurrentDevice(deviceID: String) {
        print("GridViewModel: Using preloaded messages (no CloudKit fetch needed)")
        // Messages are already loaded and kept up-to-date via real-time subscription
        // This method is kept for compatibility but doesn't need to do anything
        print("GridViewModel: \(messages.count) messages already available instantly")
    }

    func initializeGrid() {
        gridNodes = []
        for i in 0..<gridSize {
            var row: [GridNode] = []
            for j in 0..<gridSize {
                row.append(GridNode(id: UUID(), x: i, y: j, userProfile: nil))
            }
            gridNodes.append(row)
        }
    }

    func updateCurrentUsername(newUsername: String) {
        // This method might need re-evaluation as UserProfile uses deviceName instead of username
        // For now, it could update the deviceName if needed
        guard let profile = currentUserProfile else {
            print("Cannot update, currentUserProfile is nil.")
            return
        }
        // Note: You might want to add a separate username field or modify deviceName
        print("Username update called. Note: Consider adding a separate username field or updating deviceName.")
        updateUserActivityAndLocation(profile)
        placeCurrentUserOnGrid()
        print("Current user profile updated and saved to public grid.")
    }
    
    func setCurrentUserProfile(_ profile: UserProfile) {
        self.currentUserProfile = profile
        updateUserActivityAndLocation(profile) // NEW: Use activity-based saving
        placeCurrentUserOnGrid()
        print("GridViewModel: Set current user profile for device ID \(profile.deviceID) (user: \(profile.userID))")
        
        // Load star/block relationships first
        print("GridViewModel: Loading star/block relationships...")
        loadStarBlockRelationships(forUserID: profile.userID) { [weak self] in
            guard let self = self else { return }
            
            // Load read receipts after star/block
            print("GridViewModel: Loading read receipts...")
            self.loadReadReceipts(forDeviceID: profile.deviceID) { [weak self] in
                guard let self = self else { return }
                
                // After read receipts are loaded, fetch messages
                print("GridViewModel: Preloading all messages for instant chat access...")
                self.fetchAllMessagesForCurrentDevice(deviceID: profile.deviceID)
            }
        }
        
        // Subscribe to message changes immediately
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        
        // REMOVED: Don't start location updates automatically
        // locationService.requestLocationPermission()

        // Check for deferred navigation
        if let pendingDeviceID = pendingChatNavigationDeviceID {
            print("GridViewModel: Handling deferred navigation to chat with deviceID: \(pendingDeviceID)")
            selectChatPartner(partnerDeviceID: pendingDeviceID)
            chatRecipientToPresent = ChatRecipient(id: pendingDeviceID)
            pendingChatNavigationDeviceID = nil // Clear after handling
        }
    }
    
    // Enhanced: Fetch ALL messages for the current device (for all conversations)
    private func fetchAllMessagesForCurrentDevice(deviceID: String) {
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
        
        return messages.filter { message in
            (message.senderDeviceID == currentDeviceID && message.recipientDeviceID == deviceID) ||
            (message.senderDeviceID == deviceID && message.recipientDeviceID == currentDeviceID)
        }.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    // NEW: Get conversation list with last message preview
    func getConversationList() -> [(deviceID: String, displayName: String, lastMessage: Message?, messageCount: Int)] {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return [] }
        
        // Group messages by conversation partner
        let conversations = Dictionary(grouping: messages) { message in
            message.senderDeviceID == currentDeviceID ? message.recipientDeviceID : message.senderDeviceID
        }
        
        return conversations.compactMap { (otherDeviceID, conversationMessages) in
            let sortedMessages = conversationMessages.sorted(by: { $0.timestamp < $1.timestamp })
            let lastMessage = sortedMessages.last
            
            // Get display name from grid if available
            var displayName = "Device \(String(otherDeviceID.prefix(8)))"
            if otherDeviceID == currentDeviceID {
                displayName = "My Notes"
            } else {
                // Look for the device in the grid
                for row in gridNodes {
                    for node in row {
                        if let profile = node.userProfile, profile.deviceID == otherDeviceID {
                            displayName = profile.displayName
                            break
                        }
                    }
                }
            }
            
            return (deviceID: otherDeviceID, displayName: displayName, lastMessage: lastMessage, messageCount: conversationMessages.count)
        }.sorted { conversation1, conversation2 in
            // Sort by last message timestamp, most recent first
            guard let date1 = conversation1.lastMessage?.timestamp,
                  let date2 = conversation2.lastMessage?.timestamp else {
                return conversation1.lastMessage != nil && conversation2.lastMessage == nil
            }
            return date1 > date2
        }
    }
    
    // LEGACY: Keep for backwards compatibility
    private func saveProfileToPublicGrid(_ profile: UserProfile) {
        updateUserActivityAndLocation(profile)
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
    
    private func persistAndUpdateProfileAndGrid(completion: ((Bool) -> Void)? = nil) {
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
    
    // NEW: Helper function to detect CloudKit daemon connection errors
    private func isCloudKitDaemonConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for the specific CloudKit daemon connection error
        if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 4099 {
            return true
        }
        
        // Check error description for daemon-related issues
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("cloudd") || 
           errorDescription.contains("daemon") ||
           errorDescription.contains("connection") && errorDescription.contains("cloudkit") {
            return true
        }
        
        return false
    }

    private func findNode(forDeviceID deviceID: String) -> GridNode? {
        for row in gridNodes {
            for node in row {
                if node.userProfile?.deviceID == deviceID {
                    return node
                }
            }
        }
        return nil
    }
    
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
        
        // Count messages that are:
        // 1. From the specified device TO the current user
        // 2. Haven't been read yet (not in readReceipts)
        return messages.filter { message in
            message.senderDeviceID == deviceID && 
            message.recipientDeviceID == currentDeviceID && 
            !readReceipts.contains(message.id)
        }.count
    }
    
    // NEW: Mark messages as read when opening a chat
    func markMessagesAsRead(from deviceID: String) {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return }
        
        let publicDB = CKContainer.default().publicCloudDatabase
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
        
        // Save read receipts to CloudKit
        if !newReadReceipts.isEmpty {
            print("Creating \(newReadReceipts.count) read receipts in CloudKit")
            
            let records = newReadReceipts.map { $0.toCKRecord() }
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            
            operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
                if let error = error {
                    print("Error saving read receipts to CloudKit: \(error.localizedDescription)")
                } else {
                    print("Successfully saved \(savedRecords?.count ?? 0) read receipts to CloudKit")
                }
            }
            publicDB.add(operation)
        }
    }
    
    // NEW: Load star/block relationships from CloudKit
    private func loadStarBlockRelationships(forUserID userID: String, completion: @escaping () -> Void = {}) {
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "userID == %@", userID)
        let query = CKQuery(recordType: "UserRelationships", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion()
                    return
                }
                
                if let error = error {
                    print("Error loading star/block relationships: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                if let records = records {
                    // Clear existing and load fresh from CloudKit
                    self.starredUsers.removeAll()
                    self.blockedUsers.removeAll()
                    
                    for record in records {
                        if let relationship = UserRelationship(record: record) {
                            switch relationship.actionType {
                            case .star:
                                self.starredUsers.insert(relationship.targetUserID)
                            case .block:
                                self.blockedUsers.insert(relationship.targetUserID)
                            case .report:
                                // Reports are handled separately - they're not stored in a set
                                // Skip report records when loading star/block relationships
                                break
                            }
                        }
                    }
                    
                    print("Loaded \(self.starredUsers.count) starred users and \(self.blockedUsers.count) blocked users from CloudKit")
                    
                    // Trigger UI update
                    self.objectWillChange.send()
                }
                
                completion()
            }
        }
    }
    
    // NEW: Load read receipts from CloudKit
    private func loadReadReceipts(forDeviceID deviceID: String, completion: @escaping () -> Void = {}) {
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "deviceID == %@", deviceID)
        let query = CKQuery(recordType: "ReadReceipts", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let self = self else { 
                    completion()
                    return 
                }
                
                if let error = error {
                    print("Error loading read receipts: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                if let records = records {
                    // Clear existing and load fresh from CloudKit
                    self.readReceipts.removeAll()
                    
                    for record in records {
                        if let receipt = ReadReceipt(record: record) {
                            self.readReceipts.insert(receipt.messageID)
                        }
                    }
                    
                    print("Loaded \(self.readReceipts.count) read receipts from CloudKit")
                    
                    // Update message statuses based on read receipts
                    for index in self.messages.indices {
                        if self.readReceipts.contains(self.messages[index].id) &&
                           self.messages[index].recipientDeviceID == deviceID {
                            self.messages[index].status = .sent
                        }
                    }
                    
                    // Trigger UI update
                    self.objectWillChange.send()
                }
                
                completion()
            }
        }
    }
    
    // NEW: Star/unstar a user
    func toggleStar(for deviceID: String) {
        guard let currentUserID = currentUserProfile?.userID,
              let targetUserID = getUserID(forDeviceID: deviceID) else { return }
        
        if starredUsers.contains(targetUserID) {
            // Unstar
            starredUsers.remove(targetUserID)
            deleteStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .star)
        } else {
            // Star
            starredUsers.insert(targetUserID)
            saveStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .star)
        }
        
        // Refresh the grid if we're in starred-only mode
        if showingStarredOnly {
            let profiles = proximityService.activeNearbyProfiles
            updateGridWithAllProfiles(profiles)
        }
        
        objectWillChange.send()
    }
    
    // NEW: Block/unblock a user
    func toggleBlock(for deviceID: String) {
        guard let currentUserID = currentUserProfile?.userID,
              let targetUserID = getUserID(forDeviceID: deviceID) else { return }
        
        if blockedUsers.contains(targetUserID) {
            // Unblock
            blockedUsers.remove(targetUserID)
            deleteStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .block)
        } else {
            // Block
            blockedUsers.insert(targetUserID)
            saveStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .block)
        }
        
        objectWillChange.send()
    }
    
    // Helper to save star/block record to CloudKit
    private func saveStarBlockRecord(userID: String, targetUserID: String, actionType: UserRelationship.ActionType) {
        let relationship = UserRelationship(userID: userID, targetUserID: targetUserID, actionType: actionType)
        let record = relationship.toCKRecord()
        
        let publicDB = CKContainer.default().publicCloudDatabase
        publicDB.save(record) { savedRecord, error in
            if let error = error {
                print("Error saving \(actionType.rawValue) relationship: \(error.localizedDescription)")
            } else {
                print("Successfully saved \(actionType.rawValue) relationship for user: \(targetUserID)")
            }
        }
    }
    
    // Helper to delete star/block record from CloudKit
    private func deleteStarBlockRecord(userID: String, targetUserID: String, actionType: UserRelationship.ActionType) {
        let recordID = CKRecord.ID(recordName: "\(userID)_\(targetUserID)_\(actionType.rawValue)")
        
        let publicDB = CKContainer.default().publicCloudDatabase
        publicDB.delete(withRecordID: recordID) { deletedRecordID, error in
            if let error = error {
                print("Error deleting \(actionType.rawValue) relationship: \(error.localizedDescription)")
            } else {
                print("Successfully deleted \(actionType.rawValue) relationship for user: \(targetUserID)")
            }
        }
    }
    
    // Helper to get userID from deviceID
    private func getUserID(forDeviceID deviceID: String) -> String? {
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
    
    // NEW: Check if sender is in grid, if not fetch their profile and add them
    private func checkAndAddNewSenderToGrid(senderDeviceID: String, senderUserID: String) {
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
    private func addProfileToGrid(_ profile: UserProfile) {
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
        
        // Check if the user is blocked (checks by userID)
        if isBlocked(deviceID) {
            return (false, "You have blocked this user")
        }
        
        // Check proximity-based messaging rules
        return proximityService.canMessage(from: currentProfile, to: targetProfile)
    }

    // MARK: - Messaging Methods

    func selectChatPartner(partnerDeviceID: String) {
        self.currentChatRecipientDeviceID = partnerDeviceID
        print("Selected chat partner device: \(partnerDeviceID)")
    }

    // Simplified sendMessage - can message anyone you can see
    func sendMessage(text: String, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else {
            print("Error: Current user profile not available to send message.")
            return
        }
        
        // Check if encryption should be used
        let shouldEncrypt = isEncryptionMode && encryptionProfiles[recipientDeviceID] != nil
        
        let recipientProfile: UserProfile
        if recipientDeviceID == senderProfile.deviceID {
            recipientProfile = senderProfile
        } else {
            // TODO: This should ideally come from a more reliable source than just gridNodes,
            // perhaps a dedicated user cache if available, or ensure gridNodes is always up-to-date.
            guard let foundProfile = findNode(forDeviceID: recipientDeviceID)?.userProfile else {
                print("Error: Could not find recipient profile for device \(recipientDeviceID)")
                // OPTIONAL: Create a temporary message with .failed status or inform user.
                return
            }
            recipientProfile = foundProfile
        }
        
        // 1. Create optimistic message
        // The temporaryID will be used to find and update this message upon server response.
        let temporaryID = UUID().uuidString
        var optimisticMessage = Message(
            id: temporaryID, // Use temporary client-generated ID
            senderDeviceID: senderProfile.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: senderProfile.userID,
            recipientUserID: recipientProfile.userID, // Make sure recipientProfile.userID is valid
            text: text,
            timestamp: Date(), // Client-side timestamp for now
            status: .sending  // Initial status
        )
        
        // Handle encryption if needed
        if shouldEncrypt {
            guard let recipientEncryptionProfile = encryptionProfiles[recipientDeviceID],
                  let encryptedData = CryptoService.shared.encrypt(text: text, withPublicKey: recipientEncryptionProfile.publicKey) else {
                print("Failed to encrypt message")
                return
            }
            
            optimisticMessage.isEncrypted = true
            optimisticMessage.encryptedContent = encryptedData.base64EncodedString()  // Convert to base64 string
            optimisticMessage.encryptionKeyID = recipientEncryptionProfile.id
            optimisticMessage.text = "[Encrypted Message]" // Placeholder for CloudKit
        } else {
            optimisticMessage.isEncrypted = false
        }
        
        // 2. Add to local messages array immediately
        // This should trigger UI update due to @Published
        self.messages.append(optimisticMessage)
        self.messages.sort(by: { $0.timestamp < $1.timestamp }) // Keep sorted
        print("GridViewModel: Optimistically added message (TempID: \(temporaryID)): \(text)")

        // 3. Send to messaging service
        // Note: The `message` object sent to `messagingService.sendMessage` might need to be the one
        // created *without* the temporaryID if the service expects to generate the ID or use CKRecord.ID.
        // For now, assuming messagingService.sendMessage can handle a Message object that might have a client ID.
        // Let's re-create it for sending, or ensure `toCKRecord()` uses `id` for `recordName`.
        // The current `Message.toCKRecord()` uses `self.id` for the recordName, so `optimisticMessage` is fine.
        
        messagingService.sendMessage(optimisticMessage) { [weak self] result in
            guard let self = self else { return }
            
            // Find the optimistic message in our array using its temporaryID
            guard let optimisticMessageIndex = self.messages.firstIndex(where: { $0.id == temporaryID && $0.status == .sending }) else {
                print("GridViewModel: Could not find optimistic message (TempID: \(temporaryID)) to update after send attempt. It might have been already updated or removed.")
                // If the message from subscription arrived faster and replaced it, that's okay.
                // Or if `savedMessage.id` from success case matches the `temporaryID` initially, that's also okay.
                // Let's check if a message with the *potential* final ID (if known from savedMessage) exists.
                if case .success(let savedMessage) = result, self.messages.contains(where: { $0.id == savedMessage.id }) {
                    print("GridViewModel: Message (ID: \(savedMessage.id)) seems to be already updated by subscription or direct ID match.")
                }
                return
            }
            
            switch result {
            case .success(let savedMessage):
                // Update the optimistic message with server-confirmed data
                self.messages[optimisticMessageIndex].id = savedMessage.id // This is CKRecord.ID.recordName
                self.messages[optimisticMessageIndex].recordID = savedMessage.recordID
                self.messages[optimisticMessageIndex].timestamp = savedMessage.timestamp // Server authoritative timestamp
                self.messages[optimisticMessageIndex].status = .sent
                print("GridViewModel: Optimistic message (TempID: \(temporaryID)) confirmed by server. New ID: \(savedMessage.id), Status: .sent")
                
            case .failure(let error):
                self.messages[optimisticMessageIndex].status = .failed
                print("GridViewModel: Optimistic message (TempID: \(temporaryID)) failed to send: \(error.localizedDescription). Status: .failed")
                // TODO: Implement retry logic or user notification
            }
            
            // Re-sort after update
            self.messages.sort(by: { $0.timestamp < $1.timestamp })
            // self.objectWillChange.send() // If needed
        }
    }

    // NEW: Auto-refresh when location is obtained or app state changes
    private func autoRefreshGrid(with location: CLLocation? = nil) {
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

    // Function to process PhotosPickerItems for additional photos
    func processSelectedPhotoItems(_ items: [PhotosPickerItem]) {
        guard let currentUserProfile = self.currentUserProfile else {
            print("GridViewModel: Cannot process photos, no current user profile.")
            return
        }
        
        var loadedImageDatas: [Data] = []
        let group = DispatchGroup()
        
        print("GridViewModel: Processing \\(items.count) selected photo items...")
        
        for item in items {
            group.enter()
            item.loadTransferable(type: Data.self) { result in
                defer { group.leave() }
                switch result {
                case .success(let data?):
                    loadedImageDatas.append(data)
                    print("GridViewModel: Successfully loaded image data (\u{2022}\\(data.count) bytes).")
                case .success(nil):
                    print("GridViewModel: Warning - loaded image data is nil.")
                case .failure(let error):
                    print("GridViewModel: Error loading image data: \\(error.localizedDescription)")
                }
            }
        }
        
        group.notify(queue: .main) {
            print("GridViewModel: All selected photos processed. Total loaded: \(loadedImageDatas.count)")
            
            // Store the actual image data as CloudKit assets
            var updatedPhotoAssets = self.currentUserProfile?.additionalPhotos ?? []
            
            // Create CKAsset objects from image data
            for (index, imageData) in loadedImageDatas.enumerated() {
                // Use Documents directory for temporary storage before CloudKit upload
                guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("GridViewModel: Could not access Documents directory")
                    continue
                }
                
                let fileName = "temp_photo_\(UUID().uuidString).jpg"
                let tempFileURL = documentsDir.appendingPathComponent(fileName)
                
                do {
                    try imageData.write(to: tempFileURL)
                    // Create CKAsset from the temporary file
                    let photoAsset = CKAsset(fileURL: tempFileURL)
                    updatedPhotoAssets.append(photoAsset)
                    print("GridViewModel: Created CKAsset for photo \(index + 1): \(tempFileURL.lastPathComponent)")
                } catch {
                    print("GridViewModel: Error creating CKAsset for photo \(index + 1): \(error.localizedDescription)")
                }
            }
            
            self.currentUserProfile?.additionalPhotos = updatedPhotoAssets
            print("GridViewModel: Updated additionalPhotos count: \(updatedPhotoAssets.count)")
            
            // Save the profile if it was modified
            if var profileToSave = self.currentUserProfile {
                // Save to CloudKit immediately to ensure persistence
                self.proximityService.updateUserActivity(profileToSave) { [weak self] result in
                    switch result {
                    case .success(let savedProfile):
                        print("GridViewModel: Successfully saved profile with photo assets to CloudKit")
                        // Update with the saved profile to ensure consistency
                        self?.currentUserProfile = savedProfile
                    case .failure(let error):
                        print("GridViewModel: Error saving profile with photo assets to CloudKit: \(error.localizedDescription)")
                        print("GridViewModel: Photos will remain local until next successful save")
                        // Don't overwrite the local profile - keep the photos locally until we can save to CloudKit
                        // The photos will be retried on the next profile update
                    }
                }
                print("GridViewModel: Initiated save of profile with new photo assets to CloudKit")
            } else {
                print("GridViewModel: currentUserProfile is nil, cannot save additional photos.")
            }
        }
    }
    
    // Method to retry saving photos to CloudKit
    func retrySavePhotosToCloudKit() {
        guard let profile = currentUserProfile,
              let photos = profile.additionalPhotos,
              !photos.isEmpty else {
            print("GridViewModel: No photos to retry saving")
            return
        }
        
        print("GridViewModel: Retrying save of \(photos.count) photos to CloudKit")
        
        proximityService.updateUserActivity(profile) { [weak self] result in
            switch result {
            case .success(let savedProfile):
                print("GridViewModel: Successfully retried save of profile with photo assets to CloudKit")
                self?.currentUserProfile = savedProfile
            case .failure(let error):
                print("GridViewModel: Retry failed - Error saving profile with photo assets to CloudKit: \(error.localizedDescription)")
            }
        }
    }
    
    // Method to clean up duplicate userID records
    // REMOVING THIS METHOD as ProximityService.cleanupDuplicateUserIDs was removed
    /*
    func cleanupDuplicateUserIDs() {
        print("GridViewModel: Initiating cleanup of duplicate userID records...")
        
        proximityService.cleanupDuplicateUserIDs { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success():
                    print("GridViewModel: Successfully completed duplicate userID cleanup")
                    // After cleanup, refresh the grid to get clean data
                    self?.refreshPublicGrid()
                case .failure(let error):
                    print("GridViewModel: Duplicate cleanup failed: \(error.localizedDescription)")
                    // Continue anyway - the app should still work
                    self?.refreshPublicGrid()
                }
            }
        }
    }
    */
    
    // Enhanced app startup with cleanup
    func handleAppStartupWithCleanup() {
        print("GridViewModel: Starting app with duplicate cleanup...")
        
        // First, clean up any duplicate records
        // cleanupDuplicateUserIDs()
    }

    func updateProfilePhotos(mainPhotoData: Data?, additionalPhotoAssets: [CKAsset], completion: @escaping (Bool) -> Void) {
        guard currentUserProfile != nil else {
            print("Cannot update photos, currentUserProfile is nil.")
            completion(false)
            return
        }

        var mainPhotoAsset: CKAsset? = currentUserProfile?.profileImage // Keep existing if no new main photo data
        var tempMainPhotoURL: URL? // For cleanup if new main photo is processed

        if let data = mainPhotoData {
            // New main photo provided, process it
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do {
                try data.write(to: fileURL)
                mainPhotoAsset = CKAsset(fileURL: fileURL)
                tempMainPhotoURL = fileURL // Keep track for cleanup
                print("New main profile image processed. Temp file: \(fileURL.path)")
            } catch {
                print("Error creating CKAsset for new main profile image: \(error.localizedDescription)")
                completion(false)
                return
            }
        } else if currentUserProfile?.profileImage != nil && mainPhotoData == nil {
            // This condition implies the user might want to remove the main photo without setting a new one.
            // If your UI allows this, set mainPhotoAsset to nil.
            // For now, we assume if mainPhotoData is nil, we keep the existing or it was never set.
            // If you add a "remove main photo" button, this logic would change:
            // mainPhotoAsset = nil 
        }

        currentUserProfile?.profileImage = mainPhotoAsset
        currentUserProfile?.additionalPhotos = additionalPhotoAssets

        print("Profile photos updated locally. Persisting to CloudKit...")
        
        persistAndUpdateProfileAndGrid() { success in
            if !success {
                print("Failed to persist profile updates to CloudKit.")
                
                // Check if this was a CloudKit daemon connection error
                // The actual error handling is done in persistAndUpdateProfileAndGrid
                // but we can provide additional context here
                
                // If saving to CloudKit failed, new temp files might need cleanup.
                // The main tempMainPhotoURL is particularly important here.
                if let url = tempMainPhotoURL {
                    try? FileManager.default.removeItem(at: url)
                    print("Cleaned up temporary main photo file after failed save: \(url.path)")
                }
                // Note: additionalPhotoAssets passed to this function are either existing (no new temp file) 
                // or new (temp files created in ProfileCardView). 
                // ProfileCardView is responsible for cleaning up its *newly created* temp files on failure from this callback.
            }
            completion(success)
        }
    }

    func sendImageMessage(imageData: Data, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else {
            print("Error: Current user profile not available to send image message.")
            return
        }

        let recipientProfile: UserProfile
        if recipientDeviceID == senderProfile.deviceID {
            recipientProfile = senderProfile
        } else {
            guard let foundProfile = findNode(forDeviceID: recipientDeviceID)?.userProfile else {
                print("Error: Could not find recipient profile for device \(recipientDeviceID) to send image.")
                return
            }
            recipientProfile = foundProfile
        }

        // 1. Create CKAsset from imageData
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        var imageAsset: CKAsset?
        do {
            try imageData.write(to: tempFileURL)
            imageAsset = CKAsset(fileURL: tempFileURL)
        } catch {
            print("Error creating CKAsset for image message: \(error.localizedDescription)")
            // Optionally, inform the user that the image couldn't be prepared.
            return
        }

        guard let finalImageAsset = imageAsset else {
            print("Failed to create image asset, cannot send message.")
            // Cleanup temp file if asset creation failed mid-way, though CKAsset init might not fail if URL is valid
            try? FileManager.default.removeItem(at: tempFileURL)
            return
        }

        // 2. Create optimistic message (text is empty for now)
        let temporaryID = UUID().uuidString
        let optimisticMessage = Message(
            id: temporaryID,
            senderDeviceID: senderProfile.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: senderProfile.userID,
            recipientUserID: recipientProfile.userID,
            text: "", // Empty text for image messages, or you can add a placeholder like "[Image]"
            timestamp: Date(),
            status: .sending,
            imageAsset: finalImageAsset // The optimistic asset (local temp file URL)
        )

        // 3. Add to local messages array immediately
        self.messages.append(optimisticMessage)
        self.messages.sort(by: { $0.timestamp < $1.timestamp })
        print("GridViewModel: Optimistically added image message (TempID: \(temporaryID))")

        // 4. Send to messaging service
        messagingService.sendMessage(optimisticMessage) { [weak self] result in
            guard let self = self else { 
                // If self is nil, attempt to clean up the temp file if it still exists
                try? FileManager.default.removeItem(at: tempFileURL)
                return
            }

            guard let optimisticMessageIndex = self.messages.firstIndex(where: { $0.id == temporaryID && $0.status == .sending }) else {
                print("GridViewModel: Could not find optimistic image message (TempID: \(temporaryID)) to update after send attempt.")
                // If message not found, the temp file might be orphaned. Clean it up.
                try? FileManager.default.removeItem(at: tempFileURL) 
                return
            }
            
            switch result {
            case .success(let savedMessage):
                // Server confirmed, update local message.
                // The CKAsset in savedMessage now points to the CloudKit stored asset.
                // The local temporary file should be cleaned up.
                self.messages[optimisticMessageIndex].id = savedMessage.id
                self.messages[optimisticMessageIndex].recordID = savedMessage.recordID
                self.messages[optimisticMessageIndex].timestamp = savedMessage.timestamp
                self.messages[optimisticMessageIndex].status = .sent
                self.messages[optimisticMessageIndex].imageAsset = savedMessage.imageAsset // Update with server asset
                print("GridViewModel: Optimistic image message (TempID: \(temporaryID)) confirmed. New ID: \(savedMessage.id)")
                try? FileManager.default.removeItem(at: tempFileURL) // Cleanup successful upload
                
            case .failure(let error):
                self.messages[optimisticMessageIndex].status = .failed
                print("GridViewModel: Optimistic image message (TempID: \(temporaryID)) failed to send: \(error.localizedDescription)")
                // Temp file cleanup for failed uploads might depend on retry strategy.
                // For now, let's remove it. If retries are implemented, manage temp file lifecycle carefully.
                try? FileManager.default.removeItem(at: tempFileURL)
            }
            self.messages.sort(by: { $0.timestamp < $1.timestamp })
        }
    }

    func performFullAccountDeletion(completion: @escaping (Error?) -> Void) {
        guard let userIDToDelete = currentUserProfile?.userID else {
            print("GridViewModel: UserID not found, cannot perform account deletion.")
            completion(NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found."]))
            return
        }

        print("GridViewModel: Starting full account deletion for userID: \(userIDToDelete)")
        let publicDB = CKContainer.default().publicCloudDatabase
        let dispatchGroup = DispatchGroup()
        var encounteredError: Error? = nil

        // 1. Delete UserProfile records
        dispatchGroup.enter()
        let userProfilePredicate = NSPredicate(format: "userID == %@", userIDToDelete)
        let userProfileQuery = CKQuery(recordType: "UserProfiles", predicate: userProfilePredicate)
        
        fetchAndDeleteRecords(database: publicDB, query: userProfileQuery, recordTypeForLog: "UserProfiles") { error in
            if let error = error {
                print("GridViewModel: Error deleting UserProfile records: \(error.localizedDescription)")
                encounteredError = encounteredError ?? error // Keep the first error
            }
            dispatchGroup.leave()
        }

        // 2. Delete sent Messages
        dispatchGroup.enter()
        let sentMessagesPredicate = NSPredicate(format: "senderUserID == %@", userIDToDelete)
        let sentMessagesQuery = CKQuery(recordType: "Messages", predicate: sentMessagesPredicate)
        
        fetchAndDeleteRecords(database: publicDB, query: sentMessagesQuery, recordTypeForLog: "Sent Messages") { error in
            if let error = error {
                print("GridViewModel: Error deleting sent Message records: \(error.localizedDescription)")
                encounteredError = encounteredError ?? error
            }
            dispatchGroup.leave()
        }

        // 3. Delete received Messages (where this user was the recipient)
        dispatchGroup.enter()
        let receivedMessagesPredicate = NSPredicate(format: "recipientUserID == %@", userIDToDelete)
        let receivedMessagesQuery = CKQuery(recordType: "Messages", predicate: receivedMessagesPredicate)
        
        fetchAndDeleteRecords(database: publicDB, query: receivedMessagesQuery, recordTypeForLog: "Received Messages") { error in
            if let error = error {
                print("GridViewModel: Error deleting received Message records: \(error.localizedDescription)")
                encounteredError = encounteredError ?? error
            }
            dispatchGroup.leave()
        }

        // Notify when all deletion tasks are complete
        dispatchGroup.notify(queue: .main) {
            if encounteredError == nil {
                print("GridViewModel: Successfully deleted all records associated with userID: \(userIDToDelete)")
            }
            completion(encounteredError)
        }
    }

    private func fetchAndDeleteRecords(database: CKDatabase, query: CKQuery, recordTypeForLog: String, completion: @escaping (Error?) -> Void) {
        var recordIDsToDelete: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor? = nil // Initialize cursor to nil

        func fetchNextBatch() {
            let operation: CKQueryOperation
            if let currentCursor = cursor {
                operation = CKQueryOperation(cursor: currentCursor)
            } else {
                operation = CKQueryOperation(query: query)
            }
            operation.resultsLimit = CKQueryOperation.maximumResults // Fetch max allowed

            operation.recordFetchedBlock = { record in
                recordIDsToDelete.append(record.recordID)
            }

            operation.queryCompletionBlock = { [weak self] opCursor, error in
                if let error = error {
                    print("GridViewModel: Error fetching \(recordTypeForLog) for deletion: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                cursor = opCursor
                if opCursor != nil {
                    // More records to fetch
                    fetchNextBatch()
                } else {
                    // All records fetched, proceed to delete
                    self?.deleteRecords(database: database, recordIDs: recordIDsToDelete, recordTypeForLog: recordTypeForLog, completion: completion)
                }
            }
            database.add(operation)
        }
        fetchNextBatch() // Start fetching the first batch
    }

    private func deleteRecords(database: CKDatabase, recordIDs: [CKRecord.ID], recordTypeForLog: String, completion: @escaping (Error?) -> Void) {
        if recordIDs.isEmpty {
            print("GridViewModel: No \(recordTypeForLog) records found to delete.")
            completion(nil)
            return
        }

        print("GridViewModel: Attempting to delete \(recordIDs.count) \(recordTypeForLog) records.")
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        operation.isAtomic = false // Try to delete as many as possible, even if some fail

        operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            if let error = error {
                print("GridViewModel: Error during batch deletion of \(recordTypeForLog): \(error.localizedDescription)")
                // Check for partial failures
                if let ckError = error as? CKError, ckError.code == .partialFailure {
                    if let partialErrors = ckError.partialErrorsByItemID {
                        for (key, partialError) in partialErrors {
                            if let recordID = key as? CKRecord.ID {
                                print("GridViewModel: Error deleting record \(recordID.recordName): \(partialError.localizedDescription)")
                            } else {
                                print("GridViewModel: Error deleting a record (ID not CKRecord.ID): \(partialError.localizedDescription)")
                            }
                        }
                    }
                    // Even with partial failure, we might consider the overall operation as 'handled'
                    // depending on how critical individual deletions are. For now, pass the main error.
                }
                completion(error)
            } else {
                print("GridViewModel: Successfully deleted \(deletedRecordIDs?.count ?? 0) \(recordTypeForLog) records.")
                completion(nil)
            }
        }
        database.add(operation)
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

    // MARK: - Encryption Mode Support
    
    private func enableEncryptionMode() {
        print("GridViewModel: Enabling encryption mode...")
        
        // Check if keys exist
        hasEncryptionKeys = CryptoService.shared.hasEncryptionKeys()
        
        if !hasEncryptionKeys {
            // Generate new keys
            if let (publicKey, _) = CryptoService.shared.generateKeyPair() {
                hasEncryptionKeys = true
                
                // Create and save encryption profile
                guard let deviceID = currentUserProfile?.deviceID else { return }
                let encryptionProfile = EncryptionProfile(deviceID: deviceID, publicKey: publicKey)
                
                // Add to local cache immediately
                encryptionProfiles[deviceID] = encryptionProfile
                
                saveEncryptionProfile(encryptionProfile)
            }
        } else {
            // Keys exist, ensure our profile is published
            guard let deviceID = currentUserProfile?.deviceID,
                  let publicKey = CryptoService.shared.getPublicKey() else { return }
            let encryptionProfile = EncryptionProfile(deviceID: deviceID, publicKey: publicKey)
            
            // Add to local cache immediately
            encryptionProfiles[deviceID] = encryptionProfile
            
            saveEncryptionProfile(encryptionProfile)
        }
        
        // Load encryption profiles of other devices
        loadEncryptionProfiles()
        
        // Filter grid to show only encryption-enabled devices
        refreshGridForEncryptionMode()
    }
    
    private func disableEncryptionMode() {
        print("GridViewModel: Disabling encryption mode...")
        
        // Update our encryption profile to show disabled
        guard let deviceID = currentUserProfile?.deviceID,
              let publicKey = CryptoService.shared.getPublicKey() else { return }
        let encryptionProfile = EncryptionProfile(deviceID: deviceID, publicKey: publicKey, isEncryptionEnabled: false)
        saveEncryptionProfile(encryptionProfile)
        
        // Refresh grid to show all devices again
        autoRefreshGrid()
    }
    
    private func saveEncryptionProfile(_ profile: EncryptionProfile) {
        let publicDB = CKContainer.default().publicCloudDatabase
        let record = profile.toCKRecord()
        
        // Use CKModifyRecordsOperation to handle both create and update
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys // This allows updating existing records
        
        operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving encryption profile: \(error.localizedDescription)")
                } else {
                    print("Successfully saved/updated encryption profile for device: \(profile.id)")
                }
            }
        }
        
        publicDB.add(operation)
    }
    
    private func loadEncryptionProfiles() {
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "isEncryptionEnabled == 1")  // Use Int64 value
        let query = CKQuery(recordType: "EncryptionProfiles", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("Error loading encryption profiles: \(error.localizedDescription)")
                    return
                }
                
                self.encryptionProfiles.removeAll()
                records?.forEach { record in
                    if let profile = EncryptionProfile(record: record) {
                        self.encryptionProfiles[profile.id] = profile
                    }
                }
                
                print("Loaded \(self.encryptionProfiles.count) encryption profiles")
                self.refreshGridForEncryptionMode()
            }
        }
    }
    
    private func refreshGridForEncryptionMode() {
        if isEncryptionMode {
            // Filter profiles to show only those with encryption enabled
            let encryptedDeviceIDs = Set(encryptionProfiles.keys)
            // Always include current user in encryption mode
            let currentDeviceID = currentUserProfile?.deviceID
            let filteredProfiles = proximityService.activeNearbyProfiles.filter { profile in
                profile.deviceID == currentDeviceID || encryptedDeviceIDs.contains(profile.deviceID)
            }
            updateGridWithAllProfiles(filteredProfiles)
        } else {
            // Show all profiles
            updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        }
    }
    
    // Get encryption profile for a device
    func getEncryptionProfile(for deviceID: String) -> EncryptionProfile? {
        return encryptionProfiles[deviceID]
    }
    
    // Check if there are unread encrypted messages
    func hasUnreadEncryptedMessages() -> Bool {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return false }
        
        // Check for unread encrypted messages sent to current device
        return messages.contains { message in
            message.isEncrypted &&
            message.recipientDeviceID == currentDeviceID &&
            message.senderDeviceID != currentDeviceID &&
            !readReceipts.contains(message.id)
        }
    }
    

    
    // Decrypt message for display
    func decryptMessage(_ message: Message) -> String {
        guard message.isEncrypted,
              let encryptedContentString = message.encryptedContent,
              let encryptedContent = Data(base64Encoded: encryptedContentString),  // Convert from base64 string
              let privateKey = CryptoService.shared.getPrivateKey() else {
            return message.text
        }
        
        if let decryptedText = CryptoService.shared.decrypt(data: encryptedContent, withPrivateKey: privateKey) {
            return decryptedText
        } else {
            return "[Failed to decrypt message]"
        }
    }

    // NEW: Report a user for inappropriate content
    func reportUser(deviceID: String, reason: Report.ReportReason, description: String? = nil) {
        guard let currentUserID = currentUserProfile?.userID,
              let reportedUserID = getUserID(forDeviceID: deviceID) else { 
            print("Error: Missing user IDs for report")
            return 
        }
        
        let report = Report(
            reporterUserID: currentUserID,
            reportedUserID: reportedUserID,
            reportedDeviceID: deviceID,
            reportReason: reason,
            reportDescription: description
        )
        
        let record = report.toCKRecord()
        let publicDB = CKContainer.default().publicCloudDatabase
        
        publicDB.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error submitting report: \(error.localizedDescription)")
                    // TODO: Show user an error alert
                } else {
                    print("Successfully submitted report for user: \(reportedUserID)")
                    // TODO: Show user a success alert
                    
                    // Optionally auto-block the reported user
                    if !self.isBlocked(deviceID) {
                        self.toggleBlock(for: deviceID)
                    }
                }
            }
        }
    }
}