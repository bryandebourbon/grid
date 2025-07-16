import SwiftUI

struct StoryViewerView: View {
    @ObservedObject var viewModel: GridViewModel
    let deviceID: String
    /// Closure provided by parent to dismiss the viewer (e.g., flip Boolean in GridView).
    /// Always call this when the viewer should close.
    let onClose: () -> Void

    // Fallback for cases where StoryViewerView is presented with a sheet
    @Environment(\.dismiss) private var envDismiss
    @State private var stories: [Story] = []
    @State private var currentStoryIndex: Int = 0
    @State private var isLoading = true
    @State private var storyProgress: Double = 0.0
    @State private var isCurrentUserViewing: Bool = false
    @StateObject private var imageLoader = ImageLoader()
    @State private var debugInfo: String = "Initializing..."
    
    // Timer for auto-advancing stories
    @State private var storyTimer: Timer?
    
    private let storyDuration: TimeInterval = 5.0 // 5 seconds per story
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            if isLoading {
                // Loading state with debug info
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Loading stories...")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Device: \(deviceID)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // Debug info
                    Text(debugInfo)
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    // Manual dismiss button during loading
                    Button("Cancel Loading") {
                        print("StoryViewerView: Cancel loading button tapped")
                        closeViewer()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.top, 20)
                }
            } else if stories.isEmpty {
                // No stories state
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("No Stories Available")
                        .font(.title2)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                    
                    Text("This user doesn't have any active stories right now.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // Debug info
                    Text("Debug: \(debugInfo)")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Button("Close") {
                        print("StoryViewerView: Close button tapped (no stories)")
                        closeViewer()
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(25)
                    .padding(.top, 20)
                }
            } else {
                // Story display
                storyDisplayView
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .onAppear {
            print("StoryViewerView: 🎬 onAppear called - Starting setup")
            debugInfo = "onAppear called, setting up..."
            setupStoryViewing()
        }
        .onDisappear {
            print("StoryViewerView: 👋 onDisappear called")
            cleanupStoryViewing()
        }
    }
    
    private var storyDisplayView: some View {
        ZStack {
            // Main story image
            Group {
                if imageLoader.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2.0)
                        
                        Text("Loading image...")
                            .foregroundColor(.white)
                        
                        Text("Debug: \(debugInfo)")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else if let loadedImage = imageLoader.image {
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    // Error state
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("Failed to Load Story")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("There was an error loading this story image.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        
                        Text("Debug: \(debugInfo)")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button("Close Story Viewer") {
                            print("StoryViewerView: Close button tapped (error state)")
                            closeViewer()
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(25)
                        .padding(.top, 20)
                    }
                }
            }
            
            // Story controls overlay (only show if image loaded successfully)
            if imageLoader.image != nil {
                VStack {
                    // Top section with progress and close button
                    VStack(spacing: 12) {
                        // Progress bars
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
                        
                        // Header with user info and close button
                        HStack {
                            // User info (simplified for now)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(isCurrentUserViewing ? "You" : "User")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.black)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isCurrentUserViewing ? "Your Story" : "Story")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    
                                    Text(timeAgoString(from: currentStory?.timestamp ?? Date()))
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            
                            Spacer()
                            
                            // Close button
                            Button(action: {
                                print("StoryViewerView: Close button tapped")
                                closeViewer()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // Caption if available
                    if let caption = currentStory?.caption, !caption.isEmpty {
                        VStack {
                            Spacer()
                            
                            Text(caption)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                        }
                    }
                }
                
                // Invisible tap areas for navigation (only when image is loaded)
                // Exclude top 120 points to avoid interfering with controls
                VStack(spacing: 0) {
                    // Top safe area (for controls) - no taps
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 120)
                    
                    // Navigation tap area (below controls)
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
        }
        .onAppear {
            print("StoryViewerView: 📱 storyDisplayView appeared, loading current story")
            loadCurrentStoryImage()
            startStoryTimer()
        }
        .onChange(of: currentStoryIndex) { _ in
            print("StoryViewerView: 📊 Story index changed to \(currentStoryIndex)")
            loadCurrentStoryImage()
            restartStoryTimer()
        }
    }
    
    private var currentStory: Story? {
        guard currentStoryIndex < stories.count else { return nil }
        return stories[currentStoryIndex]
    }
    
    private func setupStoryViewing() {
        print("StoryViewerView: 🎬 Setting up story viewing for deviceID: \(deviceID)")
        debugInfo = "Setting up for device: \(deviceID)"
        isCurrentUserViewing = deviceID == viewModel.currentUserProfile?.deviceID
        print("StoryViewerView: 👤 isCurrentUserViewing: \(isCurrentUserViewing)")
        
        Task {
            do {
                debugInfo = "Loading stories from CloudKit..."
                await loadStories()
            } catch {
                await MainActor.run {
                    debugInfo = "Error loading stories: \(error.localizedDescription)"
                    print("StoryViewerView: ❌ Error in setupStoryViewing: \(error)")
                }
            }
        }
    }
    
    private func cleanupStoryViewing() {
        print("StoryViewerView: 🧹 Cleaning up story viewing")
        storyTimer?.invalidate()
        storyTimer = nil
        imageLoader.cancel()
    }
    
    private func loadStories() async {
        print("StoryViewerView: 🔍 Loading stories for deviceID: \(deviceID)")
        
        await MainActor.run {
            isLoading = true
            debugInfo = "Fetching stories from CloudKit..."
        }
        
        do {
            let result = await viewModel.getStoriesForDevice(deviceID)
            
            await MainActor.run {
                print("StoryViewerView: 📥 Fetched \(result.stories.count) stories for device \(deviceID)")
                print("StoryViewerView: 📊 Has unviewed stories: \(result.hasUnviewed)")
                
                self.stories = result.stories.sorted { $0.timestamp > $1.timestamp }
                self.isLoading = false
                
                if stories.isEmpty {
                    print("StoryViewerView: ⚠️ No stories to display")
                    debugInfo = "No active stories found for this device"
                } else {
                    print("StoryViewerView: ✅ Stories loaded successfully")
                    debugInfo = "Loaded \(stories.count) stories successfully"
                    
                    // Log details about each story
                    for (index, story) in stories.enumerated() {
                        print("StoryViewerView: Story \(index): ID=\(story.id), hasAsset=\(story.imageAsset != nil), caption=\(story.caption ?? "none")")
                        if let asset = story.imageAsset {
                            print("StoryViewerView: Story \(index) asset fileURL: \(asset.fileURL?.absoluteString ?? "nil")")
                        }
                    }
                    
                    // Stories will be marked as viewed individually as user progresses through them
                }
            }
        } catch {
            await MainActor.run {
                print("StoryViewerView: ❌ Error loading stories: \(error)")
                debugInfo = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func loadCurrentStoryImage() {
        guard let story = currentStory else {
            print("StoryViewerView: ⚠️ No current story to load image for")
            debugInfo = "No current story available"
            return
        }
        
        print("StoryViewerView: 🖼️ Loading image for story \(currentStoryIndex + 1)/\(stories.count) (ID: \(story.id))")
        debugInfo = "Loading image \(currentStoryIndex + 1)/\(stories.count)"
        
        if let imageAsset = story.imageAsset {
            print("StoryViewerView: 📁 Loading CKAsset with fileURL: \(imageAsset.fileURL?.absoluteString ?? "nil")")
            debugInfo = "Loading asset file..."
            imageLoader.loadImage(from: imageAsset)
        } else {
            print("StoryViewerView: ⚠️ Story has no image asset")
            debugInfo = "Story has no image asset"
            imageLoader.loadImage(from: nil)
        }
    }
    
    private func startStoryTimer() {
        print("StoryViewerView: ⏱️ Starting story timer for \(storyDuration) seconds")
        storyProgress = 0.0
        
        storyTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            storyProgress += 0.1 / storyDuration
            
            if storyProgress >= 1.0 {
                nextStory()
            }
        }
    }
    
    private func restartStoryTimer() {
        print("StoryViewerView: 🔄 Restarting story timer")
        storyTimer?.invalidate()
        startStoryTimer()
    }
    
    private func previousStory() {
        print("StoryViewerView: ⬅️ Previous story tapped")
        
        // Mark current story as viewed before moving
        markCurrentStoryAsViewed()
        
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            print("StoryViewerView: ✅ Moved to story \(currentStoryIndex + 1)/\(stories.count)")
        } else {
            print("StoryViewerView: ➡️ Already at first story, dismissing")
            closeViewer()
        }
    }
    
    private func nextStory() {
        print("StoryViewerView: ➡️ Next story triggered")
        
        // Mark current story as viewed before moving to next
        markCurrentStoryAsViewed()
        
        if currentStoryIndex < stories.count - 1 {
            currentStoryIndex += 1
            print("StoryViewerView: ✅ Moved to story \(currentStoryIndex + 1)/\(stories.count)")
        } else {
            print("StoryViewerView: 🏁 Reached end of stories, dismissing")
            closeViewer()
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
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    /// Mark the current story as viewed
    private func markCurrentStoryAsViewed() {
        guard let currentStory = currentStory else { return }
        
        Task {
            print("StoryViewerView: 👁️ Marking story as viewed: \(currentStory.id)")
            await viewModel.viewStory(currentStory)
        }
    }
    
    /// Unified close logic used throughout the view.
    private func closeViewer() {
        // Mark the final story as viewed before closing
        markCurrentStoryAsViewed()
        
        cleanupStoryViewing()
        onClose()
        // Also call envDismiss() in case this view was presented modally
        envDismiss()
    }
}

struct StoryViewerView_Previews: PreviewProvider {
    static var previews: some View {
        StoryViewerView(viewModel: GridViewModel(), deviceID: "sample-device") {
            // onClose closure for preview
        }
    }
} 