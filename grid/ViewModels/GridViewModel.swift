import Combine
import SwiftUI
import MultipeerConnectivity
import CloudKit

class GridViewModel: ObservableObject {
    @Published var gridNodes: [[GridNode]] = []
    @Published var currentUserProfile: UserProfile?
    @Published var connectedPeersText: String = "Peers: 0"
    @Published var messages: [Message] = [] // For displaying messages
    @Published var currentChatRecipientDeviceID: String? // Device ID of who the current chat is with

    private var networkService: NetworkService
    private var messagingService: MessagingService
    private var gridService: GridService // New: for public grid management
    private var cancellables = Set<AnyCancellable>()
    let gridSize = 5

    init(networkService: NetworkService = NetworkService(), 
         messagingService: MessagingService = MessagingService(),
         gridService: GridService = GridService(),
         initialProfile: UserProfile? = nil) {
        self.networkService = networkService
        self.messagingService = messagingService
        self.gridService = gridService
        self.currentUserProfile = initialProfile
        initializeGrid()
        setupNetworkHandlers()
        setupMessagingHandlers()
        setupGridServiceHandlers()
        
        if let profile = initialProfile {
            saveProfileToPublicGrid(profile)
            placeCurrentUserOnGrid()
            // Fetch messages for this device and subscribe to new ones
            fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
            messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        }
    }

