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
    
    private var isCurrentUser: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
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
        }
        .onDisappear {
            cleanupStoryViewing()
        }
        .onChange(of: currentStoryIndex) { _ in
            loadCurrentStoryImage()
            restartStoryTimer()
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