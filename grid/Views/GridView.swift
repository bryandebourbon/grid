import SwiftUI
import CloudKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showingConversationsList = false  // NEW: For conversations list
    @State private var selectedUserProfileForCard: ProfileCardUser? = nil // NEW: For profile card
    @State private var showProfileOverlay = false
    @State private var overlayProfile: UserProfile? = nil
    @State private var showChatOverlay = false  // NEW: For chat overlay
    @State private var chatOverlayRecipientID: String? = nil  // NEW: For chat overlay recipient
    @State private var showingSettingsMenu = false
    @State private var showingContactInfo = false  // NEW: For contact info
    @State private var showingBlockedUsers = false  // NEW: For blocked users view
    @State private var storiesMode = UserDefaults.standard.object(forKey: "storiesMode") as? Bool ?? false  // NEW: Stories mode (default: off)
    @State private var useCircularPhotos = UserDefaults.standard.object(forKey: "circularPhotos") as? Bool ?? true  // NEW: Circular photos (default: on)
    @State private var zoom = GridColumnZoom()
    @State private var showingStoryCreation = false  // NEW: For story creation sheet
    @State private var showingBioStoriesOverlay = false  // NEW: For bio+stories overlay
    @State private var bioStoriesProfile: UserProfile? = nil  // NEW: Profile for bio+stories overlay
    
    // Background customization
    @State private var backgroundColor: Color = Color.blue.opacity(0.15)
    @State private var backgroundImage: Image? = nil
    @State private var showingColorPicker = false
    @State private var showingBackgroundPhotoPicker = false
    @State private var selectedBackgroundPhotoItem: PhotosPickerItem? = nil
    
    // Computed property for actual photo shape based on stories mode and circular photos setting
    private var shouldUseCircularPhotos: Bool {
        if storiesMode {
            return true // Always circular in stories mode
        } else {
            return useCircularPhotos // Use manual setting in non-stories mode
        }
    }
    @State private var singleTapTimer: Timer?
    var signOutAction: () -> Void
    var deleteAccountAction: () -> Void

    @State private var showingDeleteConfirmation = false

    private var doubleTapDetectedBinding: Binding<Bool> {
        Binding(
            get: { zoom.doubleTapDetected },
            set: { zoom.doubleTapDetected = $0 }
        )
    }

    private func cancelRecentOverlaysFromDoubleTap() {
        if showProfileOverlay {
            withAnimation(.easeOut(duration: 0.15)) {
                showProfileOverlay = false
                overlayProfile = nil
            }
        }
        if showingBioStoriesOverlay {
            withAnimation(.easeOut(duration: 0.15)) {
                showingBioStoriesOverlay = false
                bioStoriesProfile = nil
            }
        }
    }

    // MARK: - Grid cell touch routing

    private func handleProfileTapped(_ profile: UserProfile) {
        if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
           profile.deviceID == currentUserDeviceID {
            // Current user - open full profile editor
            selectedUserProfileForCard = ProfileCardUser(id: profile.deviceID, userProfile: profile)
        } else {
            // Other user - show overlay
            withAnimation(.easeInOut(duration: 0.2)) {
                self.overlayProfile = profile
                self.showProfileOverlay = true
            }
        }
    }
    
    private func handleChatTapped(_ recipientDeviceID: String) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            chatOverlayRecipientID = recipientDeviceID
            showChatOverlay = true
        }
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
    
    private func handleSingleTapOccurred() {
        zoom.recordSingleTap()
    }

    private var gridScrollView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: zoom.gridColumns), spacing: 2) {
                ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                    GridNodeView(
                        node: node,
                        viewModel: viewModel,
                        useCircularPhotos: shouldUseCircularPhotos,
                        storiesMode: storiesMode,
                        onProfileTapped: handleProfileTapped,
                        onChatTapped: handleChatTapped,
                        onStoriesTapped: handleStoriesTapped,
                        onSingleTapOccurred: handleSingleTapOccurred,
                        doubleTapDetected: doubleTapDetectedBinding
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .padding()
        }
        .scrollDisabled(zoom.scrollDisabled)
        .simultaneousGesture(zoom.pinchGesture)
        .onTapGesture(count: 2) {
            zoom.handleDoubleTapGesture(cancelRecentOverlay: cancelRecentOverlaysFromDoubleTap)
        }
        .simultaneousGesture(zoom.longPressGesture)
        .simultaneousGesture(zoom.dragZoomGesture)
        .refreshable {
            await refreshGrid()
        }
        // Dynamic background (colour or photo) visible through transparent cell corners
        .background(GridBackgroundView(backgroundColor: backgroundColor, backgroundImage: backgroundImage))
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
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    chatOverlayRecipientID = deviceID
                                    showChatOverlay = true
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 40)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1000)
                }
            }
        }
        // User-selected background (colour or photo)
        .background(
            GridBackgroundView(backgroundColor: backgroundColor, backgroundImage: backgroundImage)
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.3), value: showingBioStoriesOverlay)
    }
    
    var mainGridView: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !viewModel.selectedInterestFilter.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.selectedInterestFilter), id: \.self) { interest in
                                FilterChip(
                                    text: interest.rawValue,
                                    icon: nil,
                                    color: .blue,
                                    emoji: interest.emoji
                                ) {
                                    viewModel.removeInterestFilter(interest)
                                }
                            }
                            
                            if !viewModel.selectedInterestFilter.isEmpty {
                                Button("Clear All") {
                                    viewModel.clearInterestFilter()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }
                
                GridInterestBrowseSection(viewModel: viewModel)
                
                if let profile = viewModel.currentUserProfile {
                    // Grid supports multiple zoom gestures (like Maps):
                    // • Pinch to zoom in/out
                    // • Double-tap for quick zoom in/out 
                    // • Long drag up/down for continuous zoom
                    gridScrollView
                } else {
                    Text("Loading profile or no profile set...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .onAppear {
                viewModel.handleGridAppeared()
            }
            .onDisappear {
                // Clean up any pending single tap timer
                singleTapTimer?.invalidate()
                singleTapTimer = nil
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConversationsList = true }) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.body)
                            .accessibilityLabel("Conversations")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Story creation button when in stories mode
                        if storiesMode {
                            Button(action: {
                                showingStoryCreation = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Menu {
                        Button(action: {
                            if let myDeviceID = viewModel.currentUserProfile?.deviceID {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    chatOverlayRecipientID = myDeviceID
                                    showChatOverlay = true
                                }
                            }
                        }) {
                            Label("My Notes", systemImage: "note.text")
                        }
                        
                        // Story creation option when in stories mode
                        if storiesMode {
                            Button(action: {
                                showingStoryCreation = true
                            }) {
                                Label("Create Story", systemImage: "camera.circle.fill")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            if let currentProfile = viewModel.currentUserProfile {
                                selectedUserProfileForCard = ProfileCardUser(id: currentProfile.deviceID, userProfile: currentProfile)
                            }
                        }) {
                            Label("Edit Profile", systemImage: "person.circle")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                storiesMode.toggle()
                                UserDefaults.standard.set(storiesMode, forKey: "storiesMode")
                            }
                        }) {
                            Label(storiesMode ? "Exit Stories Mode" : "Stories Mode", 
                                  systemImage: storiesMode ? "circle.badge.minus" : "circle.badge.plus")
                        }
                        
                        // Only show circular photos toggle when NOT in stories mode (since stories mode forces circular)
                        if !storiesMode {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    useCircularPhotos.toggle()
                                    UserDefaults.standard.set(useCircularPhotos, forKey: "circularPhotos")
                                }
                            }) {
                                Label(useCircularPhotos ? "Square Photos" : "Circular Photos", 
                                      systemImage: useCircularPhotos ? "rectangle" : "circle")
                            }
                        }
                        
                        // Background customization
                        Button(action: {
                            showingColorPicker = true
                        }) {
                            Label("Background Color", systemImage: "paintpalette")
                        }
                        
                        Button(action: {
                            showingBackgroundPhotoPicker = true
                        }) {
                            Label("Background Photo", systemImage: "photo")
                        }
                        
                        if backgroundImage != nil {
                            Button(role: .destructive, action: {
                                backgroundImage = nil
                                selectedBackgroundPhotoItem = nil
                            }) {
                                Label("Remove Background Photo", systemImage: "photo.slash")
                            }
                        }
                        
                        Button(action: { showingBlockedUsers = true }) {
                            Label("Blocked Users", systemImage: "hand.raised.slash")
                        }
                        
                        Button(action: { showingContactInfo = true }) {
                            Label("Contact Us", systemImage: "envelope")
                        }
                        
                        Button(action: { viewModel.showingPrivacyPolicy = true }) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                        
                        Button(action: signOutAction) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Account", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                    }
                }
            }
            .sheet(isPresented: $showingConversationsList) {
                ConversationsListView(viewModel: viewModel) { deviceID in
                    showingConversationsList = false
                    // Use overlay instead of sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            chatOverlayRecipientID = deviceID
                            showChatOverlay = true
                        }
                    }
                }
            }
            .sheet(item: $selectedUserProfileForCard) { profileUser in // NEW: Sheet for Profile Card
                // Placeholder for ProfileCardView - will be created next
                // For now, just a simple view to confirm it works
                ProfileCardView(
                    viewModel: viewModel, 
                    userProfile: profileUser.userProfile,
                    onChatTapped: { deviceID in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            chatOverlayRecipientID = deviceID
                            showChatOverlay = true
                        }
                    }
                )
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
            .sheet(isPresented: $showingStoryCreation) {  // NEW: Sheet for Story Creation
                StoryCreationView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingInterestSearch) { // NEW: Sheet for Interest Search
                InterestSearchView(viewModel: viewModel)
            }
            // Background Color Picker
            .sheet(isPresented: $showingColorPicker) {
                BackgroundColorPickerView(selectedColor: $backgroundColor)
            }
            // Background Photo Picker
            .sheet(isPresented: $showingBackgroundPhotoPicker) {
                BackgroundPhotoPickerView(selectedItem: $selectedBackgroundPhotoItem, backgroundImage: $backgroundImage)
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteAccountAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single column navigation on iPad
        .overlay(
            // Profile and Chat overlays
            Group {
                // Profile overlay
                if showProfileOverlay, let profile = overlayProfile {
                    ZStack {
                        OverlayBackdrop(
                            opacity: 0.5,
                            dismissAnimation: .easeInOut(duration: 0.2),
                            onDismiss: {
                                showProfileOverlay = false
                                overlayProfile = nil
                            }
                        )

                        ProfileOverlayView(
                            userProfile: profile,
                            viewModel: viewModel,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                            },
                            onChat: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                                // Delay to allow profile overlay to close before opening chat
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        chatOverlayRecipientID = profile.deviceID
                                        showChatOverlay = true
                                    }
                                }
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                // Chat overlay
                if showChatOverlay, let recipientID = chatOverlayRecipientID {
                    ZStack {
                        OverlayBackdrop(
                            opacity: 0.5,
                            dismissAnimation: .spring(response: 0.6, dampingFraction: 0.8),
                            onDismiss: {
                                showChatOverlay = false
                                chatOverlayRecipientID = nil
                            }
                        )

                        ChatOverlayView(
                            viewModel: viewModel,
                            recipientDeviceID: recipientID,
                            onClose: {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    showChatOverlay = false
                                    chatOverlayRecipientID = nil
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                            removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom))
                        ))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showProfileOverlay)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showChatOverlay)
        )
    }
    
    @MainActor
    func refreshGrid() async {
        // Call the viewModel's refresh method
        viewModel.refreshPublicGrid()
        
        return await withCheckedContinuation { continuation in
            // Give it a moment to refresh, then complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }
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
