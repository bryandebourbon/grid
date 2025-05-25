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
        // Listen for active nearby profiles updates
        proximityService.$activeNearbyProfiles
            .sink { [weak self] nearbyProfiles in
                self?.updateGridWithActiveNearbyProfiles(nearbyProfiles)
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
        
        // Update user activity in CloudKit with new location
        updateUserActivityAndLocation(profile)
        
        // Fetch nearby active users with current location
        proximityService.fetchActiveNearbyUsers(currentUserLocation: location)
        
        print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
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
    
    // NEW: Update grid with only active nearby users (sorted by distance)
    private func updateGridWithActiveNearbyProfiles(_ profiles: [UserProfile]) {
        // Clear the grid first
        initializeGrid()
        
        guard let currentUserDeviceID = currentUserProfile?.deviceID else {
            // If no current user, just place profiles normally
            for profile in profiles {
                placeProfileOnGrid(profile)
            }
            print("Updated grid with \(profiles.count) active nearby profiles")
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
        
        // Place other profiles in remaining positions (already sorted by distance)
        for profile in otherProfiles {
            placeProfileOnGridSkippingPosition(profile, skipX: 0, skipY: 0)
        }
        
        print("Updated grid with \(profiles.count) active nearby profiles (current user at top-left)")
        objectWillChange.send()
    }
    
    // LEGACY: Keep for backwards compatibility but prefer proximity-based updates
    private func updateGridWithPublicProfiles(_ profiles: [UserProfile]) {
        // This method is now mainly for fallback when location is not available
        updateGridWithActiveNearbyProfiles(profiles)
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
    
    func fetchMessagesForCurrentDevice(deviceID: String) {
        messagingService.fetchMessages(forDeviceID: deviceID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fetchedMessages):
                // Replace local messages with fetched ones to ensure sync
                self.messages = fetchedMessages.sorted(by: { $0.timestamp < $1.timestamp })
                print("Successfully fetched \(self.messages.count) messages from public database for device \(deviceID)")
            case .failure(let error):
                print("Error fetching messages for device \(deviceID): \(error.localizedDescription)")
                // TODO: Handle error (e.g., show alert to user)
            }
        }
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
        
        // When profile is set (device logs in), fetch their messages and subscribe
        fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
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
    
    // NEW: Grindr-style refresh - upload my location, download others' locations
    func refreshPublicGrid() {
        print("GridViewModel: Starting Grindr-style refresh - upload my location, get others' locations")
        
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
                
                // Step 3: Download nearby users from CloudKit based on my location
                self.proximityService.fetchActiveNearbyUsers(currentUserLocation: updatedProfile.location)
                
            case .failure(let error):
                print("Error uploading my location: \(error.localizedDescription)")
                // Still try to fetch others even if upload failed
                self.proximityService.fetchActiveNearbyUsers(currentUserLocation: profile.location)
            }
        }
    }
    
    // NEW: Handle app lifecycle events
    func handleAppDidBecomeActive() {
        guard var profile = currentUserProfile else { return }
        profile.markAsActive()
        self.currentUserProfile = profile
        updateUserActivityAndLocation(profile)
        
        // Restart location updates
        locationService.requestLocationPermission()
        
        print("App became active - marked user as active and restarted location updates")
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

    // NEW: Enhanced sendMessage with proximity checking
    func sendMessage(text: String, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else {
            print("Error: Current user profile not available to send message.")
            return
        }
        
        // Find the recipient's profile to get their userID and check proximity
        guard let recipientProfile = findNode(forDeviceID: recipientDeviceID)?.userProfile else {
            print("Error: Could not find recipient profile for device \(recipientDeviceID)")
            return
        }
        
        // NEW: Check if messaging is allowed based on proximity
        let messagingCheck = proximityService.canMessage(from: senderProfile, to: recipientProfile)
        if !messagingCheck.allowed {
            print("Messaging not allowed: \(messagingCheck.reason)")
            // TODO: Show alert to user explaining why messaging is blocked
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
}