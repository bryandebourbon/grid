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
#if canImport(UIKit)
import UIKit // For UIImage support
#endif

// Explicit imports for project-specific types:
// Ensure these types are accessible (public/internal) and correctly named.

// struct UserProfile is defined in Models/UserProfile.swift
// struct GridViewModel is defined in ViewModels/GridViewModel.swift (contains GridNode)
// struct Message is defined in Models/Message.swift
// struct ChatView is defined in Views/ChatView.swift (if it exists as a separate file)

// Add explicit imports for model types to resolve compilation errors
// These should be available since they're in the same target
// but explicit imports help with clarity and resolve any module issues
// Assuming GridNode is defined in GridViewModel or a similar accessible location.
// Assuming Message is in Models and ChatView is in Views.
// If these paths are incorrect, the build will fail, and we can adjust.

@MainActor
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
    
    // NEW: Interest filtering properties
    @Published var selectedInterestFilter: Set<Interest> = [] {
        didSet {
            // Refresh the grid when interest filter changes
            let profiles = proximityService.activeNearbyProfiles
            updateGridWithAllProfiles(profiles)
        }
    }
    
    // NEW: Interest search properties
    @Published var showingInterestSearch = false
    @Published var searchText = ""
    @Published var filteredInterests: [Interest] = []
    
    // NEW: Privacy and content moderation services
    @Published var privacyService = PrivacyService()
    @Published var contentModerationService = ContentModerationService()
    @Published var showingPrivacyPolicy = false
    
    // NEW: Demo service for promotional screenshots
    @Published var demoService = DemoService()
    
    // NEW: Stories service for story management
    @Published var storiesService = StoriesService()
    
    // NEW: Album management properties
    @Published var userAlbums: [String: Album] = [:] // deviceID -> Album
    private let publicDB = CKContainer.default().publicCloudDatabase
    
    // NEW: Encryption-only messaging properties
    @Published var showingAccountRecreationAlert = false
    @Published var hasUnencryptedMessages = false
    @Published var encryptionProfiles: [String: EncryptionProfile] = [:] // deviceID -> EncryptionProfile
    @Published var hasEncryptionKeys: Bool = false
    
    // Track read receipts
    private var readReceipts: Set<String> = [] // Set of messageIDs that have been read
    
    // Track star and block relationships
    private var starredUsers: Set<String> = [] // Set of userIDs that are starred
    private var blockedUsers: Set<String> = [] // Set of userIDs that are blocked
    private var usersWhoBlockedMe: Set<String> = [] // Set of userIDs who have blocked me

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
        setupPrivacyHandlers()
        
        if let profile = initialProfile {
            updateUserActivityAndLocation(profile)
            placeCurrentUserOnGrid()
            
            // Automatically enable encryption for all users
            enableEncryptionOnlyMode()
            
            // Load encryption profiles first, then other data
            loadEncryptionProfiles { [weak self] in
                guard let self = self else { return }
                
                // After encryption profiles are loaded, load read receipts
                self.loadReadReceipts(forDeviceID: profile.deviceID) { [weak self] in
                    guard let self = self else { return }
                    
                    // Load story views to restore viewed/unviewed state
                    self.loadStoryViews(forDeviceID: profile.deviceID) { [weak self] in
                        guard let self = self else { return }
                        
                        // Load current user's album to restore pin state
                        self.loadCurrentUserAlbum(forDeviceID: profile.deviceID) { [weak self] in
                            guard let self = self else { return }
                            
                            // Finally, fetch messages after all persistent state is loaded
                            self.fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
                            // Check for unencrypted messages after loading
                            self.checkForUnencryptedMessages()
                            
                            // Load stories data
                            Task {
                                await self.refreshStories()
                            }
                        }
                    }
                }
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
                // All messaging is now encrypted by default
                self.updateGridWithAllProfiles(allProfiles)
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
    
    private func setupPrivacyHandlers() {
        // Add any additional setup for privacy handlers if needed
        // This could include setting up notifications, handling privacy policy acceptance, etc.
        // For now, we'll just add a placeholder for these handlers.
        print("GridViewModel: Setting up privacy handlers...")
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
        
        // Get profiles to display - either real users or demo users
        var profilesToDisplay: [UserProfile] = []
        
        if demoService.isDemoMode {
            // In demo mode, generate demo users instead of showing real users
            if let currentLocation = locationService.currentLocation {
                profilesToDisplay = demoService.generateDemoUsers(near: currentLocation, count: 24) // Fill most of the 5x5 grid
                print("GridViewModel: Using \(profilesToDisplay.count) demo users for grid")
            } else {
                // If no location, create demo users around a default location (San Francisco)
                let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                profilesToDisplay = demoService.generateDemoUsers(near: defaultLocation, count: 24)
                print("GridViewModel: Using \(profilesToDisplay.count) demo users with default location")
            }
        } else {
            profilesToDisplay = profiles
        }
        
        // Separate current user from other profiles
        var currentUserProfile: UserProfile?
        var otherProfiles: [UserProfile] = []
        
        for profile in profilesToDisplay {
            if profile.deviceID == currentUserDeviceID {
                currentUserProfile = profile
            } else {
                otherProfiles.append(profile)
            }
        }
        
        // Filter profiles if showing starred only (skip in demo mode)
        if showingStarredOnly && !demoService.isDemoMode {
            otherProfiles = otherProfiles.filter { profile in
                starredUsers.contains(profile.userID)
            }
        }
        
        // Filter out blocked users (skip in demo mode)
        if !demoService.isDemoMode {
            print("DEBUG: Before filtering - blockedUsers.count = \(blockedUsers.count), usersWhoBlockedMe.count = \(usersWhoBlockedMe.count)")
            print("DEBUG: blockedUsers = \(blockedUsers)")
            print("DEBUG: usersWhoBlockedMe = \(usersWhoBlockedMe)")
            
            let beforeCount = otherProfiles.count
            otherProfiles = otherProfiles.filter { profile in
                let iBlockedThem = blockedUsers.contains(profile.userID)
                let theyBlockedMe = usersWhoBlockedMe.contains(profile.userID)
                let shouldFilter = iBlockedThem || theyBlockedMe
                
                if shouldFilter {
                    print("DEBUG: Filtering out user \(profile.userID) - iBlockedThem: \(iBlockedThem), theyBlockedMe: \(theyBlockedMe)")
                }
                
                return !shouldFilter
            }
            let afterCount = otherProfiles.count
            print("DEBUG: After filtering - profiles went from \(beforeCount) to \(afterCount)")
        }
        
        // Filter profiles by selected interests if any are selected
        if !selectedInterestFilter.isEmpty {
            otherProfiles = otherProfiles.filter { profile in
                let sharedInterests = Set(profile.interests).intersection(selectedInterestFilter)
                return !sharedInterests.isEmpty
            }
        }
        
        // Place current user first at position (0, 0)
        if let currentProfile = self.currentUserProfile {
            // Use demo version of current user if demo mode is enabled
            let profileToPlace = demoService.isDemoMode ? 
                (demoService.createDemoCurrentUser(from: currentProfile) ?? currentProfile) : 
                currentProfile
                
            gridNodes[0][0].userProfile = profileToPlace
            print("Placed current user '\(profileToPlace.displayName)' at top-left position (0,0) - Demo mode: \(demoService.isDemoMode)")
        }
        
        // Place other profiles in remaining positions (sorted by distance if location available)
        for profile in otherProfiles {
            placeProfileOnGridSkippingPosition(profile, skipX: 0, skipY: 0)
        }
        
        let filterStatus = showingStarredOnly ? " (starred only)" : ""
        let blockingStatus = demoService.isDemoMode ? " (demo mode)" : " (filtered out \(blockedUsers.count) blocked + \(usersWhoBlockedMe.count) who blocked me)"
        let modeLabel = demoService.isDemoMode ? "demo users" : "real users"
        print("Updated grid with \(otherProfiles.count + 1) total \(modeLabel)\(filterStatus)\(blockingStatus) (current user at top-left)")
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
        
        // Automatically enable encryption for all users
        enableEncryptionOnlyMode()
        
        // Load encryption profiles first, then other data
        loadEncryptionProfiles { [weak self] in
            guard let self = self else { return }
            
                    // Load star/block relationships after encryption profiles
        print("GridViewModel: Loading star/block relationships...")
        self.loadStarBlockRelationships(forUserID: profile.userID) { [weak self] in
            guard let self = self else { return }
            
            // After star/block relationships, load read receipts
            print("GridViewModel: Loading read receipts...")
            self.loadReadReceipts(forDeviceID: profile.deviceID) { [weak self] in
                guard let self = self else { return }
                
                // Load story views to restore viewed/unviewed state
                print("GridViewModel: Loading story views...")
                self.loadStoryViews(forDeviceID: profile.deviceID) { [weak self] in
                    guard let self = self else { return }
                    
                    // Load current user's album to restore pin state
                    print("GridViewModel: Loading user album...")
                    self.loadCurrentUserAlbum(forDeviceID: profile.deviceID) { [weak self] in
                        guard let self = self else { return }
                        
                        // Finally, fetch messages after all persistent state is loaded
                        print("GridViewModel: Preloading all messages for instant chat access...")
                        self.fetchAllMessagesForCurrentDevice(deviceID: profile.deviceID)
                        
                        // Check for unencrypted messages after loading
                        self.checkForUnencryptedMessages()
                        
                        // Load stories data
                        Task {
                            await self.refreshStories()
                        }
                    }
                }
            }
        }
        }
        
        // Subscribe to message changes immediately
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        
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
    
    // NEW: Load star/block relationships from CloudKit (both outgoing and incoming blocks)
    private func loadStarBlockRelationships(forUserID userID: String, completion: @escaping () -> Void = {}) {
        print("📥 ========== LOAD STAR/BLOCK RELATIONSHIPS ==========")
        print("📥 Called for userID: \(userID)")
        print("📥 blockedUsers BEFORE loading: \(blockedUsers)")
        print("📥 blockedUsers.count BEFORE loading: \(blockedUsers.count)")
        
        let publicDB = CKContainer.default().publicCloudDatabase
        
        // Create a dispatch group to wait for both queries
        let dispatchGroup = DispatchGroup()
        
        // Query 1: Get relationships I created (people I starred/blocked)
        dispatchGroup.enter()
        let myRelationshipsPredicate = NSPredicate(format: "userID == %@", userID)
        let myRelationshipsQuery = CKQuery(recordType: "UserRelationships", predicate: myRelationshipsPredicate)
        
        print("📥 Starting CloudKit query for MY relationships...")
        publicDB.perform(myRelationshipsQuery, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                print("📥 CloudKit query for MY relationships completed")
                print("📥 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
                print("📥 Records count: \(records?.count ?? 0)")
                print("📥 Error: \(error?.localizedDescription ?? "none")")
                
                guard let self = self else {
                    print("📥 Self is nil in my relationships completion")
                    dispatchGroup.leave()
                    return
                }
                
                if let error = error {
                    print("📥 ❌ Error loading my star/block relationships: \(error.localizedDescription)")
                } else if let records = records {
                    print("📥 ⚠️ CLEARING existing blockedUsers and starredUsers sets")
                    print("📥 starredUsers before clear: \(self.starredUsers)")
                    print("📥 blockedUsers before clear: \(self.blockedUsers)")
                    
                    // Clear existing and load fresh from CloudKit
                    self.starredUsers.removeAll()
                    self.blockedUsers.removeAll()
                    
                    print("📥 After clearing - starredUsers: \(self.starredUsers)")
                    print("📥 After clearing - blockedUsers: \(self.blockedUsers)")
                    
                    print("📥 Processing \(records.count) relationship records...")
                    for (index, record) in records.enumerated() {
                        if let relationship = UserRelationship(record: record) {
                            print("📥 Record \(index): \(relationship.userID) -> \(relationship.targetUserID) (\(relationship.actionType.rawValue))")
                            switch relationship.actionType {
                            case .star:
                                self.starredUsers.insert(relationship.targetUserID)
                                print("📥 ⭐ Added \(relationship.targetUserID) to starredUsers")
                            case .block:
                                self.blockedUsers.insert(relationship.targetUserID)
                                print("📥 🚫 Added \(relationship.targetUserID) to blockedUsers")
                            case .report:
                                print("📥 📝 Skipping report record")
                                break
                            }
                        } else {
                            print("📥 ❌ Failed to parse relationship from record \(index)")
                        }
                    }
                    
                    print("📥 ✅ Loaded \(self.starredUsers.count) starred users and \(self.blockedUsers.count) blocked users from CloudKit")
                    print("📥 starredUsers: \(self.starredUsers)")
                    print("📥 blockedUsers: \(self.blockedUsers)")
                }
                
                dispatchGroup.leave()
            }
        }
        
        // Query 2: Get relationships where I'm the target (people who blocked me)
        dispatchGroup.enter()
        let blockingMePredicate = NSPredicate(format: "targetUserID == %@ AND actionType == %@", userID, "block")
        let blockingMeQuery = CKQuery(recordType: "UserRelationships", predicate: blockingMePredicate)
        
        print("📥 Starting CloudKit query for users who BLOCKED ME...")
        publicDB.perform(blockingMeQuery, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                print("📥 CloudKit query for users who blocked me completed")
                print("📥 Records count: \(records?.count ?? 0)")
                print("📥 Error: \(error?.localizedDescription ?? "none")")
                
                guard let self = self else {
                    print("📥 Self is nil in blocked me completion")
                    dispatchGroup.leave()
                    return
                }
                
                if let error = error {
                    print("📥 ❌ Error loading users who blocked me: \(error.localizedDescription)")
                } else if let records = records {
                    print("📥 Clearing usersWhoBlockedMe before reload: \(self.usersWhoBlockedMe)")
                    // Clear and reload
                    self.usersWhoBlockedMe.removeAll()
                    
                    for (index, record) in records.enumerated() {
                        if let relationship = UserRelationship(record: record) {
                            self.usersWhoBlockedMe.insert(relationship.userID)
                            print("📥 Record \(index): \(relationship.userID) blocked me")
                        }
                    }
                    
                    print("📥 ✅ Loaded \(self.usersWhoBlockedMe.count) users who have blocked me from CloudKit")
                    print("📥 usersWhoBlockedMe: \(self.usersWhoBlockedMe)")
                }
                
                dispatchGroup.leave()
            }
        }
        
        // Wait for both queries to complete
        dispatchGroup.notify(queue: .main) {
            print("📥 ========== ALL RELATIONSHIP QUERIES COMPLETED ==========")
            print("📥 Final blockedUsers: \(self.blockedUsers)")
            print("📥 Final usersWhoBlockedMe: \(self.usersWhoBlockedMe)")
            print("📥 Refreshing grid to apply loaded filters")
            
            // Refresh the grid to apply blocking filters
            let profiles = self.proximityService.activeNearbyProfiles
            self.updateGridWithAllProfiles(profiles)
            
            // Trigger UI update
            self.objectWillChange.send()
            completion()
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
            deleteStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .star) { success in
                print("Star deletion \(success ? "successful" : "failed") for user: \(targetUserID)")
            }
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
        print("🔄 ========== TOGGLE BLOCK START ==========")
        print("🔄 Called for deviceID: \(deviceID)")
        
        guard let currentUserID = currentUserProfile?.userID,
              let targetUserID = getUserID(forDeviceID: deviceID) else { 
            print("❌ Failed to get currentUserID or targetUserID")
            print("❌ currentUserID: \(currentUserProfile?.userID ?? "nil")")
            print("❌ targetUserID: \(getUserID(forDeviceID: deviceID) ?? "nil")")
            return 
        }
        
        print("🔄 currentUserID: \(currentUserID)")
        print("🔄 targetUserID: \(targetUserID)")
        
        let wasBlocked = blockedUsers.contains(targetUserID)
        print("🔄 wasBlocked: \(wasBlocked)")
        print("🔄 blockedUsers.count BEFORE: \(blockedUsers.count)")
        print("🔄 blockedUsers BEFORE: \(blockedUsers)")
        
        if wasBlocked {
            // Unblock
            print("🔓 ========== UNBLOCKING USER ==========")
            print("🔓 About to remove \(targetUserID) from local blockedUsers set")
            
            let removedUser = blockedUsers.remove(targetUserID)
            print("🔓 blockedUsers.remove() result: \(removedUser != nil ? "SUCCESS" : "FAILED")")
            print("🔓 blockedUsers.count AFTER removal: \(blockedUsers.count)")
            print("🔓 blockedUsers AFTER removal: \(blockedUsers)")
            print("🔓 blockedUsers.contains(\(targetUserID)): \(blockedUsers.contains(targetUserID))")
            
            print("🔓 Calling deleteStarBlockRecord for CloudKit deletion...")
            
            // Wait for CloudKit deletion before refreshing
            deleteStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .block) { [weak self] success in
                print("☁️ ========== CLOUDKIT DELETION COMPLETED ==========")
                print("☁️ deletion success: \(success)")
                print("☁️ Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
                
                guard let self = self else { 
                    print("☁️ Self is nil in completion")
                    return 
                }
                
                DispatchQueue.main.async {
                    print("☁️ Back on main thread")
                    print("☁️ blockedUsers.count in completion: \(self.blockedUsers.count)")
                    print("☁️ blockedUsers in completion: \(self.blockedUsers)")
                    print("☁️ blockedUsers.contains(\(targetUserID)) in completion: \(self.blockedUsers.contains(targetUserID))")
                    
                    if success {
                        print("☁️ ✅ CloudKit deletion successful. Refreshing grid WITHOUT reloading relationships.")
                        self.refreshGridWithCurrentState()
                    } else {
                        print("☁️ ❌ CloudKit deletion failed. Re-adding user to blocked set.")
                        self.blockedUsers.insert(targetUserID)
                        print("☁️ blockedUsers after re-adding: \(self.blockedUsers)")
                        self.refreshGridWithCurrentState()
                    }
                }
            }
        } else {
            // Block
            print("🔒 ========== BLOCKING USER ==========")
            print("🔒 About to add \(targetUserID) to local blockedUsers set")
            
            blockedUsers.insert(targetUserID)
            print("🔒 blockedUsers.count AFTER addition: \(blockedUsers.count)")
            print("🔒 blockedUsers AFTER addition: \(blockedUsers)")
            
            saveStarBlockRecord(userID: currentUserID, targetUserID: targetUserID, actionType: .block)
            print("🔒 Blocked user \(targetUserID). Hiding them from grid.")
            
            // For blocking: Just refresh with current cached list (immediate)
            let profiles = proximityService.activeNearbyProfiles
            updateGridWithAllProfiles(profiles)
        }
        
        print("🔄 Calling objectWillChange.send()")
        objectWillChange.send()
        print("🔄 ========== TOGGLE BLOCK END ==========")
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
    private func deleteStarBlockRecord(userID: String, targetUserID: String, actionType: UserRelationship.ActionType, completion: @escaping (Bool) -> Void = { _ in }) {
        let recordName = "\(userID)_\(targetUserID)_\(actionType.rawValue)"
        let recordID = CKRecord.ID(recordName: recordName)
        
        print("🗑️ ========== DELETING CLOUDKIT RECORD ==========")
        print("🗑️ Record name: \(recordName)")
        print("🗑️ userID: \(userID)")
        print("🗑️ targetUserID: \(targetUserID)")
        print("🗑️ actionType: \(actionType.rawValue)")
        print("🗑️ Starting CloudKit deletion...")
        
        let publicDB = CKContainer.default().publicCloudDatabase
        publicDB.delete(withRecordID: recordID) { deletedRecordID, error in
            print("🗑️ CloudKit deletion callback triggered")
            print("🗑️ Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
            print("🗑️ deletedRecordID: \(deletedRecordID?.recordName ?? "nil")")
            print("🗑️ error: \(error?.localizedDescription ?? "none")")
            
            DispatchQueue.main.async {
                print("🗑️ Back on main thread for completion")
                if let error = error {
                    print("🗑️ ❌ Error deleting \(actionType.rawValue) relationship: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("🗑️ ✅ Successfully deleted \(actionType.rawValue) relationship for user: \(targetUserID)")
                    completion(true)
                }
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
    
    // NEW: Unblock a user by userID (for BlockedUsersView)
    func unblockUser(userID: String) {
        print("🔓 ========== UNBLOCK USER BY USERID ==========")
        print("🔓 Called for userID: \(userID)")
        
        guard let currentUserID = currentUserProfile?.userID else { 
            print("🔓 ❌ No current user profile")
            return 
        }
        
        print("🔓 currentUserID: \(currentUserID)")
        print("🔓 blockedUsers BEFORE: \(blockedUsers)")
        print("🔓 blockedUsers.contains(\(userID)): \(blockedUsers.contains(userID))")
        
        guard blockedUsers.contains(userID) else {
            print("🔓 ❌ User \(userID) is not in blocked list")
            return
        }
        
        // Remove from local blocked set
        let removedUser = blockedUsers.remove(userID)
        print("🔓 Removed user from local set: \(removedUser != nil)")
        print("🔓 blockedUsers AFTER removal: \(blockedUsers)")
        
        // Delete the blocking record from CloudKit
        print("🔓 Calling deleteStarBlockRecord for CloudKit deletion...")
        deleteStarBlockRecord(userID: currentUserID, targetUserID: userID, actionType: .block) { [weak self] success in
            print("🔓 ========== CLOUDKIT DELETION FOR UNBLOCK COMPLETED ==========")
            print("🔓 deletion success: \(success)")
            
            guard let self = self else { 
                print("🔓 Self is nil in completion")
                return 
            }
            
            DispatchQueue.main.async {
                print("🔓 Back on main thread after unblock deletion")
                print("🔓 blockedUsers in completion: \(self.blockedUsers)")
                
                if success {
                    print("🔓 ✅ CloudKit deletion successful. Refreshing grid.")
                    // Force a complete refresh to get the unblocked user back
                    self.forceRefreshGrid()
                } else {
                    print("🔓 ❌ CloudKit deletion failed. Re-adding user to blocked set.")
                    self.blockedUsers.insert(userID)
                    print("🔓 blockedUsers after re-adding: \(self.blockedUsers)")
                }
                
                // Trigger UI update
                self.objectWillChange.send()
            }
        }
    }
    
    // Force refresh the grid by fetching all users again
    func forceRefreshGrid() {
        print("🔄 ========== FORCE REFRESH GRID ==========")
        print("🔄 Current blockedUsers: \(blockedUsers)")
        print("🔄 Current usersWhoBlockedMe: \(usersWhoBlockedMe)")
        print("🔄 Calling proximityService.fetchAllUsers...")
        
        if let currentLocation = locationService.currentLocation {
            print("🔄 Using current location: \(currentLocation.coordinate)")
            proximityService.fetchAllUsers(currentUserLocation: currentLocation)
        } else {
            print("🔄 No current location available, fetching without location")
            proximityService.fetchAllUsers()
        }
    }
    
    // Refresh grid using current local state without fetching from CloudKit
    private func refreshGridWithCurrentState() {
        print("🔄 ========== REFRESH GRID WITH CURRENT STATE ==========")
        print("🔄 blockedUsers.count: \(blockedUsers.count)")
        print("🔄 blockedUsers: \(blockedUsers)")
        print("🔄 usersWhoBlockedMe.count: \(usersWhoBlockedMe.count)")
        print("🔄 usersWhoBlockedMe: \(usersWhoBlockedMe)")
        
        // Use the current cached profiles and apply current blocking filters
        let profiles = proximityService.activeNearbyProfiles
        print("🔄 proximityService.activeNearbyProfiles.count: \(profiles.count)")
        for (index, profile) in profiles.enumerated() {
            print("🔄 Profile \(index): \(profile.displayName) (userID: \(profile.userID))")
        }
        
        print("🔄 Calling updateGridWithAllProfiles with \(profiles.count) profiles")
        updateGridWithAllProfiles(profiles)
        
        // Wait a moment, then do a full refresh to ensure consistency
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔄 ========== DELAYED FULL REFRESH ==========")
            print("🔄 Following up with full refresh to ensure consistency")
            print("🔄 blockedUsers before full refresh: \(self.blockedUsers)")
            self.forceRefreshGrid()
        }
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
        
        // Handle encryption - try to encrypt if profiles are available
        var canEncrypt = false
        
        // For self-messages, use our own public key
        let targetEncryptionProfile: EncryptionProfile?
        if recipientDeviceID == senderProfile.deviceID {
            // Self-message: use our own encryption profile
            targetEncryptionProfile = encryptionProfiles[senderProfile.deviceID]
        } else {
            // Other user: use their encryption profile
            targetEncryptionProfile = encryptionProfiles[recipientDeviceID]
        }
        
        if let encryptionProfile = targetEncryptionProfile,
           let encryptedData = CryptoService.shared.encrypt(text: text, withPublicKey: encryptionProfile.publicKey) {
            // Encryption successful
            optimisticMessage.isEncrypted = true
            optimisticMessage.encryptedContent = encryptedData.base64EncodedString()  // Convert to base64 string
            optimisticMessage.encryptionKeyID = encryptionProfile.id
            optimisticMessage.text = "[Encrypted Message]" // Placeholder for CloudKit
            canEncrypt = true
            print("GridViewModel: Message encrypted for device: \(recipientDeviceID)")
        } else {
            // Encryption failed or no profile available - fall back to unencrypted
            optimisticMessage.isEncrypted = false
            print("GridViewModel: Warning - No encryption profile available for device: \(recipientDeviceID), sending unencrypted message")
            print("Available encryption profiles: \(encryptionProfiles.keys)")
            
            if recipientDeviceID != senderProfile.deviceID {
                print("GridViewModel: Recipient may need to recreate their account to enable encryption")
            }
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

        // 1. Compress image data for encryption to prevent CloudKit size limits
        var processedImageData = imageData
        let maxSizeForEncryption = 400 * 1024 // 400KB limit to leave room for encryption overhead
        
        #if canImport(UIKit)
        if imageData.count > maxSizeForEncryption {
            print("GridViewModel: Image is \(imageData.count) bytes, compressing for encryption...")
            if let uiImage = UIImage(data: imageData) {
                var compressionQuality: CGFloat = 0.8
                while compressionQuality > 0.1 {
                    if let compressedData = uiImage.jpegData(compressionQuality: compressionQuality) {
                        if compressedData.count <= maxSizeForEncryption {
                            processedImageData = compressedData
                            print("GridViewModel: Compressed image from \(imageData.count) to \(compressedData.count) bytes (quality: \(compressionQuality))")
                            break
                        }
                    }
                    compressionQuality -= 0.1
                }
                
                if processedImageData.count > maxSizeForEncryption {
                    print("GridViewModel: Could not compress image enough for encryption, will fall back to unencrypted")
                }
            }
        }
        #endif

        // 2. Create optimistic message first (we'll set the asset after determining encryption)
        let temporaryID = UUID().uuidString
        var optimisticMessage = Message(
            id: temporaryID,
            senderDeviceID: senderProfile.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: senderProfile.userID,
            recipientUserID: recipientProfile.userID,
            text: "", // Empty text for image messages
            timestamp: Date(),
            status: .sending
        )

        // 2. Handle encryption for image data
        var imageAsset: CKAsset? = nil
        var canEncrypt = false
        
        // Determine encryption profile to use
        let targetEncryptionProfile: EncryptionProfile?
        if recipientDeviceID == senderProfile.deviceID {
            // Self-message: use our own encryption profile
            targetEncryptionProfile = encryptionProfiles[senderProfile.deviceID]
        } else {
            // Other user: use their encryption profile
            targetEncryptionProfile = encryptionProfiles[recipientDeviceID]
        }
        
        if let encryptionProfile = targetEncryptionProfile,
           let encryptedImageData = CryptoService.shared.encryptImage(data: processedImageData, withPublicKey: encryptionProfile.publicKey) {
            
            // Check if encrypted + base64 encoded size is reasonable for CloudKit
            let base64EncodedString = encryptedImageData.base64EncodedString()
            let maxCloudKitSize = 800 * 1024 // 800KB limit for safety (CloudKit limit is ~1MB)
            
            if base64EncodedString.count <= maxCloudKitSize {
                // Encryption successful and size is acceptable
                optimisticMessage.isEncrypted = true
                optimisticMessage.encryptedImageData = base64EncodedString
                optimisticMessage.encryptionKeyID = encryptionProfile.id
                optimisticMessage.text = "[Encrypted Image]" // Placeholder for CloudKit
                canEncrypt = true
                print("GridViewModel: Image encrypted for device: \(recipientDeviceID) (final size: \(base64EncodedString.count) bytes)")
                
                // For encrypted images, we don't create a CKAsset - the encrypted data is stored as a string
                imageAsset = nil
            } else {
                print("GridViewModel: Encrypted image still too large for CloudKit (\(base64EncodedString.count) bytes), falling back to unencrypted")
                canEncrypt = false
            }
        } else {
            if processedImageData.count > maxSizeForEncryption {
                print("GridViewModel: Image too large for encryption even after compression, falling back to unencrypted")
            } else if targetEncryptionProfile == nil {
                print("GridViewModel: Warning - No encryption profile available for device: \(recipientDeviceID), sending unencrypted image")
                print("Available encryption profiles: \(encryptionProfiles.keys)")
            } else {
                print("GridViewModel: Image encryption failed for device: \(recipientDeviceID), falling back to unencrypted")
            }
            canEncrypt = false
        }
        
        if !canEncrypt {
            // Encryption failed or not possible - fall back to unencrypted CKAsset
            optimisticMessage.isEncrypted = false
            
            if recipientDeviceID != senderProfile.deviceID {
                print("GridViewModel: Recipient may need to recreate their account to enable image encryption")
            }
            
            // Create CKAsset from unencrypted imageData
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do {
                try imageData.write(to: tempFileURL)
                imageAsset = CKAsset(fileURL: tempFileURL)
            } catch {
                print("Error creating CKAsset for unencrypted image message: \(error.localizedDescription)")
                return
            }
        }
        
        // Set the image asset (nil for encrypted, CKAsset for unencrypted)
        optimisticMessage.imageAsset = imageAsset

        // 3. Add to local messages array immediately
        self.messages.append(optimisticMessage)
        self.messages.sort(by: { $0.timestamp < $1.timestamp })
        print("GridViewModel: Optimistically added \(canEncrypt ? "encrypted" : "unencrypted") image message (TempID: \(temporaryID))")

        // 4. Send to messaging service
        messagingService.sendMessage(optimisticMessage) { [weak self] result in
            guard let self = self else {
                // Clean up temp file if it exists for unencrypted images
                if let asset = imageAsset, let url = asset.fileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }

            guard let optimisticMessageIndex = self.messages.firstIndex(where: { $0.id == temporaryID && $0.status == .sending }) else {
                print("GridViewModel: Could not find optimistic image message (TempID: \(temporaryID)) to update after send attempt.")
                // Clean up temp file if it exists
                if let asset = imageAsset, let url = asset.fileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }
            
            switch result {
            case .success(let savedMessage):
                // Server confirmed, update local message
                self.messages[optimisticMessageIndex].id = savedMessage.id
                self.messages[optimisticMessageIndex].recordID = savedMessage.recordID
                self.messages[optimisticMessageIndex].timestamp = savedMessage.timestamp
                self.messages[optimisticMessageIndex].status = .sent
                self.messages[optimisticMessageIndex].imageAsset = savedMessage.imageAsset // Update with server asset
                print("GridViewModel: Optimistic image message (TempID: \(temporaryID)) confirmed. New ID: \(savedMessage.id)")
                
                // Clean up temp file for unencrypted images
                if let asset = imageAsset, let url = asset.fileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                
            case .failure(let error):
                self.messages[optimisticMessageIndex].status = .failed
                print("GridViewModel: Optimistic image message (TempID: \(temporaryID)) failed to send: \(error.localizedDescription)")
                
                // Clean up temp file for unencrypted images
                if let asset = imageAsset, let url = asset.fileURL {
                    try? FileManager.default.removeItem(at: url)
                }
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

        // 1. Delete UserProfile records (user owns these)
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

        // 2. Delete sent Messages (user owns these)
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

        // 3. Delete UserRelationship records (star/block records user created)
        dispatchGroup.enter()
        let userRelationshipPredicate = NSPredicate(format: "userID == %@", userIDToDelete)
        let userRelationshipQuery = CKQuery(recordType: "UserRelationships", predicate: userRelationshipPredicate)
        
        fetchAndDeleteRecords(database: publicDB, query: userRelationshipQuery, recordTypeForLog: "UserRelationships") { error in
            if let error = error {
                print("GridViewModel: Error deleting UserRelationship records: \(error.localizedDescription)")
                encounteredError = encounteredError ?? error
            }
            dispatchGroup.leave()
        }

        // 4. Delete EncryptionProfile records (user owns these)
        dispatchGroup.enter()
        let encryptionProfilePredicate = NSPredicate(format: "deviceID == %@", currentUserProfile?.deviceID ?? "")
        let encryptionProfileQuery = CKQuery(recordType: "EncryptionProfiles", predicate: encryptionProfilePredicate)
        
        fetchAndDeleteRecords(database: publicDB, query: encryptionProfileQuery, recordTypeForLog: "EncryptionProfiles") { error in
            if let error = error {
                print("GridViewModel: Error deleting EncryptionProfile records: \(error.localizedDescription)")
                encounteredError = encounteredError ?? error
            }
            dispatchGroup.leave()
        }

        // NOTE: We do NOT delete received messages because the user doesn't own those CloudKit records.
        // Received messages are owned by their senders and can only be deleted by them.
        // This prevents the "WRITE operation not permitted" error.

        // Notify when all deletion tasks are complete
        dispatchGroup.notify(queue: .main) {
            if encounteredError == nil {
                print("GridViewModel: Successfully deleted all user-owned records associated with userID: \(userIDToDelete)")
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
    
    private func loadEncryptionProfiles(completion: @escaping () -> Void = {}) {
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "isEncryptionEnabled == 1")  // Use Int64 value
        let query = CKQuery(recordType: "EncryptionProfiles", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let self = self else { 
                    completion()
                    return 
                }
                
                if let error = error {
                    print("Error loading encryption profiles: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                // Don't clear existing profiles, just update/add new ones
                var loadedCount = 0
                records?.forEach { record in
                    if let profile = EncryptionProfile(record: record) {
                        self.encryptionProfiles[profile.id] = profile
                        loadedCount += 1
                    }
                }
                
                print("Loaded \(loadedCount) encryption profiles during initialization")
                self.refreshGridForEncryptionMode()
                completion()
            }
        }
    }
    
    // NEW: Load encryption profiles on-demand for specific device IDs
    private func loadEncryptionProfilesOnDemand(for deviceIDs: [String], completion: @escaping (Bool) -> Void) {
        let publicDB = CKContainer.default().publicCloudDatabase
        
        // Create record IDs for the specific devices we need
        let recordIDs = deviceIDs.map { CKRecord.ID(recordName: "encryption_\($0)") }
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
        fetchOperation.fetchRecordsCompletionBlock = { [weak self] recordsByRecordID, error in
            DispatchQueue.main.async {
                guard let self = self else { 
                    completion(false)
                    return 
                }
                
                if let error = error {
                    print("Error loading encryption profiles on-demand: \(error.localizedDescription)")
                    
                    // Check for partial failures (some profiles found, some not)
                    if let ckError = error as? CKError, ckError.code == .partialFailure {
                        if let partialErrors = ckError.partialErrorsByItemID {
                            var foundProfiles = 0
                            
                            // Process any successfully fetched profiles
                            recordsByRecordID?.forEach { (recordID, record) in
                                if let profile = EncryptionProfile(record: record) {
                                    self.encryptionProfiles[profile.id] = profile
                                    foundProfiles += 1
                                    print("Loaded encryption profile for device: \(profile.id)")
                                }
                            }
                            
                            // Check if we got the profiles we need
                            let hasAllNeeded = deviceIDs.allSatisfy { deviceID in
                                self.encryptionProfiles[deviceID] != nil
                            }
                            
                            print("On-demand load: found \(foundProfiles) profiles, need all: \(hasAllNeeded)")
                            completion(hasAllNeeded)
                        } else {
                            completion(false)
                        }
                    } else {
                        completion(false)
                    }
                    return
                }
                
                // Success case - process all fetched profiles
                var loadedCount = 0
                recordsByRecordID?.forEach { (recordID, record) in
                    if let profile = EncryptionProfile(record: record) {
                        self.encryptionProfiles[profile.id] = profile
                        loadedCount += 1
                        print("Loaded encryption profile for device: \(profile.id)")
                    }
                }
                
                print("Successfully loaded \(loadedCount) encryption profiles on-demand")
                completion(loadedCount > 0)
            }
        }
        
        publicDB.add(fetchOperation)
    }
    
    private func refreshGridForEncryptionMode() {
        // All messaging is now encrypted by default - always filter to show encryption-enabled profiles
        let encryptedDeviceIDs = Set(encryptionProfiles.keys)
        // Always include current user in encryption mode
        let currentDeviceID = currentUserProfile?.deviceID
        let filteredProfiles = proximityService.activeNearbyProfiles.filter { profile in
            // Check encryption requirement
            let hasEncryption = profile.deviceID == currentDeviceID || encryptedDeviceIDs.contains(profile.deviceID)
            
            // Also check blocking status
            let isNotBlocked = profile.deviceID == currentDeviceID || (!blockedUsers.contains(profile.userID) && !usersWhoBlockedMe.contains(profile.userID))
            
            return hasEncryption && isNotBlocked
        }
        updateGridWithAllProfiles(filteredProfiles)
    }
    
    // Get encryption profile for a device
    func getEncryptionProfile(for deviceID: String) -> EncryptionProfile? {
        return encryptionProfiles[deviceID]
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
    
    // Decrypt image for display
    func decryptImageMessage(_ message: Message) -> Data? {
        guard message.isEncrypted,
              let encryptedImageDataString = message.encryptedImageData,
              let encryptedImageData = Data(base64Encoded: encryptedImageDataString),
              let privateKey = CryptoService.shared.getPrivateKey() else {
            return nil
        }
        
        if let decryptedImageData = CryptoService.shared.decryptImage(data: encryptedImageData, withPrivateKey: privateKey) {
            return decryptedImageData
        } else {
            print("Failed to decrypt image message")
            return nil
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
    
    // MARK: - Privacy and Content Moderation Methods
    
    /// Send message with content filtering
    func sendMessageWithModeration(text: String, to recipientDeviceID: String, isEncrypted: Bool = false) {
        // First check content appropriateness
        let moderationResult = contentModerationService.isMessageAppropriate(text)
        
        if !moderationResult.isAppropriate {
            print("Message blocked by content filter: \(moderationResult.reason ?? "Unknown reason")")
            // You could show an alert here to inform the user
            return
        }
        
        // If content is appropriate, send the message normally
        // Note: encryption is handled automatically since all messaging is now encrypted by default
        sendMessage(text: text, to: recipientDeviceID)
        
        // Track the event for analytics (if user has consented)
        privacyService.trackEvent("message_sent", parameters: [
            "recipient_type": recipientDeviceID == currentUserProfile?.deviceID ? "self" : "other",
            "is_encrypted": isEncrypted,
            "message_length": text.count
        ])
    }
    
    /// Update bio with content filtering
    func updateUserProfileBioWithModeration(bio: String, completion: @escaping (Bool, String?) -> Void) {
        // Check bio appropriateness
        let moderationResult = contentModerationService.isBioAppropriate(bio)
        
        if !moderationResult.isAppropriate {
            completion(false, moderationResult.reason)
            return
        }
        
        // If bio is appropriate, update normally
        updateUserProfileBio(bio: bio) { [weak self] success in
            if success {
                self?.privacyService.trackEvent("bio_updated", parameters: [
                    "bio_length": bio.count
                ])
            }
            completion(success, nil)
        }
    }
    
    /// Update profile image with content filtering
    func updateCurrentProfileImageWithModeration(newPhotoData: Data) {
        #if canImport(UIKit)
        // Check image appropriateness
        let moderationResult = contentModerationService.isImageAppropriate(newPhotoData)
        
        if !moderationResult.isAppropriate {
            print("Image blocked by content filter: \(moderationResult.reason ?? "Unknown reason")")
            // You could show an alert here to inform the user
            return
        }
        #endif
        
        // If image is appropriate, update normally
        updateCurrentProfileImage(newPhotoData: newPhotoData)
        
        // Track the event
        privacyService.trackEvent("profile_image_updated", parameters: [
            "image_size_kb": newPhotoData.count / 1024
        ])
    }
    
    /// Report user with automatic content analysis
    func reportUserWithAnalysis(deviceID: String, reason: Report.ReportReason, description: String? = nil) {
        // If there's a description, analyze it for appropriateness
        if let desc = description, !desc.isEmpty {
            let moderationResult = contentModerationService.isTextAppropriate(desc)
            if !moderationResult.isAppropriate {
                print("Report description blocked by content filter")
                return
            }
        }
        
        // Submit the report
        reportUser(deviceID: deviceID, reason: reason, description: description)
        
        // Track the event
        privacyService.trackEvent("user_reported", parameters: [
            "reason": reason.rawValue,
            "has_description": description != nil
        ])
    }
    
    /// Get content moderation summary for admin purposes
    func getContentModerationSummary() -> [String: Any] {
        return [
            "content_filtering_active": true,
            "privacy_policy_version": "1.0"
        ]
    }
    
    // MARK: - Interest Filter Methods
    
    /// Toggle interest filter on/off
    func toggleInterestFilter(_ interest: Interest) {
        if selectedInterestFilter.contains(interest) {
            selectedInterestFilter.remove(interest)
        } else {
            selectedInterestFilter.insert(interest)
        }
    }
    
    /// Remove specific interest from filter
    func removeInterestFilter(_ interest: Interest) {
        selectedInterestFilter.remove(interest)
    }
    
    /// Clear all interest filters
    func clearInterestFilter() {
        selectedInterestFilter.removeAll()
    }
    
    /// Check if interest filter is active
    var hasActiveInterestFilter: Bool {
        return !selectedInterestFilter.isEmpty
    }
    
    /// Get count of users that share interests with current user
    func getSharedInterestCount(with userProfile: UserProfile) -> Int {
        guard let myInterests = currentUserProfile?.interests else { return 0 }
        let sharedInterests = Set(myInterests).intersection(Set(userProfile.interests))
        return sharedInterests.count
    }
    
    /// Get the shared interests between current user and another user
    func getSharedInterests(with userProfile: UserProfile) -> [Interest] {
        guard let myInterests = currentUserProfile?.interests else { return [] }
        let sharedInterests = Set(myInterests).intersection(Set(userProfile.interests))
        return Array(sharedInterests).sorted { $0.rawValue < $1.rawValue }
    }
    
    // MARK: - Encryption-Only Mode Methods
    
    /// Enable encryption for all messaging (called automatically on init)
    private func enableEncryptionOnlyMode() {
        print("GridViewModel: Enabling encryption-only mode...")
        
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
        
        // Note: loadEncryptionProfiles() is now called explicitly in the initialization sequence
    }
    
    /// Check for unencrypted messages that would require account recreation
    private func checkForUnencryptedMessages() {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return }
        
        // Check if user has any unencrypted messages
        hasUnencryptedMessages = messages.contains { message in
            !message.isEncrypted && (message.senderDeviceID == currentDeviceID || message.recipientDeviceID == currentDeviceID)
        }
        
        if hasUnencryptedMessages {
            print("GridViewModel: User has unencrypted messages - account recreation required")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showingAccountRecreationAlert = true
            }
        }
    }
    
    /// Check if user needs to recreate account due to unencrypted messages
    func requiresAccountRecreation() -> Bool {
        return hasUnencryptedMessages
    }

    // Check if there are unread messages (all messages are now encrypted)
    func hasUnreadMessages() -> Bool {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return false }
        
        // Check for unread messages sent to current device
        return messages.contains { message in
            message.recipientDeviceID == currentDeviceID &&
            message.senderDeviceID != currentDeviceID &&
            !readReceipts.contains(message.id)
        }
    }
    
    // MARK: - Stories Management Methods
    
    /// Upload a new story
    func uploadStory(imageData: Data, caption: String? = nil) async throws {
        print("GridViewModel: 📤 Starting story upload process...")
        
        guard let currentProfile = currentUserProfile else {
            print("GridViewModel: ❌ No current user profile available for story upload")
            throw NSError(domain: "GridViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user profile"])
        }
        
        print("GridViewModel: 👤 Uploading story for user: \(currentProfile.userID), device: \(currentProfile.deviceID)")
        print("GridViewModel: 📊 Image data size: \(imageData.count) bytes, Caption: \(caption ?? "none")")
        
        do {
            let story = try await storiesService.uploadStory(
                imageData: imageData,
                caption: caption,
                userID: currentProfile.userID,
                deviceID: currentProfile.deviceID
            )
            print("GridViewModel: ✅ Successfully uploaded story: \(story.id)")
            
            // Refresh the stories to ensure UI is updated
            print("GridViewModel: 🔄 Refreshing stories after upload...")
            await refreshStories()
            
        } catch {
            print("GridViewModel: ❌ Error uploading story: \(error.localizedDescription)")
            print("GridViewModel: ❌ Error details: \(error)")
            throw error
        }
    }
    
    /// Refresh all active stories
    func refreshStories() async {
        print("GridViewModel: 🔄 Refreshing all stories...")
        await storiesService.refreshStories()
        print("GridViewModel: ✅ Stories refresh completed")
    }
    
    /// Get stories for a specific device with unread indicator
    func getStoriesForDevice(_ deviceID: String) async -> (stories: [Story], hasUnviewed: Bool) {
        print("GridViewModel: 🔍 getStoriesForDevice called for deviceID: \(deviceID)")
        
        guard let currentDeviceID = currentUserProfile?.deviceID else {
            print("GridViewModel: ❌ No current user profile available")
            return ([], false)
        }
        
        print("GridViewModel: 👤 Current user deviceID: \(currentDeviceID)")
        print("GridViewModel: 📞 Calling storiesService.getStoriesForDevice...")
        
        let result = await storiesService.getStoriesForDevice(deviceID, viewerDeviceID: currentDeviceID)
        
        print("GridViewModel: 📊 Result: \(result.stories.count) stories, hasUnviewed: \(result.hasUnviewed)")
        
        return result
    }

    /// Check if a device has new/unviewed stories
    func hasUnviewedStories(for deviceID: String) async -> Bool {
        print("GridViewModel: 🔍 hasUnviewedStories called for deviceID: \(deviceID)")
        let result = await getStoriesForDevice(deviceID)
        print("GridViewModel: 📊 hasUnviewedStories result: \(result.hasUnviewed)")
        return result.hasUnviewed
    }

    /// Mark a story as viewed
    func viewStory(_ story: Story) async {
        print("GridViewModel: 👁️ viewStory called for story ID: \(story.id)")
        guard let currentProfile = currentUserProfile else { 
            print("GridViewModel: ❌ No current user profile available for viewStory")
            return 
        }
        
        print("GridViewModel: 📞 Calling storiesService.recordStoryView...")
        await storiesService.recordStoryView(
            storyID: story.id,
            viewerUserID: currentProfile.userID,
            viewerDeviceID: currentProfile.deviceID
        )
        print("GridViewModel: ✅ Story view recorded")
    }
    
    /// Delete a specific story (only for current user's stories)
    func deleteStory(_ story: Story) async {
        guard let currentDeviceID = currentUserProfile?.deviceID,
              story.deviceID == currentDeviceID else {
            print("GridViewModel: Cannot delete story - not owned by current user")
            return
        }
        
        await storiesService.deleteStory(story)
    }
    
    /// Get all active stories for the grid
    func getAllActiveStories() -> [Story] {
        return storiesService.allActiveStories
    }
    
    /// Get current user's stories
    func getMyStories() -> [Story] {
        return storiesService.myStories
    }
    
    /// Check if current user has any active stories
    func hasActiveStories() -> Bool {
        guard let currentDeviceID = currentUserProfile?.deviceID else { 
            print("GridViewModel: hasActiveStories() - No current user device ID")
            return false 
        }
        
        let allStories = storiesService.allActiveStories
        let userStories = allStories.filter { $0.deviceID == currentDeviceID && $0.isValid }
        let hasStories = !userStories.isEmpty
        
        print("GridViewModel: hasActiveStories() for \(currentDeviceID):")
        print("  - Total cached stories: \(allStories.count)")
        print("  - User's valid stories: \(userStories.count)")
        print("  - Has active stories: \(hasStories)")
        
        if !userStories.isEmpty {
            print("  - User's story IDs: \(userStories.map { $0.id })")
        }
        
        return hasStories
    }
    
    /// Check if a specific device has any active stories
    func hasActiveStories(for deviceID: String) -> Bool {
        let allStories = storiesService.allActiveStories
        let deviceStories = allStories.filter { $0.deviceID == deviceID && $0.isValid }
        let hasStories = !deviceStories.isEmpty
        
        print("GridViewModel: hasActiveStories(for: \(deviceID)):")
        print("  - Total cached stories: \(allStories.count)")
        print("  - Device's valid stories: \(deviceStories.count)")
        print("  - Has active stories: \(hasStories)")
        
        return hasStories
    }
    
    /// Check if current user has any active stories (async version with fresh data)
    func hasActiveStoriesAsync() async -> Bool {
        print("GridViewModel: hasActiveStoriesAsync() - Fetching fresh stories data...")
        await refreshStories()
        return hasActiveStories()
    }
    
    /// Check if a specific device has any active stories (async version with fresh data)
    func hasActiveStoriesAsync(for deviceID: String) async -> Bool {
        print("GridViewModel: hasActiveStoriesAsync(for: \(deviceID)) - Fetching fresh stories data...")
        await refreshStories()
        return hasActiveStories(for: deviceID)
    }
    
    /// Get stories grouped by device ID for easier UI handling
    func getStoriesGroupedByDevice() -> [String: [Story]] {
        var grouped: [String: [Story]] = [:]
        
        for story in storiesService.allActiveStories where story.isValid {
            if grouped[story.deviceID] == nil {
                grouped[story.deviceID] = []
            }
            grouped[story.deviceID]?.append(story)
        }
        
        // Sort stories within each device group by timestamp (newest first)
        for deviceID in grouped.keys {
            grouped[deviceID]?.sort { $0.timestamp > $1.timestamp }
        }
        
        return grouped
    }
    
    // MARK: - Album Management
    
    /// Create an album for the current user if they don't have one
    func createAlbumIfNeeded() async -> AlbumResult {
        guard let currentProfile = currentUserProfile else {
            print("GridViewModel: ❌ No current user profile available for album creation")
            return AlbumResult.failure("No current user profile")
        }
        
        // Check if user already has an album
        if let existingAlbum = userAlbums[currentProfile.deviceID] {
            print("GridViewModel: ✅ User already has an album: \(existingAlbum.id)")
            return AlbumResult.success(existingAlbum)
        }
        
        // Create new album
        let album = Album(ownerUserID: currentProfile.userID, ownerDeviceID: currentProfile.deviceID)
        
        print("GridViewModel: 📝 Creating new album: \(album.id) for user: \(currentProfile.deviceID)")
        
        do {
            let record = album.toCKRecord()
            let savedRecord = try await publicDB.save(record)
            
            if let savedAlbum = Album(record: savedRecord) {
                print("GridViewModel: ✅ Album created successfully: \(savedAlbum.id)")
                
                // Update local cache and user profile
                userAlbums[currentProfile.deviceID] = savedAlbum
                await updateUserProfileWithAlbum(savedAlbum)
                
                return AlbumResult.success(savedAlbum)
            } else {
                print("GridViewModel: ❌ Failed to create Album from saved record")
                return AlbumResult.failure("Failed to create album from saved record")
            }
        } catch {
            print("GridViewModel: ❌ Error creating album: \(error.localizedDescription)")
            return AlbumResult.failure(error.localizedDescription)
        }
    }
    
    /// Pin a story to the current user's album
    func pinStoryToAlbum(_ story: Story) async -> PinResult {
        guard let currentProfile = currentUserProfile else {
            print("GridViewModel: ❌ No current user profile for pinning story")
            return PinResult.failure("No current user profile")
        }
        
        // Only allow pinning own stories in Phase 1
        guard story.deviceID == currentProfile.deviceID else {
            print("GridViewModel: ❌ Cannot pin other users' stories in Phase 1")
            return PinResult.failure("Cannot pin other users' stories")
        }
        
        print("GridViewModel: 📌 Attempting to pin story \(story.id) to album")
        
        // Ensure user has an album
        let albumResult = await createAlbumIfNeeded()
        guard albumResult.success, var album = albumResult.album else {
            print("GridViewModel: ❌ Failed to get or create album: \(albumResult.error ?? "Unknown error")")
            return PinResult.failure("Failed to get or create album")
        }
        
        // Check if album is full
        if !album.hasSpace {
            print("GridViewModel: ❌ Album is full (\(Album.maxPhotos) photos maximum)")
            return PinResult.albumFull()
        }
        
        // Check if story is already pinned
        if album.isPhotoPinned(storyID: story.id) {
            print("GridViewModel: ⚠️ Story \(story.id) is already pinned")
            return PinResult.alreadyPinned()
        }
        
        // Create metadata for the pinned photo
        let metadata = PhotoMetadata(
            storyID: story.id,
            originalStoryDate: story.timestamp,
            caption: story.caption
        )
        
        // Add photo to album
        guard let imageAsset = story.imageAsset else {
            print("GridViewModel: ❌ Story has no image asset to pin")
            return PinResult.failure("Story has no image asset")
        }
        
        let added = album.addPhoto(asset: imageAsset, metadata: metadata)
        guard added else {
            print("GridViewModel: ❌ Failed to add photo to album")
            return PinResult.failure("Failed to add photo to album")
        }
        
        // Save updated album to CloudKit
        do {
            let record = album.toCKRecord()
            
            // Use modifyRecords for explicit update operation
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            
            var savedRecord: CKRecord?
            
            return try await withCheckedThrowingContinuation { continuation in
                operation.perRecordSaveBlock = { (recordID: CKRecord.ID, result: Result<CKRecord, Error>) in
                    switch result {
                    case .success(let record):
                        savedRecord = record
                    case .failure(let error):
                        print("GridViewModel: ❌ Error saving individual record: \(error.localizedDescription)")
                    }
                }
                
                operation.modifyRecordsCompletionBlock = { (savedRecords: [CKRecord]?, deletedRecordIDs: [CKRecord.ID]?, error: Error?) in
                    if let error = error {
                        print("GridViewModel: ❌ Error saving album after pinning: \(error.localizedDescription)")
                        continuation.resume(returning: PinResult.failure(error.localizedDescription))
                    } else if let record = savedRecord,
                              let savedAlbum = Album(record: record) {
                        print("GridViewModel: ✅ Successfully pinned story to album")
                        
                        // Update local cache and user profile
                        Task {
                            self.userAlbums[currentProfile.deviceID] = savedAlbum
                            await self.updateUserProfileWithAlbum(savedAlbum)
                        }
                        
                        continuation.resume(returning: PinResult.success())
                    } else {
                        print("GridViewModel: ❌ Failed to create Album from saved record after pinning")
                        continuation.resume(returning: PinResult.failure("Failed to save album changes"))
                    }
                }
                
                publicDB.add(operation)
            }
        } catch {
            print("GridViewModel: ❌ Error saving album after pinning: \(error.localizedDescription)")
            return PinResult.failure(error.localizedDescription)
        }
    }
    
    /// Unpin a story from the current user's album
    func unpinStoryFromAlbum(_ story: Story) async -> PinResult {
        guard let currentProfile = currentUserProfile else {
            print("GridViewModel: ❌ No current user profile for unpinning story")
            return PinResult.failure("No current user profile")
        }
        
        guard var album = userAlbums[currentProfile.deviceID] else {
            print("GridViewModel: ❌ No album found for current user")
            return PinResult.failure("No album found")
        }
        
        print("GridViewModel: 📌 Attempting to unpin story \(story.id) from album")
        
        // Remove photo from album
        let removed = album.removePhoto(storyID: story.id)
        guard removed else {
            print("GridViewModel: ⚠️ Story \(story.id) was not pinned in album")
            return PinResult.failure("Story not found in album")
        }
        
        // Save updated album to CloudKit
        do {
            let record = album.toCKRecord()
            
            // Use modifyRecords for explicit update operation
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            
            var savedRecord: CKRecord?
            
            return try await withCheckedThrowingContinuation { continuation in
                operation.perRecordSaveBlock = { (recordID: CKRecord.ID, result: Result<CKRecord, Error>) in
                    switch result {
                    case .success(let record):
                        savedRecord = record
                    case .failure(let error):
                        print("GridViewModel: ❌ Error saving individual record: \(error.localizedDescription)")
                    }
                }
                
                operation.modifyRecordsCompletionBlock = { (savedRecords: [CKRecord]?, deletedRecordIDs: [CKRecord.ID]?, error: Error?) in
                    if let error = error {
                        print("GridViewModel: ❌ Error saving album after unpinning: \(error.localizedDescription)")
                        continuation.resume(returning: PinResult.failure(error.localizedDescription))
                    } else if let record = savedRecord,
                              let savedAlbum = Album(record: record) {
                        print("GridViewModel: ✅ Successfully unpinned story from album")
                        
                        // Update local cache and user profile
                        Task {
                            self.userAlbums[currentProfile.deviceID] = savedAlbum
                            await self.updateUserProfileWithAlbum(savedAlbum)
                        }
                        
                        continuation.resume(returning: PinResult.success())
                    } else {
                        print("GridViewModel: ❌ Failed to create Album from saved record after unpinning")
                        continuation.resume(returning: PinResult.failure("Failed to save album changes"))
                    }
                }
                
                publicDB.add(operation)
            }
        } catch {
            print("GridViewModel: ❌ Error saving album after unpinning: \(error.localizedDescription)")
            return PinResult.failure(error.localizedDescription)
        }
    }
    
    /// Get album for a specific user
    func getAlbum(for deviceID: String) async -> Album? {
        // Check local cache first
        if let cachedAlbum = userAlbums[deviceID] {
            print("GridViewModel: ✅ Found album in cache for \(deviceID)")
            return cachedAlbum
        }
        
        print("GridViewModel: 🔍 Fetching album from CloudKit for \(deviceID)")
        
        // Fetch from CloudKit
        let predicate = NSPredicate(format: "ownerDeviceID == %@", deviceID)
        let query = CKQuery(recordType: "Albums", predicate: predicate)
        
        do {
            let result = try await publicDB.records(matching: query)
            let records = result.matchResults.compactMap { try? $0.1.get() }
            
            if let record = records.first, let album = Album(record: record) {
                print("GridViewModel: ✅ Found album in CloudKit for \(deviceID)")
                userAlbums[deviceID] = album
                return album
            } else {
                print("GridViewModel: ❌ No album found in CloudKit for \(deviceID)")
                return nil
            }
        } catch {
            print("GridViewModel: ❌ Error fetching album from CloudKit: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Check if a story is pinned in current user's album
    func isStoryPinned(_ storyID: String) -> Bool {
        guard let currentProfile = currentUserProfile else {
            return false
        }
        
        guard let album = userAlbums[currentProfile.deviceID] else {
            return false
        }
        
        return album.isPhotoPinned(storyID: storyID)
    }
    
    /// Get current user's album
    func getCurrentUserAlbum() async -> Album? {
        guard let currentProfile = currentUserProfile else {
            return nil
        }
        
        return await getAlbum(for: currentProfile.deviceID)
    }
    
    /// Load albums for all nearby users (for preview display)
    func loadNearbyUsersAlbums() async {
        print("GridViewModel: 🔄 Loading albums for nearby users")
        
        let nearbyDeviceIDs = proximityService.activeNearbyProfiles.map { $0.deviceID }
        
        for deviceID in nearbyDeviceIDs {
            if userAlbums[deviceID] == nil {
                _ = await getAlbum(for: deviceID)
            }
        }
        
        print("GridViewModel: ✅ Finished loading albums for nearby users")
    }
    
    /// Update user profile with album information
    private func updateUserProfileWithAlbum(_ album: Album) async {
        guard var currentProfile = currentUserProfile else { return }
        
        // Update profile with album info
        currentProfile.updateAlbumInfo(albumID: album.id, previewPhotos: album.previewPhotos)
        
        // Save updated profile to CloudKit using CKModifyRecordsOperation for explicit update
        do {
            let record = currentProfile.toPublicCKRecord()
            
            // Use CKModifyRecordsOperation to handle both create and update
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys // This allows updating existing records
            operation.qualityOfService = .userInitiated
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.perRecordSaveBlock = { (recordID: CKRecord.ID, result: Result<CKRecord, Error>) in
                    switch result {
                    case .success(_):
                        break // Success handled in completion block
                    case .failure(let error):
                        print("GridViewModel: ❌ Error saving individual profile record: \(error.localizedDescription)")
                    }
                }
                
                operation.modifyRecordsCompletionBlock = { (savedRecords: [CKRecord]?, deletedRecordIDs: [CKRecord.ID]?, error: Error?) in
                    if let error = error {
                        print("GridViewModel: ❌ Error updating user profile with album info: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                        print("GridViewModel: ✅ Updated user profile with album info")
                        continuation.resume()
                    }
                }
                
                publicDB.add(operation)
            }
            
            // Update local profile
            self.currentUserProfile = currentProfile
            
        } catch {
            print("GridViewModel: ❌ Error updating user profile with album info: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Initialization Helpers
    
    /// Load story views from CloudKit on app startup
    private func loadStoryViews(forDeviceID deviceID: String, completion: @escaping () -> Void = {}) {
        print("GridViewModel: 📖 Loading story views for device: \(deviceID)")
        
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "viewerDeviceID == %@", deviceID)
        let query = CKQuery(recordType: "StoryViews", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion()
                    return
                }
                
                if let error = error {
                    print("GridViewModel: ❌ Error loading story views: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                var loadedViews: [String: [StoryView]] = [:]
                var totalViewsLoaded = 0
                
                records?.forEach { record in
                    if let storyView = StoryView(record: record) {
                        if loadedViews[storyView.storyID] == nil {
                            loadedViews[storyView.storyID] = []
                        }
                        loadedViews[storyView.storyID]?.append(storyView)
                        totalViewsLoaded += 1
                    }
                }
                
                // Update the stories service with loaded views
                Task { @MainActor in
                    for (storyID, views) in loadedViews {
                        self.storiesService.storyViews[storyID] = views
                    }
                    print("GridViewModel: ✅ Loaded \(totalViewsLoaded) story views for \(loadedViews.keys.count) stories")
                    completion()
                }
            }
        }
    }
    
    /// Load current user's album from CloudKit on app startup
    private func loadCurrentUserAlbum(forDeviceID deviceID: String, completion: @escaping () -> Void = {}) {
        print("GridViewModel: 📁 Loading album for device: \(deviceID)")
        
        Task {
            if let album = await getAlbum(for: deviceID) {
                print("GridViewModel: ✅ Loaded album \(album.id) with \(album.photosCount) photos")
            } else {
                print("GridViewModel: ℹ️ No album found for device: \(deviceID)")
            }
            
            await MainActor.run {
                completion()
            }
        }
    }
}