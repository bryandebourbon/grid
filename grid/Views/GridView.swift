import SwiftUI
import CloudKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    private enum HomePane {
        case people
        case map
        case messages
    }

    @State private var homePane: HomePane = .people
    @State private var isProfileDrawerExpanded = false
    @State private var showingInterestCapPopover = false
    @FocusState private var isChatComposerFocused: Bool
    @State private var showingContactInfo = false  // NEW: For contact info
    @State private var showingSignOutConfirmation = false
    @State private var showingBlockedUsers = false  // NEW: For blocked users view
    @State private var storiesMode = GridUITestHarness.isActive
        ? false
        : UserDefaults.standard.object(forKey: "storiesMode") as? Bool ?? false
    @AppStorage("grid.chatAlbumButton") private var showChatAlbumButton = false
    @State private var showBioBubbles = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "grid.bioBubbles") == nil {
            return true
        }
        return defaults.bool(forKey: "grid.bioBubbles")
    }()
    @State private var zoom = GridColumnZoom()
    @State private var showingStoryCreation = false  // NEW: For story creation sheet
    @State private var showingBioStoriesOverlay = false  // NEW: For bio+stories overlay
    @State private var bioStoriesProfile: UserProfile? = nil  // NEW: Profile for bio+stories overlay
    
    // Background customization
    @State private var backgroundImage: Image? = nil
    @State private var showingBackgroundPhotoPicker = false
    @State private var selectedBackgroundPhotoItem: PhotosPickerItem? = nil
    
    private var shouldUseCircularPhotos: Bool { false }

    private var shouldUseSquarePhotos: Bool { false }
    @State private var singleTapTimer: Timer?
    var signOutAction: () -> Void
    var deleteAccountAction: () -> Void

    @State private var showingDeleteConfirmation = false
    private static let aboveDrawerControlsHeight: CGFloat = 52

    private var gridScrollBottomInset: CGFloat {
        GridInterestBrowseSection.peekHeight() + Self.aboveDrawerControlsHeight + 8
    }

    private var showBioBubblesBinding: Binding<Bool> {
        Binding(
            get: { showBioBubbles },
            set: { newValue in
                showBioBubbles = newValue
                UserDefaults.standard.set(newValue, forKey: "grid.bioBubbles")
            }
        )
    }

    private var showSelfOnGridBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsSelfOnGrid },
            set: { newValue in
                viewModel.showsSelfOnGrid = newValue
                UserDefaults.standard.set(newValue, forKey: "grid.showSelfOnGrid")
                viewModel.updateGridWithAllProfiles(viewModel.proximityService.activeNearbyProfiles)
            }
        )
    }

    private func openChat(with deviceID: String) {
        viewModel.openChatOverlay(with: deviceID)
        isChatComposerFocused = true
    }

    private func hideChat() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.hideChatOverlay()
            isChatComposerFocused = false
        }
        zoom.resetPressState()
        KeyboardPresentation.dismissKeyboard()
    }

    private func warmChatIfNeeded() {
        KeyboardPresentation.installHeightObserver()
    }

    // MARK: - Grid cell touch routing

    private func handleChatTapped(_ recipientDeviceID: String) {
        openChat(with: recipientDeviceID)
    }
    
    private func handleStoriesTapped(_ profile: UserProfile) {
        print("GridView: 📱 Story tapped for profile: \(profile.deviceID)")
        
        // Check if it's the current user and they have no stories
        if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
           profile.deviceID == currentUserDeviceID {
            print("GridView: 👤 Current user tapped their own story")
            
            // Check if current user has active stories
            let hasStories = viewModel.storiesService.hasActiveStories(for: profile.deviceID)
            print("GridView: 📊 Current user has active stories: \(hasStories)")
            
            if !hasStories {
                // No stories - open creation
                print("GridView: ➕ No active stories, opening story creation for current user: \(profile.deviceID)")
                showingStoryCreation = true
                return
            }
        }
        
        // Open bio+stories overlay for all users (including current user with stories)
        print("GridView: 🎭 Opening bio+stories overlay for: \(profile.deviceID)")
        withAnimation {
            bioStoriesProfile = profile
            showingBioStoriesOverlay = true
        }
    }
    
    private func gridScrollView(nodes: [[GridNode]], showsFavoritesHint: Bool) -> some View {
        ScrollView {
            VStack(spacing: GridCellLayout.gutter) {
                ForEach(Array(GridColumnZoomLogic.occupiedRows(from: nodes, columns: zoom.gridColumns).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: GridCellLayout.gutter) {
                        ForEach(row) { node in
                            let partnerID = GridCellTapLogic.chatPartnerDeviceID(for: node)
                            GridNodeView(
                                node: node,
                                viewModel: viewModel,
                                useCircularPhotos: shouldUseCircularPhotos,
                                useSquarePhotos: shouldUseSquarePhotos,
                                storiesMode: storiesMode,
                                showBioBubbles: showBioBubbles,
                                gridColumns: zoom.gridColumns,
                                onChatTapped: { _ in
                                    if let partnerID {
                                        handleChatTapped(partnerID)
                                    }
                                },
                                onStoriesTapped: handleStoriesTapped
                            )
                            .id(node.id)
                            .frame(maxWidth: .infinity)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                        if row.count < zoom.gridColumns {
                            ForEach(0..<(zoom.gridColumns - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, GridCellLayout.gutter)
            .padding(.top, GridCellLayout.gutter)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: zoom.gridColumns)

            if viewModel.needsLocationOnboarding && !isProfileDrawerExpanded && !GridUITestHarness.isActive {
                GridLocationWelcomeCard(
                    buttonTitle: viewModel.locationEnableButtonTitle,
                    onOpenProfile: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            isProfileDrawerExpanded = true
                        }
                    },
                    onEnableLocation: {
                        viewModel.enableLocationFromOnboarding()
                    }
                )
            } else if showsFavoritesHint && !hasFavoritePeers(in: nodes) {
                Text(emptyGroupHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            Color.clear.frame(height: gridScrollBottomInset)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await viewModel.refreshPeopleAndMessages()
        }
        .scrollDisabled(zoom.scrollDisabled)
        .simultaneousGesture(zoom.pinchGesture)
        .simultaneousGesture(zoom.pressThenDragZoomGesture)
        .background {
            GridScrollPageSwipe(
                isEnabled: canSwipePeopleTabs,
                onSwipeLeft: {
                    handlePeopleTabSwipe(translation: -80)
                },
                onSwipeRight: {
                    handlePeopleTabSwipe(translation: 80)
                }
            )
        }
        // Dynamic background (colour or photo) visible through transparent cell corners
        .background(GridBackgroundView(backgroundImage: backgroundImage))
    }

    private var canSwipePeopleTabs: Bool {
        !viewModel.chatOverlaySession.isPresented && !showingBioStoriesOverlay && !zoom.isScaling
    }

    private func handlePeopleTabSwipe(translation: CGFloat) {
        if GridPeopleTabPaging.shouldPromptRemoveInterestToAdd(
            translation: translation,
            current: viewModel.peopleTab,
            tabs: viewModel.orderedPeopleTabs,
            canAddInterestPage: viewModel.canAddInterestPage
        ) {
            showingInterestCapPopover = true
            return
        }
        if GridPeopleTabPaging.shouldOpenInterestSearch(
            translation: translation,
            current: viewModel.peopleTab,
            tabs: viewModel.orderedPeopleTabs,
            canAddInterestPage: viewModel.canAddInterestPage
        ) {
            openInterestSearch()
            return
        }
        movePeopleTab(to: GridPeopleTabPaging.tabAfterSwipe(
            translation: translation,
            current: viewModel.peopleTab,
            tabs: viewModel.orderedPeopleTabs
        ))
    }

    private func openInterestSearch() {
        guard viewModel.canAddInterestPage else { return }
        viewModel.searchText = ""
        viewModel.showingInterestSearch = true
    }

    private var emptyGroupHint: String {
        if case .custom = viewModel.peopleTab {
            return "Star someone and choose this group to add them here."
        }
        if case .interest(let raw) = viewModel.peopleTab {
            return "No one nearby into \(raw) yet."
        }
        return "Star people from their profile to add them here."
    }

    private func movePeopleTab(to tab: GridPeopleTab) {
        guard viewModel.peopleTab != tab else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.peopleTab = tab
        }
    }

    private var conversationsButton: some View {
        Button {
            toggleHomePane(.messages)
        } label: {
            paneCircleLabel(
                systemImage: "bubble.left.and.bubble.right.fill",
                isActive: homePane == .messages
            )
            .overlay(alignment: .topTrailing) {
                let unread = viewModel.incomingUnreadCount()
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, unread > 9 ? 4 : 0)
                        .background(Color.white, in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(homePane == .messages ? "Show grid" : "Messages")
        .accessibilityAddTraits(homePane == .messages ? [.isSelected] : [])
        .accessibilityValue(viewModel.incomingUnreadCount() > 0 ? "\(viewModel.incomingUnreadCount()) unread" : "No unread")
        .accessibilityIdentifier("grid.messages")
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            mapsCircleButton(systemImage: "minus.magnifyingglass") {
                zoom.zoomOut()
            }
            .disabled(!zoom.canZoomOut)
            .opacity(zoom.canZoomOut ? 1 : 0.4)
            .accessibilityLabel("Zoom out")

            mapsCircleButton(systemImage: "plus.magnifyingglass") {
                zoom.zoomIn()
            }
            .disabled(!zoom.canZoomIn)
            .opacity(zoom.canZoomIn ? 1 : 0.4)
            .accessibilityLabel("Zoom in")
        }
    }

    private var aboveDrawerControls: some View {
        HStack(spacing: 8) {
            if storiesMode {
                mapsCircleButton(systemImage: "plus") {
                    showingStoryCreation = true
                }
                .accessibilityLabel("Create Story")
            }

            settingsMenu
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                homePane = .messages
            } label: {
                Label("Conversations", systemImage: "bubble.left.and.bubble.right.fill")
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isProfileDrawerExpanded = true
                }
            } label: {
                Label("Edit Profile", systemImage: "person.circle")
            }

            if storiesMode {
                Button {
                    showingStoryCreation = true
                } label: {
                    Label("Create Story", systemImage: "camera.circle.fill")
                }
            }

            Divider()

            Toggle(isOn: showSelfOnGridBinding) {
                Label("Show me on the grid", systemImage: "person.crop.square")
            }

            Toggle(isOn: showBioBubblesBinding) {
                Label("Status bubbles", systemImage: "text.bubble")
            }

            Toggle(isOn: $showChatAlbumButton) {
                Label("Album button in chat", systemImage: "photo.on.rectangle")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showsLocalLLM.toggle()
                    LocalLLMIdentity.setEnabled(viewModel.showsLocalLLM)
                    viewModel.updateGridWithAllProfiles(viewModel.proximityService.activeNearbyProfiles)
                }
            } label: {
                Label(
                    viewModel.showsLocalLLM ? "Hide AI Chat" : "AI Chat",
                    systemImage: viewModel.showsLocalLLM ? "sparkles" : "sparkle"
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    storiesMode.toggle()
                    UserDefaults.standard.set(storiesMode, forKey: "storiesMode")
                }
            } label: {
                Label(
                    storiesMode ? "Exit Stories Mode" : "Stories Mode",
                    systemImage: storiesMode ? "circle.badge.minus" : "circle.badge.plus"
                )
            }

            Button {
                showingBackgroundPhotoPicker = true
            } label: {
                Label("Background Photo", systemImage: "photo")
            }

            if backgroundImage != nil {
                Button(role: .destructive) {
                    backgroundImage = nil
                    selectedBackgroundPhotoItem = nil
                } label: {
                    Label("Remove Background Photo", systemImage: "photo.slash")
                }
            }

            Divider()

            Button {
                showingBlockedUsers = true
            } label: {
                Label("Blocked Users", systemImage: "hand.raised.slash")
            }

            Button {
                showingContactInfo = true
            } label: {
                Label("Contact Us", systemImage: "envelope")
            }

            Button {
                viewModel.showingTermsOfUse = true
            } label: {
                Label("Terms of Use", systemImage: "doc.text")
            }

            Button {
                viewModel.showingPrivacyPolicy = true
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }

            Divider()

            Button(role: .destructive) {
                showingSignOutConfirmation = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
        } label: {
            mapsCircleButtonLabel(systemImage: "gearshape.fill", foreground: .gray)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(GridUITestHarness.settingsIdentifier)
    }

    private var peopleMapButton: some View {
        Button {
            toggleHomePane(.map)
        } label: {
            paneCircleLabel(systemImage: "map.fill", isActive: homePane == .map)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(homePane == .map ? "Show grid" : "Map")
        .accessibilityAddTraits(homePane == .map ? [.isSelected] : [])
        .accessibilityIdentifier("grid.map")
    }

    private var uiTestHarnessBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                UITestHitButton(title: "Open Alice", identifier: "uitest.open.alice") {
                    openChat(with: GridUITestHarness.alice.deviceID)
                }
                UITestHitButton(title: "Open Bob", identifier: "uitest.open.bob") {
                    openChat(with: GridUITestHarness.bob.deviceID)
                }
                UITestHitButton(title: "Open Me", identifier: "uitest.open.me") {
                    openChat(with: GridUITestHarness.me.deviceID)
                }
                Text(viewModel.uiTestOpenedPartner)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier(GridUITestHarness.partnerProbeIdentifier)
            }
            .frame(height: 36)

            HStack(spacing: 8) {
                UITestHitButton(title: "All", identifier: "people.tab.all") {
                    viewModel.peopleTab = .all
                }
                Text(viewModel.peopleTab.rawValue)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier(GridUITestHarness.peopleTabProbeIdentifier)
            }
            .frame(height: 36)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.95))
    }

    private func mapsCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            mapsCircleButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func mapsCircleButtonLabel(systemImage: String, foreground: Color = .primary) -> some View {
        paneCircleLabel(systemImage: systemImage, isActive: false, foreground: foreground)
    }

    private func paneCircleLabel(
        systemImage: String,
        isActive: Bool,
        foreground: Color = .primary
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : foreground)
            .frame(width: 44, height: 44)
            .background(isActive ? Color.blue : Color.clear, in: Circle())
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.35 : 0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
    }

    private func toggleHomePane(_ pane: HomePane) {
        homePane = homePane == pane ? .people : pane
    }

    private var peopleTabPager: some View {
        gridScrollView(
            nodes: viewModel.nodes(for: viewModel.peopleTab),
            showsFavoritesHint: viewModel.peopleTab != .all
        )
        .id(viewModel.peopleTab)
    }

    private func hasFavoritePeers(in nodes: [[GridNode]]) -> Bool {
        let me = viewModel.currentUserProfile?.deviceID
        return nodes.flatMap { $0 }.contains { node in
            guard let profile = node.userProfile else { return false }
            return profile.deviceID != me && !LocalLLMIdentity.isLLM(profile.deviceID)
        }
    }

    var body: some View {
        ZStack {
            // Main grid content
            mainGridView
            

            
            // Bio+Stories overlay
            if showingBioStoriesOverlay, let profile = bioStoriesProfile {
                ZStack {
                    OverlayBackdrop(
                        opacity: 0.3,
                        dismissAnimation: .easeInOut(duration: 0.3),
                        onDismiss: {
                            showingBioStoriesOverlay = false
                            bioStoriesProfile = nil
                        }
                    )

                    BioStoriesOverlayView(
                        viewModel: viewModel,
                        userProfile: profile,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingBioStoriesOverlay = false
                                bioStoriesProfile = nil
                            }
                        },
                        onChatTapped: { deviceID in
                            // Close overlay and open chat
                            showingBioStoriesOverlay = false
                            bioStoriesProfile = nil
                            
                            openChat(with: deviceID)
                        }
                    )
                    .padding(.horizontal, 40)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1000)
                }
            }

            if viewModel.chatOverlaySession.isPresented,
               let recipientID = viewModel.chatOverlaySession.activePartnerDeviceID {
                ChatOverlayView(
                    viewModel: viewModel,
                    recipientDeviceID: recipientID,
                    isPresented: true,
                    isComposerFocused: $isChatComposerFocused,
                    onClose: hideChat
                )
                .id(recipientID)
                .zIndex(20)
                .transaction { $0.disablesAnimations = true }
                .accessibilityIdentifier("chat.overlay")
            }
        }
        // User-selected background (colour or photo)
        .background(
            GridBackgroundView(backgroundImage: backgroundImage)
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.3), value: showingBioStoriesOverlay)
    }
    
    var mainGridView: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch homePane {
                        case .map:
                            GridPeopleMapView(viewModel: viewModel) { deviceID in
                                openChat(with: deviceID)
                            }
                        case .messages:
                            ConversationsListView(
                                viewModel: viewModel,
                                bottomInset: gridScrollBottomInset,
                                onSelect: openChat(with:)
                            )
                        case .people:
                            if viewModel.currentUserProfile != nil {
                                peopleTabPager
                            } else {
                                Text("Loading profile or no profile set...")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 8) {
                        HStack {
                            conversationsButton
                            peopleMapButton
                            Spacer()
                            if homePane == .people {
                                zoomControls
                            }
                            aboveDrawerControls
                        }
                        .padding(.horizontal, 16)

                        if !GridUITestHarness.isActive {
                            GridInterestBrowseSection(
                                viewModel: viewModel,
                                isExpanded: $isProfileDrawerExpanded,
                                showBioBubbles: showBioBubbles,
                                onChatTapped: { deviceID in
                                    isProfileDrawerExpanded = false
                                    openChat(with: deviceID)
                                }
                            )
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if GridUITestHarness.isActive {
                        uiTestHarnessBar
                    } else {
                        GridPeopleTabBar(
                            selection: $viewModel.peopleTab,
                            groups: viewModel.customGroups,
                            interestPages: viewModel.interestPages,
                            canAddInterestPage: viewModel.canAddInterestPage,
                            showingInterestCapPopover: $showingInterestCapPopover,
                            onSearchInterests: openInterestSearch,
                            onDeleteInterest: { interest in
                                viewModel.unregisterFromInterest(interest)
                            }
                        )
                    }
                }
                .background(.bar)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.handleGridAppeared()
                warmChatIfNeeded()
            }
            .onChange(of: viewModel.currentUserProfile?.deviceID) { _ in
                warmChatIfNeeded()
            }
            .onDisappear {
                // Clean up any pending single tap timer
                singleTapTimer?.invalidate()
                singleTapTimer = nil
            }
            .sheet(item: $viewModel.selectedUserProfileForReport) { profileUser in // NEW: Sheet for Report Dialog
                ReportUserView(viewModel: viewModel, userProfile: profileUser.userProfile)
            }
            .sheet(isPresented: $showingContactInfo) {  // NEW: Sheet for Contact Info
                ContactInfoView()
            }
            .sheet(isPresented: $showingBlockedUsers) {  // NEW: Sheet for Blocked Users
                BlockedUsersView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingPrivacyPolicy) {  // NEW: Sheet for Privacy Policy
                PrivacyPolicyView()
            }
            .sheet(isPresented: $viewModel.showingTermsOfUse) {
                TermsOfUseView()
            }
            .sheet(isPresented: $showingStoryCreation) {  // NEW: Sheet for Story Creation
                StoryCreationView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingInterestSearch) { // NEW: Sheet for Interest Search
                InterestSearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingBackgroundPhotoPicker) {
                BackgroundPhotoPickerView(selectedItem: $selectedBackgroundPhotoItem, backgroundImage: $backgroundImage)
            }
            .alert("Log Out?", isPresented: $showingSignOutConfirmation) {
                Button("Log Out", role: .destructive) { signOutAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You’ll return to the sign-in screen.")
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteAccountAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
            .alert(
                "Notice",
                isPresented: Binding(
                    get: { viewModel.userFacingAlert != nil },
                    set: { if !$0 { viewModel.userFacingAlert = nil } }
                )
            ) {
                Button("OK") { viewModel.userFacingAlert = nil }
            } message: {
                Text(viewModel.userFacingAlert ?? "")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single column navigation on iPad
    }
    
    @MainActor
    func refreshGrid() async {
        await viewModel.refreshPeopleAndMessages()
    }

}

#if DEBUG
struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(
            userID: "previewUser123",
            deviceID: "previewDeviceID_789",
            deviceName: "Preview Device",
            profileImage: nil
        )
        mockViewModel.setCurrentUserProfile(dummyProfile)
        if !mockViewModel.gridNodes.isEmpty, !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        return GridView(viewModel: mockViewModel, signOutAction: {}, deleteAccountAction: {})
    }
}
#endif
