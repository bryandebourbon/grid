import SwiftUI
import CloudKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showsMap = true
    @State private var showsGrid = true
    @State private var showsMessages = false
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
    @AppStorage("grid.showZoomControls") private var showZoomControls = false
    @AppStorage("grid.mapSplitFraction.half") private var mapSplitFraction = 0.5
    @State private var mapSplitDragOrigin: Double?
    @State private var pageHeight: CGFloat = 852
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
    @State private var showingMasterPassword = false
    @State private var showingWrongMasterPassword = false
    @State private var masterPassword = ""
    @State private var isRefreshingPeople = false
    @State private var lastReportedScrollOffset: CGFloat = -1
    @State private var searchX: CGFloat = 0
    @State private var searchOpen = false
    @State private var searchPageWidth: CGFloat = 390
    private static let aboveDrawerControlsHeight: CGFloat = 52

    private var gridScrollBottomInset: CGFloat {
        let home = GridInterestBrowseSection.bottomSafeArea
        if showsMap && showsGrid && showsMessages == false {
            return home + 8
        }
        return home + Self.aboveDrawerControlsHeight + 16
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

    private var showHiddenPeopleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsHiddenPeople },
            set: { newValue in
                if newValue {
                    masterPassword = ""
                    DispatchQueue.main.async {
                        showingMasterPassword = true
                    }
                } else {
                    viewModel.setShowsHiddenPeople(false)
                }
            }
        )
    }

    private func unlockHiddenPeopleIfPasswordMatches() {
        let password = masterPassword
        masterPassword = ""
        if GridMasterViewerLogic.unlocking(enabled: true, password: password) {
            viewModel.setShowsHiddenPeople(true)
        } else {
            showingWrongMasterPassword = true
        }
    }

    private var heatmapRadiusBinding: Binding<Int> {
        Binding(
            get: { InterestPlaceHeatmapLogic.kilometers(fromMeters: viewModel.heatmapSearchRadiusMeters) },
            set: { viewModel.setHeatmapSearchRadius(InterestPlaceHeatmapLogic.meters(fromKilometers: $0)) }
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
                                    guard let partnerID else { return }
                                    if partnerID == viewModel.currentUserProfile?.deviceID {
                                        isProfileDrawerExpanded = true
                                    } else {
                                        handleChatTapped(partnerID)
                                    }
                                },
                                onStoriesTapped: { profile in
                                    if profile.deviceID == viewModel.currentUserProfile?.deviceID {
                                        isProfileDrawerExpanded = true
                                    } else {
                                        handleStoriesTapped(profile)
                                    }
                                }
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

            if showsFavoritesHint && !hasFavoritePeers(in: nodes) {
                Text(emptyGroupHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            Color.clear.frame(height: BrowseRadiusLogic.scrollSpan)
            Color.clear.frame(height: gridScrollBottomInset)
        }
        .scrollBounceBehavior(.always)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y)
        } action: { _, offset in
            guard abs(offset - lastReportedScrollOffset) >= 8 else { return }
            lastReportedScrollOffset = offset
            viewModel.setBrowseRadius(fromScrollOffset: offset)
        }
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
        // A chosen photo still shows through the cell corners. Otherwise the drawer glass shows through.
        .background {
            if backgroundImage != nil {
                GridBackgroundView(backgroundImage: backgroundImage)
            } else if showsMap == false {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
    }

    private var canSwipePeopleTabs: Bool {
        !viewModel.chatOverlaySession.isPresented && !showingBioStoriesOverlay && !zoom.isScaling && !searchOpen
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
        openSearch()
    }

    private func openSearch() {
        guard !searchOpen else { return }
        guard viewModel.canAddInterestPage else {
            showingInterestCapPopover = true
            viewModel.showingInterestSearch = false
            return
        }
        viewModel.searchText = ""
        viewModel.showingInterestSearch = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            searchOpen = true
            searchX = -searchPageWidth
        }
    }

    private func closeSearch() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            searchOpen = false
            searchX = 0
        }
        viewModel.showingInterestSearch = false
    }

    private func settleSearch(translation: CGFloat, velocity: CGFloat) {
        if !searchOpen, translation >= 0 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                searchX = 0
            }
            return
        }
        let flick = abs(translation) < 90 && abs(velocity) > 500
        if !searchOpen, flick, translation < 0 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                searchX = 0
            }
            handlePeopleTabSwipe(translation: -80)
            return
        }
        let projected = searchX + velocity * 0.16
        let open = projected < -searchPageWidth * 0.32
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            searchOpen = open
            searchX = open ? -searchPageWidth : 0
            viewModel.showingInterestSearch = open
        }
    }

    private func followSearchDrag(_ translation: CGFloat) {
        let x: CGFloat
        if searchOpen {
            x = -searchPageWidth + max(0, translation)
        } else {
            let pulled = min(0, translation + 36)
            x = pulled
        }
        if x > 0 {
            searchX = x * 0.2
        } else if x < -searchPageWidth {
            searchX = -searchPageWidth + (x + searchPageWidth) * 0.2
        } else {
            searchX = x
        }
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
            showsMessages.toggle()
        } label: {
            paneCircleLabel(
                systemImage: "bubble.left.and.bubble.right.fill",
                isActive: showsMessages
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
        .accessibilityLabel(showsMessages ? "Show grid" : "Messages")
        .accessibilityAddTraits(showsMessages ? [.isSelected] : [])
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

            locationButton
            refreshButton
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                showsMessages = true
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

            Toggle(isOn: showHiddenPeopleBinding) {
                Label("See hidden people", systemImage: "eye.slash")
            }

            Toggle(isOn: showSelfOnGridBinding) {
                Label("Show me on the grid", systemImage: "person.crop.square")
            }

            Toggle(isOn: showBioBubblesBinding) {
                Label("Status bubbles", systemImage: "text.bubble")
            }

            Picker(selection: heatmapRadiusBinding) {
                ForEach(InterestPlaceHeatmapLogic.presetKilometers, id: \.self) { km in
                    Text("\(km) km").tag(km)
                }
            } label: {
                Label("Heatmap radius", systemImage: "circle.dotted")
            }

            Toggle(isOn: $showZoomControls) {
                Label("Zoom buttons", systemImage: "plus.magnifyingglass")
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

    private var locationButton: some View {
        Button {
            toggleMap()
        } label: {
            paneCircleLabel(
                systemImage: "location.fill",
                isActive: (showsMap && showsMessages == false) || viewModel.needsLocationOnboarding
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map")
        .accessibilityValue(
            viewModel.needsLocationOnboarding
                ? viewModel.locationEnableButtonTitle
                : "Current location"
        )
        .accessibilityAddTraits(showsMap && showsMessages == false ? [.isSelected] : [])
        .accessibilityIdentifier("grid.map")
    }

    private var refreshButton: some View {
        Button {
            Task { await refreshFromToolbar() }
        } label: {
            ZStack {
                paneCircleLabel(
                    systemImage: "arrow.clockwise",
                    isActive: isRefreshingPeople
                )
                .opacity(isRefreshingPeople ? 0 : 1)
                if isRefreshingPeople {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue, in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRefreshingPeople)
        .accessibilityLabel("Refresh")
        .accessibilityIdentifier("grid.refresh")
    }

    @MainActor
    private func refreshFromToolbar() async {
        guard isRefreshingPeople == false else { return }
        isRefreshingPeople = true
        await viewModel.refreshPeopleAndMessages()
        isRefreshingPeople = false
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

    private func toggleMap() {
        if showsMessages {
            showsMessages = false
            showsMap = true
            viewModel.recenterMapOnUser()
            return
        }
        if showsMap {
            viewModel.recenterMapOnUser()
            return
        }
        showsMap = true
        viewModel.recenterMapOnUser()
    }

    private var controlBar: some View {
        HStack {
            conversationsButton
            Spacer()
            if showsGrid && showsMessages == false, showZoomControls {
                zoomControls
            }
            aboveDrawerControls
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if showsMap && showsGrid && showsMessages == false && GridUITestHarness.isActive == false {
            let fraction = min(0.72, max(0.18, mapSplitFraction))
            let drawerHeight = max(200, pageHeight * (1 - CGFloat(fraction)))
            VStack(spacing: 0) {
                controlBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                gridWithTabs(isMapOverlay: true, containerHeight: pageHeight)
                    .frame(height: drawerHeight)
            }
        } else {
            controlBar
                .padding(.horizontal, 16)
                .padding(.bottom, GridInterestBrowseSection.bottomSafeArea + 8)
        }
    }

    private func gridWithTabs(isMapOverlay: Bool, containerHeight: CGFloat = 1) -> some View {
        GridInterestBrowseSection(
            viewModel: viewModel,
            isExpanded: .constant(false),
            showBioBubbles: showBioBubbles,
            showingInterestCapPopover: $showingInterestCapPopover,
            onSearchInterests: openInterestSearch,
            onDeleteInterest: { interest in
                viewModel.unregisterFromInterest(interest)
            },
            gridContent: AnyView(gridPane),
            isMapOverlay: isMapOverlay,
            containerHeight: containerHeight,
            splitFraction: $mapSplitFraction,
            splitDragOrigin: $mapSplitDragOrigin
        )
    }

    private var mapPane: some View {
        GridPeopleMapView(viewModel: viewModel) { deviceID in
            if deviceID == viewModel.currentUserProfile?.deviceID {
                isProfileDrawerExpanded = true
            } else {
                openChat(with: deviceID)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var gridPane: some View {
        if viewModel.currentUserProfile != nil {
            peopleTabPager
        } else {
            Text("Loading profile or no profile set...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            GeometryReader { geo in
                HStack(spacing: 0) {
                    mainPage
                        .frame(width: geo.size.width, height: geo.size.height)
                    InterestSearchView(viewModel: viewModel, isActive: searchOpen, onClose: closeSearch)
                        .safeAreaPadding(.top)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .offset(x: searchX)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .onAppear { searchPageWidth = geo.size.width }
                .onChange(of: geo.size.width) { width in
                    searchPageWidth = width
                    if searchOpen { searchX = -width }
                }
            }
            .clipped()
            .ignoresSafeArea()
            .background {
                GridSearchPager(
                    enabled: canSwipePeopleTabs || searchOpen,
                    searchOpen: searchOpen,
                    onHold: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            searchX = searchOpen ? -searchPageWidth : 0
                        }
                    },
                    onMove: followSearchDrag,
                    onEnd: settleSearch
                )
            }
            .onChange(of: viewModel.showingInterestSearch) { show in
                if show { openSearch() }
            }
            .sheet(item: $viewModel.selectedUserProfileForReport) { profileUser in
                ReportUserView(viewModel: viewModel, userProfile: profileUser.userProfile)
            }
            .sheet(isPresented: $showingContactInfo) {
                ContactInfoView()
            }
            .sheet(isPresented: $showingBlockedUsers) {
                BlockedUsersView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $viewModel.showingTermsOfUse) {
                TermsOfUseView()
            }
            .sheet(isPresented: $showingStoryCreation) {
                StoryCreationView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingBackgroundPhotoPicker) {
                BackgroundPhotoPickerView(selectedItem: $selectedBackgroundPhotoItem, backgroundImage: $backgroundImage)
            }
            .alert("See hidden people", isPresented: $showingMasterPassword) {
                SecureField("Password", text: $masterPassword)
                Button("Unlock") { unlockHiddenPeopleIfPasswordMatches() }
                Button("Cancel", role: .cancel) { masterPassword = "" }
            } message: {
                Text("Enter the password to show everyone, including hidden people.")
            }
            .alert("Wrong password", isPresented: $showingWrongMasterPassword) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That password didn’t unlock hidden people.")
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
        .navigationViewStyle(StackNavigationViewStyle())
        .ignoresSafeArea()
    }

    private var mainPage: some View {
        ZStack(alignment: .bottom) {
                    Group {
                        if showsMessages {
                            ConversationsListView(
                                viewModel: viewModel,
                                bottomInset: gridScrollBottomInset,
                                onSelect: openChat(with:)
                            )
                            .safeAreaPadding(.top)
                        } else if showsMap {
                            mapPane
                        } else if GridUITestHarness.isActive {
                            gridPane
                        } else {
                            gridWithTabs(isMapOverlay: false)
                                .safeAreaPadding(.top)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomChrome
                        .fixedSize(horizontal: false, vertical: true)
                }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { pageHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { pageHeight = $0 }
                }
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if GridUITestHarness.isActive {
                    uiTestHarnessBar
                        .background(.bar)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isProfileDrawerExpanded) {
                GridInterestBrowseSection(
                    viewModel: viewModel,
                    isExpanded: $isProfileDrawerExpanded,
                    showBioBubbles: showBioBubbles,
                    showingInterestCapPopover: $showingInterestCapPopover,
                    onSearchInterests: openInterestSearch,
                    onDeleteInterest: { interest in
                        viewModel.unregisterFromInterest(interest)
                    },
                    onChatTapped: { deviceID in
                        isProfileDrawerExpanded = false
                        openChat(with: deviceID)
                    },
                    expandedTrailing: AnyView(settingsMenu),
                    showsOwnProfile: true
                )
            }
            .onAppear {
                viewModel.handleGridAppeared()
                warmChatIfNeeded()
            }
            .onChange(of: viewModel.currentUserProfile?.deviceID) { _ in
                warmChatIfNeeded()
            }
            .onDisappear {
                singleTapTimer?.invalidate()
                singleTapTimer = nil
            }
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
