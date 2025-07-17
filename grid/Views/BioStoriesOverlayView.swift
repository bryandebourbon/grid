import SwiftUI

struct BioStoriesOverlayView: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    let onClose: () -> Void
    let onChatTapped: (String) -> Void
    
    @State private var stories: [Story] = []
    @State private var currentStoryIndex: Int = 0
    @State private var isLoading = true
    @State private var storyProgress: Double = 0.0
    @StateObject private var imageLoader = ImageLoader()
    @StateObject private var profileImageLoader = ImageLoader()
    
    // Timer for auto-advancing stories
    @State private var storyTimer: Timer?
    private let storyDuration: TimeInterval = 5.0
    
    // Pin action feedback
    @State private var showingPinAlert = false
    @State private var pinAlertMessage = ""
    @State private var pinAlertTitle = ""
    
    // Track pinned stories to avoid repeated method calls
    @State private var pinnedStories: Set<String> = []
    
    private var isCurrentUser: Bool {
        return viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }
    
    private var currentStory: Story? {
        guard currentStoryIndex < stories.count else { return nil }
        return stories[currentStoryIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section with user info and close button
            HStack {
                // User info
                HStack(spacing: 12) {
                    // Profile photo
                    Group {
                        if profileImageLoader.isLoading {
                            ProgressView()
                                .frame(width: 40, height: 40)
                        } else if let image = profileImageLoader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(10)
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userProfile.deviceName ?? "Unknown User")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if !isCurrentUser {
                            if let distanceString = viewModel.getDistanceString(to: userProfile.deviceID) {
                                Text(distanceString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("You")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 16) {
                    // Chat button
                    Button(action: {
                        onChatTapped(userProfile.deviceID)
                    }) {
                        Image(systemName: "message.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    
                    // Star button (only for other users)
                    if !isCurrentUser {
                        Button(action: {
                            viewModel.toggleStar(for: userProfile.deviceID)
                        }) {
                            Image(systemName: viewModel.isStarred(userProfile.deviceID) ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundColor(viewModel.isStarred(userProfile.deviceID) ? .yellow : .gray)
                        }
                    }
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Stories section
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("Loading stories...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
            } else if stories.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text(isCurrentUser ? "No Stories Yet" : "No Stories")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(isCurrentUser ? "Create your first story!" : "This user hasn't shared any stories.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
            } else {
                // Story display with navigation
                ZStack {
                    // Story image
                    Group {
                        if imageLoader.isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                Text("Loading image...")
                                    .foregroundColor(.white)
                            }
                        } else if let loadedImage = imageLoader.image {
                            loadedImage
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 300)
                        } else {
                            // Error state
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.red)
                                Text("Failed to Load Story")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipped()
                    
                    // Story controls overlay
                    VStack {
                        // Progress bars at top
                        HStack(spacing: 4) {
                            ForEach(0..<stories.count, id: \.self) { index in
                                ProgressView(value: progressForStory(at: index))
                                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                    .scaleEffect(x: 1, y: 2, anchor: .center)
                                    .background(Color.white.opacity(0.3))
                                    .cornerRadius(2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        Spacer()
                        
                        // Caption if available
                        if let caption = currentStory?.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                    
                    // Navigation tap areas
                    HStack(spacing: 0) {
                        // Left tap area - previous story
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                previousStory()
                            }
                        
                        // Right tap area - next story
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                nextStory()
                            }
                    }
                }
            }
            
            // Stories thumbnail scroll view (only show if there are stories)
            if !stories.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("Stories")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(currentStoryIndex + 1) of \(stories.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                                StoryThumbnailView(
                                    story: story,
                                    isSelected: index == currentStoryIndex,
                                    isPinned: pinnedStories.contains(story.id),
                                    isCurrentUser: isCurrentUser,
                                    onTapped: {
                                        print("BioStoriesOverlayView: 👆 Story thumbnail tapped: \(story.id)")
                                        // Jump to selected story
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            markCurrentStoryAsViewed() // Mark current as viewed before switching
                                            currentStoryIndex = index
                                        }
                                    },
                                    onLongPress: { story in
                                        print("BioStoriesOverlayView: 🔥 Story thumbnail long-pressed: \(story.id)")
                                        // Handle pin/unpin action
                                        Task {
                                            await handlePinAction(for: story)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.systemGray6).opacity(0.5))
            }
            
            // Bio section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bio")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    // Bio indicator
                    if let bio = userProfile.bio, !bio.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(userProfile.bio ?? "No bio available.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .frame(maxWidth: 400)
        .onAppear {
            profileImageLoader.loadImage(from: userProfile.profileImage)
            setupStoryViewing()
            
            // Load pinned stories for current user
            Task {
                await loadPinnedStories()
            }
        }
        .onDisappear {
            cleanupStoryViewing()
        }
        .onChange(of: currentStoryIndex) { _ in
            loadCurrentStoryImage()
            restartStoryTimer()
        }
        .alert(pinAlertTitle, isPresented: $showingPinAlert) {
            Button("OK") { }
        } message: {
            Text(pinAlertMessage)
        }
    }
    
    private func setupStoryViewing() {
        Task {
            await loadStories()
        }
    }
    
    private func cleanupStoryViewing() {
        storyTimer?.invalidate()
        storyTimer = nil
        imageLoader.cancel()
    }
    
    private func loadStories() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let result = await viewModel.getStoriesForDevice(userProfile.deviceID)
            
            await MainActor.run {
                self.stories = result.stories.sorted { $0.timestamp > $1.timestamp }
                self.isLoading = false
                
                if !stories.isEmpty {
                    loadCurrentStoryImage()
                    startStoryTimer()
                }
            }
        } catch {
            await MainActor.run {
                print("BioStoriesOverlayView: Error loading stories: \(error)")
                isLoading = false
            }
        }
    }
    
    private func loadCurrentStoryImage() {
        guard let story = currentStory else {
            return
        }
        
        if let imageAsset = story.imageAsset {
            imageLoader.loadImage(from: imageAsset)
        } else {
            imageLoader.loadImage(from: nil)
        }
    }
    
    private func startStoryTimer() {
        guard !stories.isEmpty else { return }
        
        storyProgress = 0.0
        storyTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            storyProgress += 0.1 / storyDuration
            
            if storyProgress >= 1.0 {
                nextStory()
            }
        }
    }
    
    private func restartStoryTimer() {
        storyTimer?.invalidate()
        startStoryTimer()
    }
    
    private func previousStory() {
        markCurrentStoryAsViewed()
        
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
        } else {
            onClose()
        }
    }
    
    private func nextStory() {
        markCurrentStoryAsViewed()
        
        if currentStoryIndex < stories.count - 1 {
            currentStoryIndex += 1
        } else {
            onClose()
        }
    }
    
    private func progressForStory(at index: Int) -> Double {
        if index < currentStoryIndex {
            return 1.0 // Completed
        } else if index == currentStoryIndex {
            return storyProgress // Current progress
        } else {
            return 0.0 // Not started
        }
    }
    
    private func markCurrentStoryAsViewed() {
        guard let currentStory = currentStory else { return }
        
        Task {
            await viewModel.viewStory(currentStory)
        }
    }
    
    /// Load pinned stories for current user
    private func loadPinnedStories() async {
        guard isCurrentUser else { return }
        
        // Create album if needed first
        await viewModel.createAlbumIfNeeded()
        
        // Get current user's album
        if let currentProfile = viewModel.currentUserProfile,
           let album = await viewModel.getAlbum(for: currentProfile.deviceID) {
            let pinnedStoryIDs = Set(album.photoMetadata.map { $0.storyID })
            await MainActor.run {
                pinnedStories = pinnedStoryIDs
            }
        }
    }
    
    /// Refresh stories after unpinning to remove expired stories that are no longer protected by pins
    private func refreshStoriesAfterUnpin(unpinnedStoryID: String) async {
        // Reload stories from CloudKit (which automatically filters expired ones)
        let result = await viewModel.getStoriesForDevice(userProfile.deviceID)
        
        await MainActor.run {
            let filteredStories = result.stories.sorted { $0.timestamp > $1.timestamp }
            
            // Check if the unpinned story should be removed (if expired)
            let storyStillExists = filteredStories.contains { $0.id == unpinnedStoryID }
            
            if !storyStillExists {
                print("BioStoriesOverlayView: 🗑️ Unpinned story \(unpinnedStoryID) was expired and removed from view")
            }
            
            // Update stories list
            self.stories = filteredStories
            
            // If we removed the current story and it was the last one, go to previous
            if currentStoryIndex >= stories.count && currentStoryIndex > 0 {
                currentStoryIndex = stories.count - 1
            }
            
            // If no stories left, close the overlay
            if stories.isEmpty {
                print("BioStoriesOverlayView: 📪 No stories remaining after unpin, closing overlay")
                onClose()
            } else {
                // Reload current story image
                loadCurrentStoryImage()
                restartStoryTimer()
            }
        }
    }
    
    /// Handle pin/unpin action for a story
    /// - For unpinned stories: Pins them to the user's album (permanent storage)
    /// - For pinned stories: Unpins them from album (will disappear if expired)
    private func handlePinAction(for story: Story) async {
        print("BioStoriesOverlayView: 📌 handlePinAction called for story \(story.id)")
        
        let isPinned = pinnedStories.contains(story.id)
        print("BioStoriesOverlayView: 📌 Story is currently pinned: \(isPinned)")
        
        if isPinned {
            // Unpin the story
            print("BioStoriesOverlayView: 📌 Unpinning story \(story.id)")
            let result = await viewModel.unpinStoryFromAlbum(story)
            
            await MainActor.run {
                if result.success {
                    pinAlertTitle = "Unpinned!"
                    pinAlertMessage = "Story removed from your album."
                    // Update local state
                    pinnedStories.remove(story.id)
                    
                    // Refresh stories to check if unpinned expired stories should disappear
                    Task {
                        await refreshStoriesAfterUnpin(unpinnedStoryID: story.id)
                    }
                } else {
                    pinAlertTitle = "Error"
                    pinAlertMessage = result.error ?? "Failed to unpin story."
                }
                showingPinAlert = true
            }
        } else {
            // Pin the story
            print("BioStoriesOverlayView: 📌 Pinning story \(story.id)")
            let result = await viewModel.pinStoryToAlbum(story)
            
            await MainActor.run {
                if result.success {
                    pinAlertTitle = "Pinned!"
                    pinAlertMessage = "Story added to your album."
                    // Update local state
                    pinnedStories.insert(story.id)
                } else if result.albumFull {
                    pinAlertTitle = "Album Full"
                    pinAlertMessage = "Your album can only hold \(Album.maxPhotos) photos. Remove some to add more."
                } else if result.alreadyPinned {
                    pinAlertTitle = "Already Pinned"
                    pinAlertMessage = "This story is already in your album."
                } else {
                    pinAlertTitle = "Error"
                    pinAlertMessage = result.error ?? "Failed to pin story."
                }
                showingPinAlert = true
            }
        }
    }
}

// MARK: - Story Thumbnail View

struct StoryThumbnailView: View {
    let story: Story
    let isSelected: Bool
    let isPinned: Bool
    let isCurrentUser: Bool
    let onTapped: () -> Void
    let onLongPress: (Story) -> Void
    
    @StateObject private var thumbnailImageLoader = ImageLoader()
    
    var body: some View {
        ZStack {
            // Thumbnail image
            Group {
                if thumbnailImageLoader.isLoading {
                    ProgressView()
                        .frame(width: 60, height: 80)
                } else if let image = thumbnailImageLoader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 80)
                        .clipped()
                } else {
                    // Placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.gray)
                        )
                }
            }
            .cornerRadius(8)
            
            // Selection border
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 60, height: 80)
            }
            
            // Caption and pin indicators
            VStack {
                // Pin indicator at top right
                if isPinned {
                    HStack {
                        Spacer()
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 18, height: 18)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(4)
                    }
                }
                
                Spacer()
                
                // Caption indicator at bottom right
                if let caption = story.caption, !caption.isEmpty {
                    HStack {
                        Spacer()
                        Image(systemName: "text.bubble.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 16, height: 16)
                            )
                            .padding(4)
                    }
                }
            }
        }
        .onTapGesture {
            print("StoryThumbnailView: 👆 Tap gesture detected on story \(story.id)")
            onTapped()
        }
        .onLongPressGesture {
            print("StoryThumbnailView: 🔥 Long press detected on story \(story.id)")
            print("StoryThumbnailView: 👤 isCurrentUser: \(isCurrentUser)")
            print("StoryThumbnailView: 📌 isPinned: \(isPinned)")
            
            // Only allow pinning for current user's own stories in Phase 1
            if isCurrentUser {
                print("StoryThumbnailView: ✅ Current user - proceeding with pin action")
                
                // Haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                print("StoryThumbnailView: 📳 Haptic feedback triggered")
                #endif
                
                onLongPress(story)
            } else {
                print("StoryThumbnailView: ❌ Not current user - ignoring long press")
            }
        }
        .onAppear {
            thumbnailImageLoader.loadImage(from: story.imageAsset)
            print("StoryThumbnailView: 📱 Thumbnail appeared for story \(story.id)")
            print("StoryThumbnailView: 👤 isCurrentUser: \(isCurrentUser)")
            print("StoryThumbnailView: 📌 isPinned: \(isPinned)")
            print("StoryThumbnailView: ✅ isSelected: \(isSelected)")
        }
    }
}

struct BioStoriesOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with sample user profile
        let sampleProfile = UserProfile(
            userID: "sample-user",
            deviceID: "sample-device",
            deviceName: "Sample User",
            bio: "This is a sample bio that shows how the text will appear in the overlay view."
        )
        
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()
            
            BioStoriesOverlayView(
                viewModel: GridViewModel(),
                userProfile: sampleProfile,
                onClose: {},
                onChatTapped: { _ in }
            )
            .padding(.horizontal, 40)
        }
    }
} 