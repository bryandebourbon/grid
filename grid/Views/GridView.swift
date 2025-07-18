import SwiftUI
import CloudKit // For CKAsset
import PhotosUI // For PhotosPicker
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

// Helper to load image from CKAsset
@MainActor // Ensure UI updates are on the main thread
class ImageLoader: ObservableObject {
    @Published var image: Image? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private var currentAsset: CKAsset?
    private var imageLoadingTask: Task<Void, Never>? // Store the task to allow cancellation

    func loadImage(from asset: CKAsset?) {
        guard let asset = asset else {
            self.image = nil
            self.currentAsset = nil
            return
        }
        // Avoid reloading the same asset if already loaded or loading
        guard asset.fileURL?.absoluteString != currentAsset?.fileURL?.absoluteString || image == nil else { return }
        
        isLoading = true
        self.currentAsset = asset
        self.errorMessage = nil

        // Cancel any existing task before starting a new one
        imageLoadingTask?.cancel()

        imageLoadingTask = Task {
            do {
                var validFileURL: URL?
                
                // First, check if we have a valid fileURL that points to an existing file
                if let fileURL = asset.fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                    validFileURL = fileURL
                } else {
                    // The asset's fileURL is either nil or points to a non-existent file
                    // This commonly happens with CloudKit assets that need to be downloaded
                    print("ImageLoader: CKAsset fileURL is missing or invalid. Attempting to handle CloudKit asset...")
                    
                    // For CloudKit assets, we need to ensure the file is downloaded
                    // Unfortunately, CKAsset doesn't provide a direct download method in client code
                    // The download typically happens automatically when the record is fetched with the proper options
                    
                    // If we still don't have a valid fileURL after checking, we'll have to throw an error
                    throw NSError(domain: "ImageLoader", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "CKAsset file is not available locally. This may be due to the asset not being downloaded from CloudKit, or the original temp file being deleted."
                    ])
                }
                
                // Load the image data from the valid file URL
                guard let finalFileURL = validFileURL else {
                    throw NSError(domain: "ImageLoader", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No valid file URL available for CKAsset."
                    ])
                }
                
                let data = try Data(contentsOf: finalFileURL)
                #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create UIImage from the asset data."
                    ])
                }
                #else
                // For macOS or other platforms without UIKit
                guard let nsImage = NSImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create NSImage from the asset data."
                    ])
                }
                let uiImage = nsImage
                #endif
                
                // Successfully loaded image
                await MainActor.run {
                    #if canImport(UIKit)
                    self.image = Image(uiImage: uiImage)
                    #else
                    self.image = Image(nsImage: uiImage) // uiImage is actually nsImage on macOS
                    #endif
                    self.isLoading = false
                }
                
            } catch {
                print("Failed to load image from CKAsset: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Could not load image."
                    self.image = nil // Clear previous image on error
                    self.isLoading = false
                }
            }
        }
    }

    func cancel() {
        imageLoadingTask?.cancel()
        isLoading = false // Optionally reset loading state
        // currentAsset = nil // Optionally clear current asset
        print("ImageLoader: Cancelled image loading task.")
    }
}

// Define an Identifiable struct for the chat recipient
struct ChatRecipient: Identifiable {
    let id: String // Represents the deviceID
}

