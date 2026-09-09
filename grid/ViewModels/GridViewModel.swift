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
    @Published var allGridNodes: [[GridNode]] = []
    @Published var favoriteGridNodes: [[GridNode]] = []
    @Published var currentUserProfile: UserProfile?
    @Published var messages: [Message] = [] // For displaying messages
    @Published var currentChatRecipientDeviceID: String? // Device ID of who the current chat is with
    @Published var chatOverlaySession = ChatOverlaySession()
    @Published var uiTestOpenedPartner = "none"
    var locksGridToFixtures = false
    var senderProfileFetchesInFlight = Set<String>()
    @Published var locationPermissionStatus: String = "Location permission not requested"
    @Published var needsLocationOnboarding = false
    let sessionStartedAt = Date()
    var shouldRefreshGridOnNextLocation = false
    @Published var pendingChatNavigationDeviceID: String? = nil // For deferred navigation
    @Published var selectedUserProfileForReport: ProfileCardUser? = nil // For report dialog
    
    // Interest filtering properties
    @Published var selectedInterestFilter: Set<Interest> = [] {
        didSet {
            // Refresh the grid when interest filter changes
            let profiles = proximityService.activeNearbyProfiles
            updateGridWithAllProfiles(profiles)
        }
    }
    @Published var lastTappedInterest: Interest?
    @Published var showsLocalLLM = LocalLLMIdentity.isEnabled()
    @Published var showsSelfOnGrid = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "grid.showSelfOnGrid") == nil {
            return true
        }
        return defaults.bool(forKey: "grid.showSelfOnGrid")
    }()
    @Published var showsHiddenPeople = false

    @Published var peopleTab: GridPeopleTab = .all {
        didSet {
            if case .favorites = peopleTab {
                peopleTab = .all
                return
            }
            guard oldValue != peopleTab else { return }
            gridNodes = nodes(for: peopleTab)
        }
    }
    @Published var customGroups: [PeopleGroup] = []
    @Published var customGroupNodes: [UUID: [[GridNode]]] = [:]
    @Published var interestPages: [Interest] = []
    @Published var interestGridNodes: [String: [[GridNode]]] = [:]
    @Published var interestPins: [String: [String]] = [:]
    @Published var hiddenConversations: [String: Date] = [:]
    @Published var pendingStarDeviceID: String?
    
    // NEW: Interest search properties
    @Published var showingInterestSearch = false
    @Published var searchText = ""
    @Published var filteredInterests: [Interest] = []
    
    // NEW: Privacy and content moderation services
    @Published var privacyService = PrivacyService()
    @Published var contentModerationService = ContentModerationService()
    @Published var showingPrivacyPolicy = false
    @Published var showingTermsOfUse = false
    @Published var userFacingAlert: String?

    /// Avoid re-decrypting the same message every time a chat row re-renders.
    var decryptedTextCache: [String: String] = [:]
    var decryptedImageCache: [String: Data] = [:]
    var failedDecryptIDs: Set<String> = []
    var isFetchingAllMessages = false
    var albumRefreshInFlight = Set<String>()

    func presentUserFacingAlert(_ message: String) {
        userFacingAlert = message
    }
    
    // Stories service for story management
    @Published var storiesService = StoriesService()
    
    // NEW: Album management properties
    @Published var userAlbums: [String: Album] = [:] // deviceID -> Album
    
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
    let sharedInterestService: SharedInterestService
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
         sharedInterestService: SharedInterestService = SharedInterestService(),
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
        self.sharedInterestService = sharedInterestService
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
            bootstrapSession(for: profile)
            loadCustomGroups()
            loadInterestPages()
            loadInterestPins()
            loadHiddenConversations()
            messagingService.subscribeToMessageChanges(forDeviceID: profile.deviceID)
        }
        
        needsLocationOnboarding = LocationOnboardingLogic.shouldShowWelcome(
            status: locationService.authorizationStatus
        )
    }

    func displayState(
        memberUserIDs: Set<String>,
        membersOnly: Bool,
        interestFilter: Set<Interest> = []
    ) -> GridDisplayState {
        GridDisplayState(
            blockedUserIDs: blockedUsers,
            usersWhoBlockedMe: usersWhoBlockedMe,
            selectedInterestFilter: interestFilter,
            starredUserIDs: memberUserIDs,
            favoritesOnly: membersOnly,
            showsLocalLLM: showsLocalLLM && hasLocationAccess,
            showsSelfOnGrid: showsSelfOnGrid && hasLocationAccess,
            showsNearbyPeople: hasLocationAccess
        )
    }

    var hasLocationAccess: Bool {
        locksGridToFixtures || LocationOnboardingLogic.shouldShowNearbyPeople(
            status: locationService.authorizationStatus
        )
    }

    var locationEnableButtonTitle: String {
        LocationOnboardingLogic.enableButtonTitle(for: locationService.authorizationStatus)
    }

    var orderedPeopleTabs: [GridPeopleTab] {
        GridPeopleTabPaging.orderedTabs(customGroups: customGroups, interestPages: interestPages)
    }

    var canAddInterestPage: Bool {
        InterestPageStore.canAdd(to: interestPages)
    }

    var hasMultipleStarGroups: Bool {
        !customGroups.isEmpty
    }

    func nodes(for tab: GridPeopleTab) -> [[GridNode]] {
        switch tab {
        case .all: return allGridNodes
        case .favorites: return favoriteGridNodes
        case .custom(let id): return customGroupNodes[id] ?? []
        case .interest(let raw): return interestGridNodes[raw] ?? []
        }
    }

    func loadCustomGroups() {
        guard let userID = currentUserProfile?.userID else { return }
        customGroups = PeopleGroupStore.load(userID: userID)
        if !customGroups.isEmpty {
            updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        }
    }

    func persistCustomGroups() {
        guard let userID = currentUserProfile?.userID else { return }
        PeopleGroupStore.save(customGroups, userID: userID)
    }

    func loadInterestPages() {
        guard let userID = currentUserProfile?.userID else { return }
        interestPages = InterestPageStore.load(userID: userID)
        if !interestPages.isEmpty {
            updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        }
    }

    func persistInterestPages() {
        guard let userID = currentUserProfile?.userID else { return }
        InterestPageStore.save(interestPages, userID: userID)
    }

    func loadInterestPins() {
        guard let userID = currentUserProfile?.userID else { return }
        interestPins = CategoryPinStore.load(userID: userID)
    }

    func persistInterestPins() {
        guard let userID = currentUserProfile?.userID else { return }
        CategoryPinStore.save(interestPins, userID: userID)
    }

    func loadHiddenConversations() {
        guard let userID = currentUserProfile?.userID else { return }
        hiddenConversations = HiddenConversationStore.load(userID: userID)
    }

    func persistHiddenConversations() {
        guard let userID = currentUserProfile?.userID else { return }
        HiddenConversationStore.save(hiddenConversations, userID: userID)
    }

    func openInterestPage(_ interest: Interest) {
        let alreadyOpen = InterestPageStore.contains(interest, in: interestPages)
        let nextPages = InterestPageStore.inserting(interest, into: interestPages)
        if !alreadyOpen && nextPages.count == interestPages.count {
            showingInterestSearch = false
            return
        }
        interestPages = nextPages
        persistInterestPages()
        lastTappedInterest = interest
        showingInterestSearch = false
        registerForInterest(interest)
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        peopleTab = .interest(interest.rawValue)
    }

    func registerForInterest(_ interest: Interest) {
        guard let profile = currentUserProfile else { return }
        let next = InterestPageStore.inserting(interest, into: profile.interests)
        guard next.count != profile.interests.count else { return }
        updateUserProfileInterests(interests: next) { _ in }
    }

    func unregisterFromInterest(_ interest: Interest) {
        let remainingPages = InterestPageStore.removing(interest, from: interestPages)
        interestPages = remainingPages
        persistInterestPages()
        interestPins = interestPins.filter { key, _ in
            remainingPages.contains {
                $0.rawValue.compare(key, options: .caseInsensitive) == .orderedSame
            }
        }
        persistInterestPins()
        if case .interest(let raw) = peopleTab,
           raw.compare(interest.rawValue, options: .caseInsensitive) == .orderedSame {
            peopleTab = .all
        }
        if let profile = currentUserProfile {
            let next = InterestPageStore.removing(interest, from: profile.interests)
            if next.count != profile.interests.count {
                updateUserProfileInterests(interests: next) { _ in }
            } else {
                updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
            }
        } else {
            updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        }
    }

    @discardableResult
    func addCustomGroup(named rawName: String) -> PeopleGroup? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let group = PeopleGroup(name: name)
        customGroups.append(group)
        persistCustomGroups()
        peopleTab = .custom(group.id)
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        return group
    }

    func requestStar(for deviceID: String) {
        if peopleTab == .all, hasMultipleStarGroups {
            pendingStarDeviceID = deviceID
            return
        }
        toggleFavoriteInCurrentCategory(for: deviceID)
    }

    func pinnedUserIDs(for tab: GridPeopleTab) -> Set<String> {
        switch tab {
        case .all, .favorites:
            return starredUsers
        case .interest(let raw):
            return Set(interestPinIDs(for: raw))
        case .custom(let id):
            return customGroups.first(where: { $0.id == id })?.memberUserIDs ?? []
        }
    }

    func visibleUserIDs(for tab: GridPeopleTab) -> Set<String>? {
        switch tab {
        case .all:
            return nil
        case .favorites:
            return starredUsers
        case .interest(let raw):
            let interest = Interest(rawValue: raw)
            return Set(knownProfiles().compactMap { profile in
                let matches = profile.interests.contains {
                    $0.rawValue.compare(interest.rawValue, options: .caseInsensitive) == .orderedSame
                }
                return matches ? profile.userID : nil
            })
        case .custom(let id):
            return customGroups.first(where: { $0.id == id })?.memberUserIDs ?? []
        }
    }

    func isFavoritedInCurrentCategory(_ deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return pinnedUserIDs(for: peopleTab).contains(userID)
    }

    func toggleFavoriteInCurrentCategory(for deviceID: String) {
        switch peopleTab {
        case .all, .favorites:
            toggleStar(for: deviceID)
        case .interest(let raw):
            toggleInterestPin(deviceID: deviceID, interestRaw: raw)
        case .custom(let id):
            toggleMembership(deviceID: deviceID, groupID: id)
        }
    }

    func hideConversation(with deviceID: String, unpin: Bool = true) {
        hiddenConversations[deviceID] = Date()
        persistHiddenConversations()
        if unpin {
            removePinInCurrentCategory(deviceID: deviceID)
        }
        if chatOverlaySession.activePartnerDeviceID == deviceID {
            hideChatOverlay()
        }
        objectWillChange.send()
    }

    func blockConversation(with deviceID: String) {
        hideConversation(with: deviceID, unpin: false)
        removePinsEverywhere(deviceID: deviceID)
        if isBlocked(deviceID) == false {
            toggleBlock(for: deviceID)
        }
    }

    func isInCustomGroup(_ groupID: UUID, deviceID: String) -> Bool {
        guard let userID = getUserID(forDeviceID: deviceID) else { return false }
        return customGroups.first(where: { $0.id == groupID })?.memberUserIDs.contains(userID) == true
    }

    func toggleMembership(deviceID: String, groupID: UUID) {
        guard let userID = getUserID(forDeviceID: deviceID),
              let index = customGroups.firstIndex(where: { $0.id == groupID }) else { return }
        if customGroups[index].memberUserIDs.contains(userID) {
            customGroups[index].memberUserIDs.remove(userID)
        } else {
            customGroups[index].memberUserIDs.insert(userID)
        }
        persistCustomGroups()
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        objectWillChange.send()
    }

    var isDiscoverable: Bool {
        currentUserProfile?.isDiscoverable == true
    }

    var seesHiddenPeople: Bool {
        showsHiddenPeople
    }

    func setShowsHiddenPeople(_ visible: Bool) {
        guard showsHiddenPeople != visible else { return }
        showsHiddenPeople = visible
        updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
        objectWillChange.send()
    }

    func setDiscoverable(_ visible: Bool) {
        guard var profile = currentUserProfile else { return }
        guard profile.isDiscoverable != visible else { return }
        profile.isDiscoverable = visible
        if visible {
            profile.markAsActive()
        }
        currentUserProfile = profile
        persistAndUpdateProfileAndGrid()
        objectWillChange.send()
    }

    func toggleDiscoverable() {
        setDiscoverable(!isDiscoverable)
    }

    func interestPinIDs(for raw: String) -> [String] {
        if let exact = interestPins[raw] { return exact }
        if let match = interestPins.first(where: {
            $0.key.compare(raw, options: .caseInsensitive) == .orderedSame
        }) {
            return match.value
        }
        return []
    }

    func toggleInterestPin(deviceID: String, interestRaw: String) {
        guard let userID = getUserID(forDeviceID: deviceID) else { return }
        let current = interestPinIDs(for: interestRaw)
        guard let next = FavoritePinLogic.toggling(userID, in: current) else {
            presentUserFacingAlert(FavoritePinLogic.pinLimitMessage)
            return
        }
        interestPins[interestRaw] = next
        persistInterestPins()
        objectWillChange.send()
    }

    func removePinInCurrentCategory(deviceID: String) {
        guard let userID = getUserID(forDeviceID: deviceID) else { return }
        switch peopleTab {
        case .all, .favorites:
            if starredUsers.contains(userID) {
                toggleStar(for: deviceID)
            }
        case .interest(let raw):
            let current = interestPinIDs(for: raw)
            if current.contains(userID) {
                toggleInterestPin(deviceID: deviceID, interestRaw: raw)
            }
        case .custom(let id):
            if isInCustomGroup(id, deviceID: deviceID) {
                toggleMembership(deviceID: deviceID, groupID: id)
            }
        }
    }

    func removePinsEverywhere(deviceID: String) {
        guard let userID = getUserID(forDeviceID: deviceID) else { return }
        if starredUsers.contains(userID) {
            toggleStar(for: deviceID)
        }
        var pins = interestPins
        for (raw, ids) in pins where ids.contains(userID) {
            pins[raw] = ids.filter { $0 != userID }
        }
        interestPins = pins
        persistInterestPins()
        for group in customGroups where group.memberUserIDs.contains(userID) {
            toggleMembership(deviceID: deviceID, groupID: group.id)
        }
        objectWillChange.send()
    }

    // Show all users on grid (sorted by distance if location available)
    func installUITestFixtures() {
        locksGridToFixtures = true
        showsLocalLLM = false
        showsSelfOnGrid = false
        selectedInterestFilter = []
        peopleTab = .all
        currentUserProfile = GridUITestHarness.me
        starredUsers = [GridUITestHarness.alice.userID]
        messages = [
            Message(
                id: "uitest-alice-1",
                senderDeviceID: GridUITestHarness.alice.deviceID,
                recipientDeviceID: GridUITestHarness.me.deviceID,
                senderUserID: GridUITestHarness.alice.userID,
                recipientUserID: GridUITestHarness.me.userID,
                text: GridUITestHarness.aliceMessageText,
                status: .received
            ),
            Message(
                id: "uitest-bob-1",
                senderDeviceID: GridUITestHarness.bob.deviceID,
                recipientDeviceID: GridUITestHarness.me.deviceID,
                senderUserID: GridUITestHarness.bob.userID,
                recipientUserID: GridUITestHarness.me.userID,
                text: GridUITestHarness.bobMessageText,
                status: .received
            ),
        ]
        updateGridWithAllProfiles(GridUITestHarness.nearby)
    }

    func updateGridWithAllProfiles(_ profiles: [UserProfile]) {
        let source = locksGridToFixtures ? GridUITestHarness.nearby : profiles
        let toDisplay = locksGridToFixtures
            ? source
            : gridPopulationService.profilesToDisplay(
                nearby: source,
                currentUser: currentUserProfile,
                includeHidden: seesHiddenPeople
            )
        var all = GridPlacementLogic.makeEmptyGrid()
        var favorites = GridPlacementLogic.makeEmptyGrid()
        gridPopulationService.layoutProfiles(
            into: &all,
            profiles: toDisplay,
            currentUser: currentUserProfile,
            display: displayState(memberUserIDs: starredUsers, membersOnly: false)
        )
        gridPopulationService.layoutProfiles(
            into: &favorites,
            profiles: toDisplay,
            currentUser: currentUserProfile,
            display: displayState(memberUserIDs: starredUsers, membersOnly: true)
        )
        allGridNodes = all
        favoriteGridNodes = favorites
        var groupNodes: [UUID: [[GridNode]]] = [:]
        for group in customGroups {
            var grid = GridPlacementLogic.makeEmptyGrid()
            gridPopulationService.layoutProfiles(
                into: &grid,
                profiles: toDisplay,
                currentUser: currentUserProfile,
                display: displayState(memberUserIDs: group.memberUserIDs, membersOnly: true)
            )
            groupNodes[group.id] = grid
        }
        customGroupNodes = groupNodes
        var interestNodes: [String: [[GridNode]]] = [:]
        for interest in interestPages {
            var grid = GridPlacementLogic.makeEmptyGrid()
            gridPopulationService.layoutProfiles(
                into: &grid,
                profiles: toDisplay,
                currentUser: currentUserProfile,
                display: displayState(
                    memberUserIDs: [],
                    membersOnly: false,
                    interestFilter: [interest]
                )
            )
            interestNodes[interest.rawValue] = grid
        }
        interestGridNodes = interestNodes
        gridNodes = nodes(for: peopleTab)
        SenderNameCache.store(profiles: toDisplay)
        if let current = currentUserProfile {
            SenderNameCache.store(current.deviceName, for: current.deviceID)
        }
        ingestSharedInterestsFromProfiles(toDisplay)
        objectWillChange.send()
    }

    func ingestSharedInterestsFromProfiles(_ profiles: [UserProfile]) {
        var harvest = profiles
        if let currentUserProfile {
            harvest.append(currentUserProfile)
        }
        ingestSharedInterests(SharedInterestMergeLogic.harvested(from: harvest))
    }

    func ingestSharedInterests(_ incoming: [CustomInterestRecord]) {
        let existing = CustomInterestStore.load()
        let merged = SharedInterestMergeLogic.merging(incoming, into: existing)
        guard merged != existing else { return }
        CustomInterestStore.save(merged)
        objectWillChange.send()
    }

    func refreshSharedInterestCatalog(completion: (() -> Void)? = nil) {
        sharedInterestService.fetchAll { [weak self] records in
            self?.ingestSharedInterests(records)
            completion?()
        }
    }
    
    func placeProfileOnGrid(_ profile: UserProfile) {
        guard let slot = GridPlacementLogic.firstEmptySlot(in: gridNodes) else {
            AppLog.grid.debug("Grid full; cannot place profile")
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
        if showsSelfOnGrid {
            GridPlacementLogic.place(profile: profile, in: &gridNodes, at: 0, col: 0)
        }
        if showsLocalLLM, findNode(forDeviceID: LocalLLMIdentity.deviceID) == nil {
            let col = showsSelfOnGrid && (gridNodes.first?.count ?? 0) > 1 ? 1 : 0
            if gridNodes.first?.indices.contains(col) == true, gridNodes[0][col].userProfile == nil {
                GridPlacementLogic.place(profile: LocalLLMIdentity.profile, in: &gridNodes, at: 0, col: col)
            } else {
                placeProfileOnGrid(LocalLLMIdentity.profile)
            }
        }
        objectWillChange.send()
    }
    
    func initializeGrid() {
        gridNodes = GridPlacementLogic.makeEmptyGrid(size: gridSize)
        allGridNodes = gridNodes
        favoriteGridNodes = GridPlacementLogic.makeEmptyGrid(size: gridSize)
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
