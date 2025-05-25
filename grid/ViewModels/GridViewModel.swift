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

class GridViewModel: ObservableObject {
    @Published var gridNodes: [[GridNode]] = []
    @Published var currentUserProfile: UserProfile?
    @Published var messages: [Message] = [] // For displaying messages
    @Published var currentChatRecipientDeviceID: String? // Device ID of who the current chat is with
    @Published var locationPermissionStatus: String = "Location permission not requested"

    private var messagingService: MessagingService
    private var gridService: GridService // For public grid management (legacy)
    private var locationService: LocationService // NEW: Location tracking
    private var proximityService: ProximityService // NEW: Proximity-based user filtering
    private var cancellables = Set<AnyCancellable>()
    let gridSize = 5

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
        
        if let profile = initialProfile {
            updateUserActivityAndLocation(profile)
            placeCurrentUserOnGrid()
            // Fetch messages for this device and subscribe to new ones
            fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
            messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        }
        
        // Request location permission on init
        locationService.requestLocationPermission()
    }
    
    private func setupMessagingHandlers() {
        messagingService.newMessageReceived
            .sink { [weak self] newMessage in
                guard let self = self, let currentDeviceID = self.currentUserProfile?.deviceID else { return }
                
                // Add to messages list if it's for this device (either sender or recipient)
                if newMessage.senderDeviceID == currentDeviceID || newMessage.recipientDeviceID == currentDeviceID {
                    // Avoid duplicates
                    if !self.messages.contains(where: { $0.id == newMessage.id }) {
                        self.messages.append(newMessage)
                        self.messages.sort(by: { $0.timestamp < $1.timestamp })
                        print("New message integrated into ViewModel: \(newMessage.text)")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupLocationHandlers() {
        // Listen for location updates
        locationService.$currentLocation
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
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
                self?.updateGridWithAllProfiles(allProfiles)
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
        
        // Place current user first at position (0, 0)
        if let currentProfile = currentUserProfile {
            gridNodes[0][0].userProfile = currentProfile
            print("Placed current user '\(currentProfile.displayName)' at top-left position (0,0)")
        }
        
        // Place other profiles in remaining positions (sorted by distance if location available)
        for profile in otherProfiles {
            placeProfileOnGridSkippingPosition(profile, skipX: 0, skipY: 0)
        }
        
        print("Updated grid with \(profiles.count) total users (current user at top-left)")
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
        
        // Preload all messages for instant chat access
        print("GridViewModel: Preloading all messages for instant chat access...")
        fetchAllMessagesForCurrentDevice(deviceID: profile.deviceID)
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        
        // Start location updates - grid will auto-refresh when it appears
        locationService.requestLocationPermission()
    }
    
    // Enhanced: Fetch ALL messages for the current device (for all conversations)
    private func fetchAllMessagesForCurrentDevice(deviceID: String) {
        print("GridViewModel: Fetching ALL messages for device \(deviceID) to preload chats...")
        
        messagingService.fetchMessages(forDeviceID: deviceID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fetchedMessages):
                // Store all messages for instant chat access
                self.messages = fetchedMessages.sorted(by: { $0.timestamp < $1.timestamp })
                print("GridViewModel: Preloaded \(self.messages.count) messages for instant chat access")
                
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
                print("GridViewModel: Error preloading messages for device \(deviceID): \(error.localizedDescription)")
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
            print("Error creating CKAsset for profile image: \(error.localizedDescription)")
             try? FileManager.default.removeItem(at: tempFileURL)
        }
    }
    
    private func persistAndUpdateProfileAndGrid() {
        guard let profile = currentUserProfile else { return }
        print("Profile data changed. Updating user activity.")
        updateUserActivityAndLocation(profile) // NEW: Use activity-based saving
        placeCurrentUserOnGrid()
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
        
        guard var profile = currentUserProfile else {
            print("No current user profile for refresh")
            return
        }
        
        // Step 1: Update my location if available
        if let currentLocation = locationService.currentLocation {
            print("Updating my location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
            profile.updateLocation(currentLocation)
            self.currentUserProfile = profile
        } else {
            print("No current location available, refreshing with last known position")
        }
        
        // Step 2: Upload my current status and location to CloudKit
        proximityService.updateUserActivity(profile) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let updatedProfile):
                print("Successfully uploaded my location to CloudKit")
                self.currentUserProfile = updatedProfile
                
                // Step 3: Get all users sorted by distance
                self.proximityService.fetchAllUsers(currentUserLocation: updatedProfile.location)
                
            case .failure(let error):
                print("Error uploading my location: \(error.localizedDescription)")
                // Still try to fetch others even if upload failed
                self.proximityService.fetchAllUsers(currentUserLocation: profile.location)
            }
        }
    }
    
    // Enhanced: Handle app lifecycle events with auto-refresh
    func handleAppDidBecomeActive() {
        guard var profile = currentUserProfile else { return }
        profile.markAsActive()
        self.currentUserProfile = profile
        
        print("App became active - restarting location and auto-refreshing...")
        
        // Restart location updates
        locationService.requestLocationPermission()
        
        // Get current location and immediately share + refresh
        if let currentLocation = locationService.currentLocation {
            profile.updateLocation(currentLocation)
            self.currentUserProfile = profile
            updateUserActivityAndLocation(profile)
            autoRefreshGrid(with: currentLocation)
        } else {
            // Update activity even without new location
            updateUserActivityAndLocation(profile)
            autoRefreshGrid()
        }
    }
    
    func handleAppWillResignActive() {
        guard let profile = currentUserProfile else { return }
        
        // Mark user as inactive in CloudKit
        proximityService.markUserAsInactive(deviceID: profile.deviceID) { result in
            switch result {
            case .success():
                print("Successfully marked user as inactive")
            case .failure(let error):
                print("Error marking user as inactive: \(error.localizedDescription)")
            }
        }
        
        // Stop location updates to save battery
        locationService.stopLocationUpdates()
        
        print("App will resign active - marked user as inactive and stopped location updates")
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
        
        // Find the recipient's profile to get their userID
        guard let recipientProfile = findNode(forDeviceID: recipientDeviceID)?.userProfile else {
            print("Error: Could not find recipient profile for device \(recipientDeviceID)")
            return
        }
        
        let message = Message(
            senderDeviceID: senderProfile.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: senderProfile.userID,
            recipientUserID: recipientProfile.userID,
            text: text
        )
        
        messagingService.sendMessage(message) { [weak self] result in
            switch result {
            case .success(let savedMessage):
                print("Message sent successfully to public database: \(savedMessage.text)")
            case .failure(let error):
                print("Error sending message: \(error.localizedDescription)")
                // TODO: Show error to user
            }
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
        
        // If we already have a profile, immediately update and refresh
        if let profile = currentUserProfile {
            // Get current location and update profile
            if let currentLocation = locationService.currentLocation {
                var updatedProfile = profile
                updatedProfile.updateLocation(currentLocation)
                self.currentUserProfile = updatedProfile
                
                // Share to iCloud immediately
                updateUserActivityAndLocation(updatedProfile)
                
                // Refresh grid
                autoRefreshGrid(with: currentLocation)
            } else {
                // No location yet, just refresh with existing data
                autoRefreshGrid()
            }
        }
    }
}