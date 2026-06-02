import Combine
import SwiftUI
import CloudKit
import CoreLocation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Central grid state; behavior split across `GridViewModel+*.swift` extensions.
@MainActor
class GridViewModel: ObservableObject {
    @Published var gridNodes: [[GridNode]] = []
    @Published var currentUserProfile: UserProfile?
    @Published var messages: [Message] = [] // For displaying messages
    @Published var currentChatRecipientDeviceID: String? // Device ID of who the current chat is with
    @Published var selfChatNewMessageText: String = "" // For SelfChatView input
    @Published var locationPermissionStatus: String = "Location permission not requested"
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
    
    // NEW: Encryption-only messaging properties
    @Published var showingAccountRecreationAlert = false
    @Published var hasUnencryptedMessages = false
    @Published var encryptionProfiles: [String: EncryptionProfile] = [:] // deviceID -> EncryptionProfile
    @Published var hasEncryptionKeys: Bool = false
    
    // Track read receipts
    var readReceipts: Set<String> = [] // Set of messageIDs that have been read
    
    // Track star and block relationships
    var starredUsers: Set<String> = [] // Set of userIDs that are starred
    var blockedUsers: Set<String> = [] // Set of userIDs that are blocked
    var usersWhoBlockedMe: Set<String> = [] // Set of userIDs who have blocked me

    var messagingService: MessagingService
    var locationService: LocationService // NEW: Location tracking
    var proximityService: ProximityService // NEW: Proximity-based user filtering
    let relationshipService: RelationshipService // Star/block persistence
    let encryptionProfileService: EncryptionProfileService // Public-key publishing
    let accountDeletionService: AccountDeletionService // Account record teardown
    let readReceiptService: ReadReceiptService // Read-receipt persistence
    let albumService: AlbumService
    let reportService: ReportService
    private let gridPopulationService = GridPopulationService()
    var cancellables = Set<AnyCancellable>()
    let gridSize = 5 // Max grid size for internal node storage

    init(messagingService: MessagingService = MessagingService(),
         locationService: LocationService = LocationService(),
         proximityService: ProximityService = ProximityService(),
         relationshipService: RelationshipService = RelationshipService(),
         encryptionProfileService: EncryptionProfileService = EncryptionProfileService(),
         accountDeletionService: AccountDeletionService = AccountDeletionService(),
         readReceiptService: ReadReceiptService = ReadReceiptService(),
         albumService: AlbumService = AlbumService(),
         reportService: ReportService = ReportService(),
         initialProfile: UserProfile? = nil) {
        
        self.messagingService = messagingService
        self.locationService = locationService
        self.proximityService = proximityService
        self.relationshipService = relationshipService
        self.encryptionProfileService = encryptionProfileService
        self.accountDeletionService = accountDeletionService
        self.readReceiptService = readReceiptService
        self.albumService = albumService
        self.reportService = reportService
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
                    self.storiesService.loadStoryViewsForViewer(deviceID: profile.deviceID) { [weak self] in
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
                                await self.storiesService.refreshStories()
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

    // Show all users on grid (sorted by distance if location available)
    func updateGridWithAllProfiles(_ profiles: [UserProfile]) {
        let toDisplay = gridPopulationService.profilesToDisplay(
            nearby: profiles,
            currentUser: currentUserProfile,
            demoService: demoService,
            locationService: locationService
        )
        gridPopulationService.layoutProfiles(
            into: &gridNodes,
            profiles: toDisplay,
            currentUser: currentUserProfile,
            display: GridDisplayState(
                showingStarredOnly: showingStarredOnly,
                starredUserIDs: starredUsers,
                blockedUserIDs: blockedUsers,
                usersWhoBlockedMe: usersWhoBlockedMe,
                selectedInterestFilter: selectedInterestFilter,
                isDemoMode: demoService.isDemoMode
            ),
            demoService: demoService
        )
        objectWillChange.send()
    }
    
    // LEGACY: Keep for backwards compatibility but prefer proximity-based updates
    private func updateGridWithPublicProfiles(_ profiles: [UserProfile]) {
        // This method is now mainly for fallback when location is not available
        updateGridWithAllProfiles(profiles)
    }
    
    func placeProfileOnGrid(_ profile: UserProfile) {
        guard let slot = GridPlacementLogic.firstEmptySlot(in: gridNodes) else {
            print("Grid is full! Cannot place device with ID \(profile.deviceID)")
            return
        }
        GridPlacementLogic.place(profile: profile, in: &gridNodes, at: slot.row, col: slot.col)
    }

    func updateUserActivityAndLocation(_ profile: UserProfile) {
        proximityService.updateUserActivity(profile) { result in
            switch result {
            case .success(let updatedProfile):
                print("Successfully updated user activity: \(updatedProfile.deviceName)")
            case .failure(let error):
                print("Error updating user activity: \(error.localizedDescription)")
            }
        }
    }
    
    func placeCurrentUserOnGrid() {
        guard let profile = currentUserProfile else { return }
        GridPlacementLogic.removeProfile(deviceID: profile.deviceID, from: &gridNodes)
        placeProfileOnGrid(profile)
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
        gridNodes = GridPlacementLogic.makeEmptyGrid(size: gridSize)
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
}
