import Combine
import SwiftUI // For Color, if you add it to UserProfile
import MultipeerConnectivity // Import MultipeerConnectivity
import CloudKit // Added for CKAsset

class GridViewModel: ObservableObject {
    @Published var gridNodes: [[GridNode]] = []
    // UserProfile used here should be the one from Models/UserProfile.swift
    // It should be consistent with the one used in ContentView (CloudKit backed)
    @Published var currentUserProfile: UserProfile? // Ensure this is the correct UserProfile type
    @Published var connectedPeersText: String = "Peers: 0" // For UI display

    private var networkService: NetworkService 
    let gridSize = 5 // Example grid size (5x5)

    // Consider passing the initial UserProfile if available after sign-in
    init(networkService: NetworkService = NetworkService(), initialProfile: UserProfile? = nil) {
        self.networkService = networkService
        self.currentUserProfile = initialProfile
        initializeGrid()
        setupNetworkHandlers()
        
        if initialProfile != nil {
            placeCurrentUserOnGrid() // Place initial user if provided
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
            self?.removeUserFromGridByPeerDisplayName(peerID: peerID) // Changed method name for clarity
        }

        networkService.onUserProfileReceived = { [weak self] profile in // profile is UserProfile
            // This is when we receive a profile from another peer
            // We might want to update our grid if this user is on it, or add them if new.
            // For now, let's assume onGridNodeReceived will handle their placement.
            print("Received profile for user ID \(profile.userID) from a peer.")
            // Potentially store this profile in a list of known remote users if needed
        }

        networkService.onGridNodeReceived = { [weak self] node in // node is GridNode
            self?.updateGridWithReceivedNode(node: node)
        }
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
                // GridNode's userProfile property expects UserProfile from Models/
                row.append(GridNode(id: UUID(), x: i, y: j, userProfile: nil))
            }
            gridNodes.append(row)
        }
    }

    // REVIEW: This method's role needs clarification in a CloudKit world.
    // It seems to create a local user profile, which might conflict with the one from Apple Sign-In.
    // If currentUserProfile is set from ContentView after CloudKit sync, this might be for local edits.
    func updateCurrentUsername(newUsername: String) {
        guard currentUserProfile != nil else {
            print("Cannot update username, currentUserProfile is nil.")
            return
        }
        
        // Note: UserProfile uses userID (Apple Sign-In UUID) as identifier, not username
        // The userID should not be changed after Apple Sign-In
        
        guard let profile = currentUserProfile else { return }

        placeCurrentUserOnGrid() // Re-place or update user on the grid with new info
        networkService.sendUserProfile(profile) // Send updated profile
        
        // Also send updated grid node for the current user
        if let userNode = findNode(forUser: profile.userID) { // Use userID
             networkService.sendGridNodeUpdate(userNode)
        }
        // TODO: Persist currentUserProfile changes to CloudKit via ContentView or a dedicated manager
        print("Current user profile updated. TODO: Sync with CloudKit.")
    }
    
    // Sets the main user profile for this ViewModel, e.g., after login and CloudKit fetch
    func setCurrentUserProfile(_ profile: UserProfile) {
        self.currentUserProfile = profile
        placeCurrentUserOnGrid()
        networkService.sendUserProfile(profile) // Announce profile to peers
        sendAllMyGridNodes() // Announce my grid presence
        print("GridViewModel: Set current user profile for ID \(profile.userID)")
    }

    // Method to update the current user's profile image
    func updateCurrentProfileImage(newPhotoData: Data?) {
        guard currentUserProfile != nil else {
            print("Cannot update profile image, currentUserProfile is nil.")
            return
        }

        guard let photoData = newPhotoData else {
            // If nil is passed, it means remove the photo
            currentUserProfile?.profileImage = nil
            print("Profile image removed.")
            // Proceed to save/sync this change
            persistAndUpdateProfileAndGrid()
            return
        }

        // Create a temporary file URL for the CKAsset
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")

        do {
            try photoData.write(to: tempFileURL)
            let photoAsset = CKAsset(fileURL: tempFileURL)
            currentUserProfile?.profileImage = photoAsset
            print("Profile image updated. TODO: Clean up temp file: \(tempFileURL.path) after CloudKit sync.")
            
            // This temp file (tempFileURL) should be cleaned up after the CKRecord containing this CKAsset is successfully saved to CloudKit.
            // The cleanup logic is usually in the completion handler of the CloudKit save operation.
            // For now, we just update the local model. The actual CloudKit save should be triggered by ContentView observing currentUserProfile.

            persistAndUpdateProfileAndGrid()

        } catch {
            print("Error creating CKAsset for profile image: \(error.localizedDescription)")
            // Optionally, remove the partially written temp file if error occurred during write
             try? FileManager.default.removeItem(at: tempFileURL)
        }
    }
    
    private func persistAndUpdateProfileAndGrid() {
        guard let profile = currentUserProfile else { return }

        // TODO: Trigger CloudKit save for currentUserProfile.
        // This would typically be done by ContentView observing changes to gridViewModel.currentUserProfile
        // or by calling a delegate method to inform ContentView that the profile needs saving.
        print("Profile data changed. Application needs to persist this to CloudKit.")

        placeCurrentUserOnGrid()
        networkService.sendUserProfile(profile) 
        
        if let userNode = findNode(forUser: profile.userID) {
             networkService.sendGridNodeUpdate(userNode)
        }
    }

    private func placeCurrentUserOnGrid() {
        guard let profile = currentUserProfile else { return } // profile is UserProfile

        // Remove current user from any previous position
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Compare using userID
                if gridNodes[i][j].userProfile?.userID == profile.userID {
                    gridNodes[i][j].userProfile = nil
                }
            }
        }

        var placed = false
        outerLoop: for i in 0..<gridSize {
            for j in 0..<gridSize {
                if gridNodes[i][j].userProfile == nil {
                    gridNodes[i][j].userProfile = profile // Assign the UserProfile object
                    placed = true
                    break outerLoop
                }
            }
        }
        if !placed {
            print("Grid is full! Cannot place user with ID \(profile.userID)")
        }
        objectWillChange.send() // Notify observers of grid changes
    }

    // This function is less relevant if onGridNodeReceived handles all placements of remote users.
    // It was trying to place a user just based on UserProfile info without coordinates.
    /* 
    private func updateGridWithUserProfile(profile: UserProfile) {
        print("Received profile for \(profile.username), relying on GridNode update for placement.")
        objectWillChange.send()
    }
    */
    
    private func updateGridWithReceivedNode(node: GridNode) { // node is GridNode, node.userProfile is UserProfile?
        if node.x < gridSize && node.y < gridSize && node.x >= 0 && node.y >= 0 {
            if let userProfileInNode = node.userProfile { // userProfileInNode is UserProfile
                 removeUserFromGrid(userID: userProfileInNode.userID, exceptAtX: node.x, y: node.y)
            }
            // GridNode.userProfile expects UserProfile from Models/
            gridNodes[node.x][node.y] = node 
            objectWillChange.send()
            print("Updated grid with node at (\(node.x), \(node.y)) for user ID \(node.userProfile?.userID ?? "Unknown")")
        } else {
            print("Received node with out-of-bounds coordinates: (\(node.x), \(node.y))")
        }
    }
    
    // userID is String (Apple User ID)
    private func removeUserFromGrid(userID: String, exceptAtX: Int? = nil, y: Int? = nil) {
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Compare using userID
                if let profileInNode = gridNodes[i][j].userProfile, profileInNode.userID == userID {
                    if let exceptX = exceptAtX, let exceptY = y, i == exceptX && j == exceptY {
                        continue
                    }
                    gridNodes[i][j].userProfile = nil
                    print("Removed user ID \(profileInNode.userID) from (\(i), \(j))")
                }
            }
        }
        objectWillChange.send()
    }

    // Renamed for clarity, still relies on MCPeerID.displayName which is not robust
    private func removeUserFromGridByPeerDisplayName(peerID: MCPeerID) {
        print("Peer \(peerID.displayName) disconnected. Attempting to remove from grid by display name (Note: fragile method).")
        var userRemoved = false
        // This logic is problematic as displayName is not a reliable unique ID tied to UserProfile.userID
        // We need a mapping from MCPeerID to UserProfile.userID for robust removal.
        // For now, iterating and trying to match is a placeholder.
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if let profile = gridNodes[i][j].userProfile, profile.userID == peerID.displayName { // Very unlikely to match correctly
                    print("Removing user with ID \(profile.userID) (matching disconnected peer \(peerID.displayName)) from (\(i), \(j))")
                    gridNodes[i][j].userProfile = nil
                    userRemoved = true
                }
            }
        }
        if userRemoved {
            objectWillChange.send()
        }
    }

    // userID is String (Apple User ID)
    func findNode(forUser userID: String) -> GridNode? {
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                // Compare using userID
                if gridNodes[i][j].userProfile?.userID == userID {
                    return gridNodes[i][j]
                }
            }
        }
        return nil
    }
    
    func sendAllMyGridNodes() {
        guard let currentUserID = currentUserProfile?.userID else { return } // Use userID
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if let profile = gridNodes[i][j].userProfile, profile.userID == currentUserID { // Use userID
                    networkService.sendGridNodeUpdate(gridNodes[i][j])
                    break // Assuming current user is in only one spot
                }
            }
        }
    }
} 