    func setupNetworkHandlers() {
        networkService.onPeerConnected = { [weak self] peerID in
            self?.updateConnectedPeersText()
            if let profile = self?.currentUserProfile {
                self?.networkService.sendUserProfile(profile)
            }
            self?.sendAllMyGridNodes()
        }
        networkService.onPeerDisconnected = { [weak self] peerID in
            self?.updateConnectedPeersText()
            self?.removeUserFromGridByPeerDisplayName(peerID: peerID) 
        }
        networkService.onUserProfileReceived = { [weak self] profile in 
            print("Received profile for device ID \(profile.deviceID) (user: \(profile.userID)) from a peer.")
        }
        networkService.onGridNodeReceived = { [weak self] node in 
            self?.updateGridWithReceivedNode(node: node)
        }
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
    
    private func setupGridServiceHandlers() {
        // Listen for public profile updates and update the grid
        gridService.$allPublicProfiles
            .sink { [weak self] publicProfiles in
                self?.updateGridWithPublicProfiles(publicProfiles)
            }
            .store(in: &cancellables)
    }
    
    private func updateGridWithPublicProfiles(_ profiles: [UserProfile]) {
        // Clear the grid first
        initializeGrid()
        
        guard let currentUserDeviceID = currentUserProfile?.deviceID else {
            // If no current user, just place profiles normally
            for profile in profiles {
                placeProfileOnGrid(profile)
            }
            print("Updated grid with \(profiles.count) public profiles")
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
        
        // Place other profiles in remaining positions
        for profile in otherProfiles {
            placeProfileOnGridSkippingPosition(profile, skipX: 0, skipY: 0)
        }
        
        print("Updated grid with \(profiles.count) public profiles (current user at top-left)")
        objectWillChange.send()
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

    private func updateConnectedPeersText() {
        DispatchQueue.main.async {
            self.connectedPeersText = "Peers: \(self.networkService.connectedPeers.count)"
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
        saveProfileToPublicGrid(profile)
        placeCurrentUserOnGrid()
        networkService.sendUserProfile(profile)
        if let userNode = findNode(forDeviceID: profile.deviceID) {
             networkService.sendGridNodeUpdate(userNode)
        }
        print("Current user profile updated and saved to public grid.")
    }
    
    func setCurrentUserProfile(_ profile: UserProfile) {
        self.currentUserProfile = profile
        saveProfileToPublicGrid(profile) // Save to public grid so everyone can see
        placeCurrentUserOnGrid()
        networkService.sendUserProfile(profile)
        sendAllMyGridNodes()
        print("GridViewModel: Set current user profile for device ID \(profile.deviceID) (user: \(profile.userID))")
        
        // When profile is set (device logs in), fetch their messages and subscribe
        fetchMessagesForCurrentDevice(deviceID: profile.deviceID)
        messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
    }
    
    private func saveProfileToPublicGrid(_ profile: UserProfile) {
        gridService.saveProfileToPublicGrid(profile) { result in
            switch result {
            case .success(let savedProfile):
                print("Successfully saved profile to public grid: \(savedProfile.deviceName)")
            case .failure(let error):
                print("Error saving profile to public grid: \(error.localizedDescription)")
            }
        }
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
        print("Profile data changed. Saving to public grid.")
        saveProfileToPublicGrid(profile) // Save to public grid
        placeCurrentUserOnGrid()
        networkService.sendUserProfile(profile) 
        if let userNode = findNode(forDeviceID: profile.deviceID) {
             networkService.sendGridNodeUpdate(userNode)
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
    
    private func updateGridWithReceivedNode(node: GridNode) {
        if node.x < gridSize && node.y < gridSize && node.x >= 0 && node.y >= 0 {
            if let userProfileInNode = node.userProfile {
                 removeUserFromGrid(deviceID: userProfileInNode.deviceID, exceptAtX: node.x, y: node.y)
            }
            gridNodes[node.x][node.y] = node 
            objectWillChange.send()
            print("Updated grid with node at (\(node.x), \(node.y)) for device ID \(node.userProfile?.deviceID ?? "Unknown")")
        } else {
            print("Received node with out-of-bounds coordinates: (\(node.x), \(node.y))")
        }
    }
    
    private func removeUserFromGrid(deviceID: String, exceptAtX: Int? = nil, y: Int? = nil) {
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if let profileInNode = gridNodes[i][j].userProfile, profileInNode.deviceID == deviceID {
                    if let exceptX = exceptAtX, let exceptY = y, i == exceptX && j == exceptY {
                        continue
                    }
                    gridNodes[i][j].userProfile = nil
                    print("Removed device ID \(profileInNode.deviceID) from (\(i), \(j))")
                }
            }
        }
        objectWillChange.send()
    }

    private func removeUserFromGridByPeerDisplayName(peerID: MCPeerID) {
        print("Peer \(peerID.displayName) disconnected. Note: Relies on MCPeerID.displayName which is not robust for device identification.")
        // This method remains problematic. A robust solution needs a map from MCPeerID to UserProfile.deviceID.
        // For now, no user will be removed based on peerID.displayName to avoid incorrect removals.
        // Consider implementing a handshake that exchanges UserProfile.deviceID upon peer connection.
    }
    
    // MARK: - Messaging Methods

    func selectChatPartner(partnerDeviceID: String) {
        self.currentChatRecipientDeviceID = partnerDeviceID
        print("Selected chat partner device: \(partnerDeviceID)")
    }

    func sendMessage(text: String, to recipientDeviceID: String) {
        guard let senderProfile = currentUserProfile else {
            print("Error: Current user profile not available to send message.")
            return
        }
        
        // Find the recipient's profile to get their userID
        let recipientProfile = findProfileForDevice(deviceID: recipientDeviceID)
        let recipientUserID = recipientProfile?.userID ?? "unknown"
        
        let message = Message(
            senderDeviceID: senderProfile.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: senderProfile.userID,
            recipientUserID: recipientUserID,
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

    func sendAllMyGridNodes() {
        guard let currentDevice = currentUserProfile else { return }
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if let profile = gridNodes[i][j].userProfile, profile.deviceID == currentDevice.deviceID {
                    networkService.sendGridNodeUpdate(gridNodes[i][j])
                }
            }
        }
    }
    
    func findNode(forDeviceID deviceID: String) -> GridNode? {
        for row in gridNodes {
            for node in row {
                if node.userProfile?.deviceID == deviceID {
                    return node
                }
            }
        }
        return nil
    }
    
    func findProfileForDevice(deviceID: String) -> UserProfile? {
        // Check both local grid and public profiles
        for row in gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == deviceID {
                    return profile
                }
            }
        }
        // Also check the gridService public profiles
        return gridService.allPublicProfiles.first { $0.deviceID == deviceID }
    }

    // MARK: - Grid Refresh Methods

    func refreshPublicGrid() {
        print("GridViewModel: Refreshing public grid data")
        gridService.fetchAllPublicProfiles()
    }
} 