// Define an Identifiable struct for the profile card
struct ProfileCardUser: Identifiable { // NEW
    let id: String // deviceID of the user whose profile to show
    let userProfile: UserProfile // The actual profile
}

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
    @State private var showInterestsOnGrid = false  // NEW: Toggle for showing interests on grid cells (off by default)
    @State private var showInterestsFilter = true  // NEW: Toggle for showing interests filter section (on by default)
    @State private var storiesMode = UserDefaults.standard.object(forKey: "storiesMode") as? Bool ?? false  // NEW: Stories mode (default: off)
    @State private var useCircularPhotos = UserDefaults.standard.object(forKey: "circularPhotos") as? Bool ?? true  // NEW: Circular photos (default: on)
    @State private var gridColumns: Int = 3 // Dynamic column count
    @State private var showingStoryCreation = false  // NEW: For story creation sheet
    @State private var showingBioStoriesOverlay = false  // NEW: For bio+stories overlay
    @State private var bioStoriesProfile: UserProfile? = nil  // NEW: Profile for bio+stories overlay
    
    // Computed property for actual photo shape based on stories mode and circular photos setting
    private var shouldUseCircularPhotos: Bool {
        if storiesMode {
            return true // Always circular in stories mode
        } else {
            return useCircularPhotos // Use manual setting in non-stories mode
        }
    }
    @State private var baseColumns: Int = 3 // The confirmed column count
    @State private var currentScale: CGFloat = 1.0
    @State private var isScaling = false
    // NEW: State for double-tap and swipe gestures
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var lastTapTime: Date = Date()
    @State private var tapCount = 0
    @State private var dragStartTime: Date = Date()
    @State private var dragVelocity: CGFloat = 0
    @State private var isLongPressing = false
    @State private var longPressStarted = false
    var signOutAction: () -> Void
    var deleteAccountAction: () -> Void

    @State private var showingDeleteConfirmation = false
    
    // Define column count limits
    private let minColumns = 2
    private let maxColumns = 5
    
    // Calculate preview columns based on scale
    private func previewColumns(for scale: CGFloat) -> Int {
        let scaleThreshold: CGFloat = 0.25
        let columnDelta = Int((1.0 - scale) / scaleThreshold)
        let previewCols = baseColumns + columnDelta
        return max(minColumns, min(maxColumns, previewCols))
    }
    
    // NEW: Handle double-tap zoom (like maps)
    private func handleDoubleTap() {
        let currentTime = Date()
        let timeSinceLastTap = currentTime.timeIntervalSince(lastTapTime)
        
        print("GridView: 🎯 Double-tap detected")
        print("GridView: ⏱️ Time since last tap: \(timeSinceLastTap)s")
        print("GridView: 📱 Current state - isDragging: \(isDragging), isLongPressing: \(isLongPressing)")
        print("GridView: 📐 Current columns: \(gridColumns), baseColumns: \(baseColumns)")
        
        lastTapTime = currentTime
        
        let currentColumns = gridColumns
        var targetColumns: Int
        
        // Double-tap cycle: 3 -> 2 -> 5 -> 3 (zoom in, zoom in more, zoom out)
        if currentColumns == 3 {
            targetColumns = 2 // Zoom in
        } else if currentColumns == 2 {
            targetColumns = 5 // Zoom out to max
        } else {
            targetColumns = 3 // Return to default
        }
        
        print("GridView: 🔄 Double-tap zoom transition: \(currentColumns) -> \(targetColumns) columns")
        
        // Haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            gridColumns = targetColumns
            baseColumns = targetColumns
        }
        
        print("GridView: ✅ Double-tap zoom completed")
    }
    
    // NEW: Handle drag-based zoom with velocity detection
    private func handleDragZoom(_ dragValue: DragGesture.Value) {
        let currentTime = Date()
        let timeSinceStart = currentTime.timeIntervalSince(dragStartTime)
        
        // Calculate velocity (pixels per second)
        let distance = sqrt(pow(dragValue.translation.width, 2) + pow(dragValue.translation.height, 2))
        let velocity = timeSinceStart > 0 ? distance / timeSinceStart : 0
        
        print("GridView: 📊 Drag stats - Distance: \(Int(distance))px, Time: \(String(format: "%.2f", timeSinceStart))s, Velocity: \(Int(velocity))px/s")
        
        // Fast swipe detection - if velocity is too high, don't zoom
        let fastSwipeThreshold: CGFloat = 500 // pixels per second
        if velocity > fastSwipeThreshold {
            print("GridView: 🚀 Fast swipe detected (\(Int(velocity))px/s > \(Int(fastSwipeThreshold))px/s) - ignoring zoom")
            return
        }
        
        // Only proceed with zoom if it's a deliberate slow drag
        let sensitivity: CGFloat = 200 // Pixels needed for one column change
        let verticalDelta = -dragValue.translation.height // Negative because up = zoom in
        let columnChange = Int(verticalDelta / sensitivity)
        
        let newColumns = max(minColumns, min(maxColumns, baseColumns + columnChange))
        
        if newColumns != gridColumns {
            print("GridView: 🔍 Zoom change: \(gridColumns) -> \(newColumns) columns (delta: \(Int(verticalDelta))px)")
            
            // Haptic feedback on column change
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            #endif
            
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                gridColumns = newColumns
            }
        }
    }

    var body: some View {
        ZStack {
            // Main grid content
            mainGridView
            
            // Bio+Stories overlay
            if showingBioStoriesOverlay, let profile = bioStoriesProfile {
                // Semi-transparent background to show grid underneath
                Color.black.opacity(0.3) // Dimmed but visible
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showingBioStoriesOverlay = false
                            bioStoriesProfile = nil
                        }
                    }
                
                // The actual bio+stories overlay
                BioStoriesOverlayView(
                    viewModel: viewModel,
                    userProfile: profile,
                    onClose: {
                        withAnimation {
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
        .animation(.easeInOut(duration: 0.3), value: showingBioStoriesOverlay)
    }
    
    private var mainGridView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter indicators
                if viewModel.showingStarredOnly || !viewModel.selectedInterestFilter.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if viewModel.showingStarredOnly {
                                FilterChip(
                                    text: "Starred",
                                    icon: "star.fill",
                                    color: .yellow
                                ) {
                                    viewModel.showingStarredOnly = false
                                }
                            }
                            
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
                
                // Comprehensive interests filter pills
                if showInterestsFilter {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Browse All Interests")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Tap to filter")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Search button as first element
                                SearchInterestsButton {
                                    viewModel.showingInterestSearch = true
                                }
                                
                                // Show all interests as pills
                                ForEach(Interest.allCases) { interest in
                                    InterestPillButton(
                                        interest: interest,
                                        isSelected: viewModel.selectedInterestFilter.contains(interest),
                                        isUserInterest: viewModel.currentUserProfile?.interests.contains(interest) ?? false
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            viewModel.toggleInterestFilter(interest)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6).opacity(0.5))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if let profile = viewModel.currentUserProfile {
                    // Grid supports multiple zoom gestures (like Maps):
                    // • Pinch to zoom in/out
                    // • Double-tap for quick zoom in/out 
                    // • Long drag up/down for continuous zoom
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns), spacing: 2) {
                            ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                                GridNodeView(
                                    node: node,
                                    viewModel: viewModel,
                                    showInterests: showInterestsOnGrid,
                                    useCircularPhotos: shouldUseCircularPhotos,
                                    storiesMode: storiesMode,
                                    onProfileTapped: { profile in // For long press and double tap
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
                                    },
                                    onChatTapped: { recipientDeviceID in
                                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                            chatOverlayRecipientID = recipientDeviceID
                                            showChatOverlay = true
                                        }
                                    },
                                    onStoriesTapped: { profile in
                                        print("GridView: 📱 Story tapped for profile: \(profile.deviceID)")
                                        
                                        // Check if it's the current user and they have no stories
                                        if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
                                           profile.deviceID == currentUserDeviceID {
                                            print("GridView: 👤 Current user tapped their own story")
                                            
                                            // Check if current user has active stories
                                            let hasStories = viewModel.hasActiveStories()
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
                                )
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                                .animation(.easeInOut(duration: 0.3), value: viewModel.showingStarredOnly)
                            }
                        }
                        .padding()
                        .onAppear {
                            let totalNodes = viewModel.gridNodes.flatMap { $0 }.count
                            let rowCount = Int(ceil(Double(totalNodes) / Double(gridColumns)))
                            print("GridView Debug: Total nodes: \(totalNodes), Columns: \(gridColumns), Rows: \(rowCount)")
                            print("GridView Debug: isScaling: \(isScaling)")
                        }
                    }
                    .scrollDisabled(isScaling || isDragging) // Disable scroll during pinch or drag zoom
                    .simultaneousGesture(
                        // Existing pinch gesture
                        MagnificationGesture()
                            .onChanged { value in
                                if !isScaling {
                                    isScaling = true
                                    baseColumns = gridColumns
                                    
                                    // Haptic feedback when starting pinch
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    #endif
                                }
                                currentScale = value
                                
                                // Update columns in real-time based on scale
                                let newColumns = previewColumns(for: value)
                                if newColumns != gridColumns {
                                    // Haptic feedback on column change
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    #endif
                                    
                                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                        gridColumns = newColumns
                                    }
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    // Confirm the column count
                                    baseColumns = gridColumns
                                    currentScale = 1.0
                                    isScaling = false
                                }
                                
                                // Final haptic feedback
                                #if os(iOS)
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                #endif
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double-tap gesture for discrete zoom with comprehensive logging
                        print("GridView: 🎯 Double-tap gesture triggered")
                        print("GridView: 🚦 Gesture state check - isDragging: \(isDragging), isLongPressing: \(isLongPressing)")
                        
                        if !isDragging && !isLongPressing {
                            print("GridView: ✅ Conditions met, executing double-tap zoom")
                            handleDoubleTap()
                        } else {
                            print("GridView: ❌ Double-tap blocked - isDragging: \(isDragging), isLongPressing: \(isLongPressing)")
                        }
                    }
                    .simultaneousGesture(
                        // Long press to initiate zoom mode, then drag to zoom
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                print("GridView: 👆 Long press detected - entering zoom mode")
                                isLongPressing = true
                                longPressStarted = true
                                baseColumns = gridColumns
                                
                                // Haptic feedback for long press
                                #if os(iOS)
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                #endif
                            }
                    )
                    .simultaneousGesture(
                        // Drag gesture for zoom (only active after long press)
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                // Only activate drag zoom if long press was detected
                                guard isLongPressing || longPressStarted else {
                                    return
                                }
                                
                                if !isDragging {
                                    isDragging = true
                                    dragStartTime = Date()
                                    print("GridView: 🎯 Drag zoom started (after long press)")
                                    
                                    // Additional haptic feedback when drag starts
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    #endif
                                }
                                
                                handleDragZoom(value)
                            }
                            .onEnded { _ in
                                if isDragging {
                                    print("GridView: 🏁 Drag zoom ended at \(gridColumns) columns")
                                    
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        baseColumns = gridColumns
                                        isDragging = false
                                        isLongPressing = false
                                        longPressStarted = false
                                    }
                                    
                                    // Final haptic feedback
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    #endif
                                } else {
                                    // Reset long press state even if no drag occurred
                                    print("GridView: 🔄 Resetting long press state (no drag)")
                                    isLongPressing = false
                                    longPressStarted = false
                                }
                            }
                    )
                    .refreshable {
                        await refreshGrid()
                    }
                } else {
                    Text("Loading profile or no profile set...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .onAppear {
                // Auto-refresh when grid appears
                viewModel.handleGridAppeared()
                
                // Inform user about new zoom gestures
                print("🔍 Grid Zoom Gestures Available:")
                print("   • Pinch to zoom in/out")
                print("   • Double-tap for quick zoom (cycles: 3→2→5→3 columns)")
                print("   • Long press (0.5s) + drag up/down for continuous zoom")
                print("   • Fast swipes will scroll normally (not zoom)")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        // Interest filter toggle button (moved to leftmost position)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showInterestsFilter.toggle()
                            }
                        }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: showInterestsFilter ? "heart.fill" : "heart")
                                    .font(.body)
                                    .foregroundColor(showInterestsFilter ? .pink : .primary)
                                
                                // Show count badge if filters are active
                                if !viewModel.selectedInterestFilter.isEmpty {
                                    Text("\(viewModel.selectedInterestFilter.count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Circle().fill(Color.pink))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        
                        // Star filter button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.showingStarredOnly.toggle()
                            }
                        }) {
                            Image(systemName: viewModel.showingStarredOnly ? "star.fill" : "star")
                                .font(.body)
                                .foregroundColor(viewModel.showingStarredOnly ? .yellow : .primary)
                        }
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
                        Button(action: { showingConversationsList = true }) {
                            Label("Conversations", systemImage: "message")
                        }
                        
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
                        
                        // Display Settings Section
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showInterestsOnGrid.toggle()
                            }
                        }) {
                            Label(showInterestsOnGrid ? "Hide Interest Emojis" : "Show Interest Emojis", 
                                  systemImage: showInterestsOnGrid ? "tag.fill" : "tag")
                        }
                        
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
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.demoService.toggleDemoMode()
                                // Refresh the grid to show demo users or real users
                                viewModel.refreshPublicGrid()
                            }
                        }) {
                            Label(viewModel.demoService.isDemoMode ? "Exit Demo Mode" : "Demo Mode", 
                                  systemImage: viewModel.demoService.isDemoMode ? "person.3.fill" : "person.3")
                        }
                        
                        // Debug button for demo mode (only show when demo mode is enabled)
                        if viewModel.demoService.isDemoMode {
                            Button(action: {
                                print("GridView: Manually reloading demo photos...")
                                viewModel.demoService.reloadDemoPhotos()
                                // Refresh the grid after reloading photos
                                viewModel.refreshPublicGrid()
                            }) {
                                Label("Reload Demo Photos", systemImage: "arrow.clockwise")
                            }
                            
                            Button(action: {
                                print("GridView: Shuffling demo photos...")
                                viewModel.demoService.shufflePhotos()
                                // Refresh the grid to show reshuffled photos
                                viewModel.refreshPublicGrid()
                            }) {
                                Label("Shuffle Photos", systemImage: "shuffle")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { showingBlockedUsers = true }) {
                            Label("Blocked Users", systemImage: "hand.raised.slash")
                        }
                        
                        Button(action: { showingContactInfo = true }) {
                            Label("Contact Us", systemImage: "envelope")
                        }
                        
                        Button(action: { viewModel.showingPrivacyPolicy = true }) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                        
                        Button(action: { viewModel.showingTrackingPermission = true }) {
                            Label("Tracking Settings", systemImage: "chart.line.uptrend.xyaxis")
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
            .sheet(isPresented: $viewModel.showingTrackingPermission) {  // NEW: Sheet for Tracking Permission
                TrackingPermissionView(privacyService: viewModel.privacyService)
            }
            .sheet(isPresented: $viewModel.showingInterestSearch) { // NEW: Sheet for Interest Search
                InterestSearchView(viewModel: viewModel)
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteAccountAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
            .alert("Account Recreation Required", isPresented: $viewModel.showingAccountRecreationAlert) {
                Button("Delete Account", role: .destructive) { 
                    deleteAccountAction() 
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your account contains unencrypted messages. For security, all messaging is now encrypted. Please delete your account and create a new one to continue using the app with full encryption.")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single column navigation on iPad
        .overlay(
            // Profile and Chat overlays
            Group {
                // Profile overlay
                if showProfileOverlay, let profile = overlayProfile {
                    ZStack {
                        // Semi-transparent background to dim the grid
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                            }
                        
                        // Profile card overlay
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
                        // Semi-transparent background to dim the grid
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    showChatOverlay = false
                                    chatOverlayRecipientID = nil
                                }
                            }
                        
                        // Chat card overlay
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
    private func refreshGrid() async {
        print("GridView: Refreshing grid via pull-to-refresh")
        
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

struct GridNodeView: View {
    let node: GridNode
    let viewModel: GridViewModel
    let showInterests: Bool
    let useCircularPhotos: Bool
    let storiesMode: Bool
    let onProfileTapped: (UserProfile) -> Void // For long press or single tap (when not in stories mode)
    let onChatTapped: (String) -> Void // For double tap
    let onStoriesTapped: (UserProfile) -> Void // For single tap in stories mode
    @StateObject private var imageLoader = ImageLoader()
    @State private var hasUnviewedStories = false

    var body: some View {
        ZStack {
            // Main profile image
            Group {
                if imageLoader.isLoading {
                    ProgressView()
                } else if let loadedImage = imageLoader.image {
                    loadedImage
                        .resizable()
                        .scaledToFill() // Fill the space, might crop
                } else {
                    // Placeholder if no image or failed to load
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(5) // Add some padding to the system image
                        .foregroundColor(Color.gray.opacity(0.5))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity) // Ensure it expands
            .aspectRatio(1, contentMode: .fit)
            .background(Color.gray.opacity(0.1)) // Background for empty or loading states
            .modifier(DynamicClipShape(useCircular: useCircularPhotos)) // Dynamic shape based on setting
            
            // Stories ring overlay (only in stories mode)
            if storiesMode, let profile = node.userProfile {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let hasStories = viewModel.hasActiveStories(for: profile.deviceID)
                    let isCurrentUser = profile.deviceID == viewModel.currentUserProfile?.deviceID
                    
                    StoriesRingView(
                        hasStories: hasStories,
                        hasUnviewedStories: hasUnviewedStories,
                        isCurrentUser: isCurrentUser,
                        size: size
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            
            // Distance and status overlays
            if let profile = node.userProfile {
                VStack {
                    // Top: Distance, star, encryption, and unread message badges
                    HStack {
                        // Distance on top left (or "Me" for current user)
                        if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
                           profile.deviceID == currentUserDeviceID {
                            // "Me" label for current user
                            Text("Me")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            // Distance for other users
                            if let distanceString = viewModel.getDistanceString(to: profile.deviceID) {
                                Text(distanceString)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        
                        // Star indicator 
                        if viewModel.isStarred(profile.deviceID) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.yellow)
                                .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 18, height: 18))
                        }
                        
                        Spacer()
                        
                        // Unread message badge on top right
                        let unreadCount = viewModel.getUnreadMessageCount(from: profile.deviceID)
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color.red)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    
                    Spacer()
                    
                    // Bottom: Block indicator and interests at very bottom
                    VStack(spacing: 2) {
                        // Block indicator 
                        HStack {
                            if viewModel.isBlocked(profile.deviceID) {
                                Image(systemName: "nosign")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        
                        // Interests emojis at the very bottom
                        if showInterests && !profile.interests.isEmpty {
                            GeometryReader { geometry in
                                let cellWidth = geometry.size.width
                                let emojiSize: CGFloat = max(8, min(12, cellWidth / 10)) // Responsive emoji size
                                let maxEmojis = max(3, Int(cellWidth / (emojiSize + 2))) // More emojis for larger cells
                                
                                HStack(spacing: 1) {
                                    ForEach(Array(profile.interests.prefix(maxEmojis).enumerated()), id: \.offset) { index, interest in
                                        Text(interest.emoji)
                                            .font(.system(size: emojiSize))
                                            .opacity(0.9)
                                    }
                                    
                                    // Show "+X" if there are more interests
                                    if profile.interests.count > maxEmojis {
                                        Text("+\(profile.interests.count - maxEmojis)")
                                            .font(.system(size: emojiSize - 1, weight: .medium))
                                            .foregroundColor(.white)
                                            .opacity(0.8)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(0.3))
                                )
                            }
                            .frame(height: 16)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .onAppear {
            imageLoader.loadImage(from: node.userProfile?.profileImage)
            loadStoriesStatus()
        }
        .onChange(of: node.userProfile?.profileImage?.fileURL) { _ in // Try to reload if asset URL changes
            imageLoader.loadImage(from: node.userProfile?.profileImage)
        }
        .onChange(of: storiesMode) { _ in
            loadStoriesStatus()
        }
        .onChange(of: viewModel.storiesService.allActiveStories) { _ in
            loadStoriesStatus()
        }
        // Double tap gesture for chat (must be before single tap)
        .onTapGesture(count: 2) {
            if let userProfile = node.userProfile {
                // Haptic feedback for double tap
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                #endif
                
                // If blocked, show profile instead of trying to chat
                if viewModel.isBlocked(userProfile.deviceID) {
                    onProfileTapped(userProfile)
                } else {
                    let messagingStatus = viewModel.canMessageUser(deviceID: userProfile.deviceID)
                    if messagingStatus.allowed || userProfile.deviceID == viewModel.currentUserProfile?.deviceID {
                        onChatTapped(userProfile.deviceID)
                    } else {
                        print("Cannot message user: \(messagingStatus.reason)")
                        // Optionally show an alert here
                    }
                }
            }
        }
        // Single tap gesture - stories or profile depending on mode
        .onTapGesture {
            if let userProfile = node.userProfile {
                // Haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                #endif
                
                if storiesMode {
                    onStoriesTapped(userProfile)
                } else {
                    onProfileTapped(userProfile)
                }
            }
        }
        // Long press gesture for profile overlay (always shows profile)
        .onLongPressGesture {
            if let userProfile = node.userProfile {
                // Haptic feedback for long press
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                onProfileTapped(userProfile)
            }
        }
    }
    
    private func loadStoriesStatus() {
        guard storiesMode, let profile = node.userProfile else {
            hasUnviewedStories = false
            return
        }
        
        Task {
            let unviewed = await viewModel.hasUnviewedStories(for: profile.deviceID)
            await MainActor.run {
                hasUnviewedStories = unviewed
            }
        }
    }
}

// NEW: Conversations List for instant chat access
struct ConversationsListView: View {
    @ObservedObject var viewModel: GridViewModel
    let onChatSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                let conversations = viewModel.getConversationList()
                
                if conversations.isEmpty {
                    VStack {
                        Image(systemName: "message.circle")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No conversations yet")
                            .foregroundColor(.gray)
                        Text("Tap on someone in the grid to start chatting!")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text("Double tap or long press to view profile")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations, id: \.deviceID) { conversation in
                        ConversationRowView(
                            displayName: conversation.displayName,
                            lastMessage: conversation.lastMessage,
                            messageCount: conversation.messageCount,
                            onTap: {
                                onChatSelected(conversation.deviceID)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct ConversationRowView: View {
    let displayName: String
    let lastMessage: Message?
    let messageCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if messageCount > 0 {
                            Text("\(messageCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let lastMessage = lastMessage {
                        HStack {
                            Text(lastMessage.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            Spacer()
                            
                            Text(lastMessage.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Overlay View (for long press)

struct ProfileOverlayView: View {
    let userProfile: UserProfile
    let viewModel: GridViewModel
    let onClose: () -> Void
    let onChat: () -> Void
    
    @StateObject private var imageLoader = ImageLoader()
    
    private var isCurrentUser: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Close button bar
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding()
            }
            
            // Main content card
            VStack(spacing: 16) {
                // Profile image
                Group {
                    if imageLoader.isLoading {
                        ProgressView()
                            .frame(width: 120, height: 120)
                    } else if let image = imageLoader.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(30)
                                    .foregroundColor(.gray)
                            )
                    }
                }
                
                // Name
                Text(userProfile.deviceName ?? "Unknown User")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Distance (if not current user)
                if !isCurrentUser {
                    if let distanceString = viewModel.getDistanceString(to: userProfile.deviceID) {
                        Text(distanceString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Bio
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(userProfile.bio ?? "No bio available.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.horizontal)
                
                // Action buttons
                HStack(spacing: 16) {
                    // Star button
                    if !isCurrentUser {
                        Button(action: {
                            viewModel.toggleStar(for: userProfile.deviceID)
                        }) {
                            VStack {
                                Image(systemName: viewModel.isStarred(userProfile.deviceID) ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isStarred(userProfile.deviceID) ? .yellow : .gray)
                                Text(viewModel.isStarred(userProfile.deviceID) ? "Starred" : "Star")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Chat button
                    Button(action: onChat) {
                        VStack {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text(isCurrentUser ? "Notes" : "Chat")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    // Block button
                    if !isCurrentUser {
                        Button(action: {
                            viewModel.toggleBlock(for: userProfile.deviceID)
                        }) {
                            VStack {
                                Image(systemName: viewModel.isBlocked(userProfile.deviceID) ? "nosign" : "hand.raised")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isBlocked(userProfile.deviceID) ? .red : .gray)
                                Text(viewModel.isBlocked(userProfile.deviceID) ? "Blocked" : "Block")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Report button
                    if !isCurrentUser {
                        Button(action: {
                            // First close the overlay, then show report dialog
                            onClose()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.selectedUserProfileForReport = ProfileCardUser(id: userProfile.deviceID, userProfile: userProfile)
                            }
                        }) {
                            VStack {
                                Image(systemName: "exclamationmark.shield")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                Text("Report")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.top)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 10)
            .frame(maxWidth: 350)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            imageLoader.loadImage(from: userProfile.profileImage)
        }
    }
}

// MARK: - Profile Card View (NEW)

struct ProfileCardView: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    @Environment(\.dismiss) var dismiss
    let onChatTapped: (String) -> Void

    @State private var bioText: String = ""
    @State private var isEditingBio: Bool = false
    @State private var isEditingInterests: Bool = false
    @State private var selectedInterests: Set<Interest> = []

    // Image loaders for main photo
    @StateObject private var mainImageLoader = ImageLoader()
    
    // Photo editing states
    @State private var selectedMainPhotoData: Data? = nil
    @State private var isSavingPhotos = false
    @State private var isEditingPhoto = false

    private var isCurrentUserProfile: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Profile Photo Section
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Group {
                                if mainImageLoader.isLoading {
                                    ProgressView().frame(width: 120, height: 120)
                                } else if let image = mainImageLoader.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    Circle().fill(Color.gray.opacity(0.3))
                                        .frame(width: 120, height: 120)
                                        .overlay(Image(systemName: "person.fill").resizable().scaledToFit().padding(30).foregroundColor(.gray))
                                }
                            }
                            Spacer()
                        }

                        Text(userProfile.deviceName ?? "User")
                            .font(.title)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // Main photo editing (only for current user)
                        if isCurrentUserProfile {
                            Button("Edit Photo") {
                                isEditingPhoto = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }

                    Divider()

                    // Bio Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Me")
                            .font(.headline)
                        
                        if isCurrentUserProfile {
                            if isEditingBio {
                                TextEditor(text: $bioText)
                                    .frame(height: 100)
                                    .border(Color.gray.opacity(0.5), width: 1)
                                HStack {
                                    Button("Cancel") {
                                        isEditingBio = false
                                        bioText = viewModel.currentUserProfile?.bio ?? ""
                                    }
                                    .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Save Bio") {
                                        isEditingBio = false
                                        viewModel.updateUserProfileBioWithModeration(bio: bioText) { success, error in
                                            if success {
                                                print("Bio updated successfully.")
                                            } else {
                                                print("Failed to update bio: \(error ?? "Unknown error")")
                                                // Show error to user - could add an alert here
                                                bioText = viewModel.currentUserProfile?.bio ?? ""
                                            }
                                        }
                                    }
                                    .foregroundColor(.blue)
                                }
                            } else {
                                Text(bioText.isEmpty ? "No bio yet. Tap to edit." : bioText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        isEditingBio = true
                                    }
                            }
                        } else {
                            Text(userProfile.bio ?? "No bio available.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    Divider()
                    
                    // Interests Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Interests")
                                .font(.headline)
                            
                            Spacer()
                            
                            if isCurrentUserProfile {
                                Button(isEditingInterests ? "Done" : "Edit") {
                                    if isEditingInterests {
                                        // Save interests
                                        saveInterests()
                                    } else {
                                        // Start editing
                                        selectedInterests = Set(viewModel.currentUserProfile?.interests ?? [])
                                    }
                                    isEditingInterests.toggle()
                                }
                                .foregroundColor(.blue)
                                .font(.subheadline)
                            }
                        }
                        
                        if isEditingInterests && isCurrentUserProfile {
                            // Interest editing interface
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Select your interests (\(selectedInterests.count) selected)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(Interest.categories) { category in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(category.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                                                ForEach(category.interests) { interest in
                                                    EditableInterestButton(
                                                        interest: interest,
                                                        isSelected: selectedInterests.contains(interest)
                                                    ) {
                                                        toggleInterest(interest)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            // Display interests
                            let interests = isCurrentUserProfile ? (viewModel.currentUserProfile?.interests ?? []) : userProfile.interests
                            
                            if interests.isEmpty {
                                Text(isCurrentUserProfile ? "No interests selected. Tap Edit to add some." : "No interests listed.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.vertical, 8)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 8) {
                                    ForEach(interests) { interest in
                                        HStack(spacing: 4) {
                                            Text(interest.emoji)
                                                .font(.caption)
                                            Text(interest.rawValue)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Star button
                    if !isCurrentUserProfile {
                        Button(action: {
                            viewModel.toggleStar(for: userProfile.deviceID)
                        }) {
                            Image(systemName: viewModel.isStarred(userProfile.deviceID) ? "star.fill" : "star")
                                .foregroundColor(viewModel.isStarred(userProfile.deviceID) ? .yellow : .primary)
                        }
                    }
                    
                    // Chat Button
                    if !isCurrentUserProfile {
                        Button("Chat") {
                            dismiss()
                            onChatTapped(userProfile.deviceID)
                        }
                    } else {
                        Button("My Notes") {
                            dismiss()
                            onChatTapped(userProfile.deviceID)
                        }
                    }
                    
                    // Block button
                    if !isCurrentUserProfile {
                        Menu {
                            Button(action: {
                                viewModel.toggleBlock(for: userProfile.deviceID)
                            }) {
                                Label(viewModel.isBlocked(userProfile.deviceID) ? "Unblock" : "Block", 
                                      systemImage: viewModel.isBlocked(userProfile.deviceID) ? "nosign" : "hand.raised")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                dismiss()
                                viewModel.selectedUserProfileForReport = ProfileCardUser(id: userProfile.deviceID, userProfile: userProfile)
                            }) {
                                Label("Report User", systemImage: "exclamationmark.shield")
                            }
                            .foregroundColor(.red)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onAppear {
                mainImageLoader.loadImage(from: userProfile.profileImage)
                bioText = isCurrentUserProfile ? (viewModel.currentUserProfile?.bio ?? "") : (userProfile.bio ?? "")
                selectedInterests = Set(isCurrentUserProfile ? (viewModel.currentUserProfile?.interests ?? []) : userProfile.interests)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isEditingPhoto) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Edit Profile Photo")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    CircularPhotoEditor(
                        selectedPhotoData: $selectedMainPhotoData,
                        circleSize: 250,
                        placeholder: "Update Profile Photo",
                        onPhotoChanged: { _ in
                            // Photo was changed, will be saved when user taps Done
                        }
                    )
                    
                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            selectedMainPhotoData = nil
                            isEditingPhoto = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            saveMainPhoto()
                            isEditingPhoto = false
                        }
                        .disabled(selectedMainPhotoData == nil)
                    }
                }
            }
            .onAppear {
                // Initialize with current photo if available
                if let currentImage = userProfile.profileImage,
                   let url = currentImage.fileURL,
                   let data = try? Data(contentsOf: url) {
                    selectedMainPhotoData = data
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleInterest(_ interest: Interest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }
    
    private func saveInterests() {
        viewModel.updateUserProfileInterests(interests: Array(selectedInterests)) { success in
            if success {
                print("Interests updated successfully.")
            } else {
                print("Failed to update interests.")
                // Revert to original interests on failure
                selectedInterests = Set(viewModel.currentUserProfile?.interests ?? [])
            }
        }
    }
    
    // MARK: - Photo Management Functions
    
    private func saveMainPhoto() {
        guard let photoData = selectedMainPhotoData else { return }
        
        isSavingPhotos = true
        
        viewModel.updateCurrentProfileImageWithModeration(newPhotoData: photoData)
        
        // Reload the main image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            mainImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
            selectedMainPhotoData = nil
            isSavingPhotos = false
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(userID: "previewUser123", 
                                       deviceID: "previewDeviceID_789", 
                                       deviceName: "Preview Device", 
                                       profileImage: nil as CKAsset?)
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        if !mockViewModel.gridNodes.isEmpty && !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        
        return GridView(viewModel: mockViewModel, signOutAction: {}, deleteAccountAction: {})
    }
}

// MARK: - Filter Components

struct FilterChip: View {
    let text: String
    let icon: String?
    let color: Color
    let emoji: String?
    let onRemove: () -> Void
    
    init(text: String, icon: String? = nil, color: Color, emoji: String? = nil, onRemove: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.color = color
        self.emoji = emoji
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let emoji = emoji {
                Text(emoji)
                    .font(.caption)
            } else if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct InterestFilterSheet: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Text("Filter by Interests")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Find people who share your interests")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if !viewModel.selectedInterestFilter.isEmpty {
                            Text("\(viewModel.selectedInterestFilter.count) interests selected")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                    
                    // Show user's own interests first
                    if let userInterests = viewModel.currentUserProfile?.interests, !userInterests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Interests")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                ForEach(userInterests) { interest in
                                    InterestFilterButton(
                                        interest: interest,
                                        isSelected: viewModel.selectedInterestFilter.contains(interest),
                                        isUserInterest: true
                                    ) {
                                        viewModel.toggleInterestFilter(interest)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    
                    // All interest categories
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Interest.categories) { category in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(category.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                    ForEach(category.interests) { interest in
                                        InterestFilterButton(
                                            interest: interest,
                                            isSelected: viewModel.selectedInterestFilter.contains(interest),
                                            isUserInterest: viewModel.currentUserProfile?.interests.contains(interest) ?? false
                                        ) {
                                            viewModel.toggleInterestFilter(interest)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Interest Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.selectedInterestFilter.isEmpty {
                        Button("Clear All") {
                            viewModel.clearInterestFilter()
                        }
                    }
                }
            }
        }
    }
}

struct InterestFilterButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 14))
                Text(interest.rawValue)
                    .font(.system(size: 13, weight: .medium))
                
                if isUserInterest {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return Color.blue.opacity(0.1)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isUserInterest {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return .blue.opacity(0.3)
        } else {
            return .clear
        }
    }
}

// MARK: - Editable Interest Button for Profile Editing

struct EditableInterestButton: View {
    let interest: Interest
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 12))
                Text(interest.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Interests Button for Magnifying Glass

struct SearchInterestsButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                Text("Search")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Interest Pill Button for Main Grid Filter

struct InterestPillButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(interest.emoji)
                    .font(.system(size: 12))
                Text(interest.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                // Show user indicator if this is one of the user's interests
                if isUserInterest {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return Color.blue.opacity(0.1)
        } else {
            return Color(.systemBackground)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isUserInterest {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return .blue.opacity(0.5)
        } else {
            return Color(.systemGray4)
        }
    }
}

// MARK: - Interest Search View

struct InterestSearchView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    
    // Computed property for filtered interests based on search
    private var filteredInterests: [Interest] {
        if searchText.isEmpty {
            return Interest.allCases
        } else {
            return Interest.allCases.filter { interest in
                interest.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search interests...", text: $searchText)
                            .focused($searchFieldFocused)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Selected interests "pile up" display
                    if !viewModel.selectedInterestFilter.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Filters (\(viewModel.selectedInterestFilter.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(viewModel.selectedInterestFilter), id: \.self) { interest in
                                        SelectedInterestChip(interest: interest) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                viewModel.removeInterestFilter(interest)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                Divider()
                
                // Search results or all interests
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                        ForEach(filteredInterests) { interest in
                            SearchableInterestButton(
                                interest: interest,
                                isSelected: viewModel.selectedInterestFilter.contains(interest),
                                isUserInterest: viewModel.currentUserProfile?.interests.contains(interest) ?? false
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.toggleInterestFilter(interest)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Search Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.selectedInterestFilter.isEmpty {
                        Button("Clear All") {
                            viewModel.clearInterestFilter()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                searchFieldFocused = true
            }
        }
    }
}

// MARK: - Selected Interest Chip for "Pile Up" Display

struct SelectedInterestChip: View {
    let interest: Interest
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(interest.emoji)
                .font(.system(size: 12))
            Text(interest.rawValue)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .foregroundColor(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Searchable Interest Button

struct SearchableInterestButton: View {
    let interest: Interest
    let isSelected: Bool
    let isUserInterest: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(interest.emoji)
                    .font(.system(size: 16))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(interest.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    
                    if isUserInterest {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text("Your Interest")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .blue)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return Color.blue.opacity(0.1)
        } else {
            return Color(.systemBackground)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isUserInterest {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isUserInterest {
            return .blue.opacity(0.5)
        } else {
            return Color(.systemGray4)
        }
    }
}

// MARK: - Chat Overlay View (Card-based Chat Interface)

struct ChatOverlayView: View {
    @ObservedObject var viewModel: GridViewModel
    let recipientDeviceID: String
    let onClose: () -> Void
    
    // Helper to get recipient display name
    private func recipientDisplayName() -> String {
        if recipientDeviceID == viewModel.currentUserProfile?.deviceID {
            return "My Notes"
        }
        
        // Find the recipient's profile to get their display name
        for row in viewModel.gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                    return profile.deviceName ?? "User"
                }
            }
        }
        return "Chat"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(recipientDisplayName())
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if recipientDeviceID != viewModel.currentUserProfile?.deviceID {
                        if let distanceString = viewModel.getDistanceString(to: recipientDeviceID) {
                            Text(distanceString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Menu button
                Menu {
                    if recipientDeviceID != viewModel.currentUserProfile?.deviceID {
                        Button(action: {
                            // Find the recipient's profile
                            for row in viewModel.gridNodes {
                                for node in row {
                                    if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                                        onClose()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            viewModel.selectedUserProfileForReport = ProfileCardUser(id: recipientDeviceID, userProfile: profile)
                                        }
                                        return
                                    }
                                }
                            }
                        }) {
                            Label("Report User", systemImage: "exclamationmark.shield")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            
            // Chat content
            ChatView(viewModel: viewModel, recipientDeviceID: recipientDeviceID)
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .frame(maxWidth: min(400, UIScreen.main.bounds.width - 40))
        .frame(maxHeight: min(600, UIScreen.main.bounds.height - 100))
        .padding(.bottom, 20)
        .onAppear {
            // When the view appears, ensure the viewModel knows which device we're chatting with
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            print("ChatOverlayView: Opened chat with \(recipientDeviceID)")
            
            // Mark all messages from this device as read
            viewModel.markMessagesAsRead(from: recipientDeviceID)
        }
    }
}

// MARK: - Dynamic Clip Shape Modifier

struct DynamicClipShape: ViewModifier {
    let useCircular: Bool
    
    func body(content: Content) -> some View {
        if useCircular {
            content.clipShape(Circle())
        } else {
            content.clipShape(Rectangle())
        }
    }
}
