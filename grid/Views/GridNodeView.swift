import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct GridNodeView: View {
    let node: GridNode
    let viewModel: GridViewModel
    let showInterests: Bool
    let useCircularPhotos: Bool
    let storiesMode: Bool
    let onProfileTapped: (UserProfile) -> Void // For long press or single tap (when not in stories mode)
    let onChatTapped: (String) -> Void // For double tap
    let onStoriesTapped: (UserProfile) -> Void // For single tap in stories mode
    let onSingleTapOccurred: () -> Void // NEW: Notify parent of single tap timing
    @Binding var doubleTapDetected: Bool // NEW: Track double-tap state from parent
    @StateObject private var imageLoader = ImageLoader()
    @State private var hasUnviewedStories = false
    @State private var singleTapTimer: Timer? = nil // NEW: Timer for delayed single-tap

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
            // When using circular photos, keep the cell background transparent so the coloured/photo
            // backdrop of the grid remains visible through the corners. Otherwise retain the subtle
            // gray fill used for square-style grid cells.
            .background(useCircularPhotos ? Color.clear : Color.gray.opacity(0.1))
            .modifier(DynamicClipShape(useCircular: useCircularPhotos)) // Dynamic shape based on setting
            
            // Stories ring overlay (only in stories mode)
            if storiesMode, let profile = node.userProfile {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let hasStories = viewModel.storiesService.hasActiveStories(for: profile.deviceID)
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
                        // Bio + "Me" for current user, or bio + distance for others
                        if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
                           profile.deviceID == currentUserDeviceID {
                            // Bio + "(Me)" for current user
                            bioMeText(for: profile)
                        } else {
                            // Bio + distance for other users
                            bioDistanceText(for: profile)
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
        .onDisappear {
            // Clean up the timer to prevent memory leaks
            singleTapTimer?.invalidate()
            singleTapTimer = nil
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
        // Single tap gesture - immediate execution with cancellation support
        .onTapGesture {
            if let userProfile = node.userProfile {
                print("GridNodeView: 🖱️ Single tap detected - executing immediately")
                
                // Cancel any existing timer
                singleTapTimer?.invalidate()
                
                // If a double-tap was recently detected, ignore this single tap
                if doubleTapDetected {
                    print("GridNodeView: ❌ Single tap ignored - double-tap recently detected")
                    return
                }
                
                // Notify parent of single tap timing for cancellation detection
                onSingleTapOccurred()
                
                // Execute single tap immediately for responsive feel
                print("GridNodeView: ⚡ Single tap executed immediately")
                
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
    
    private func getBioDistanceText(for profile: UserProfile) -> String {
        let distanceString = viewModel.getDistanceString(to: profile.deviceID) ?? ""
        let bioText = profile.bio?.isEmpty == false ? profile.bio! : ""
        
        if bioText.isEmpty {
            return distanceString.isEmpty ? "" : "(\(distanceString))"
        } else {
            return distanceString.isEmpty ? bioText : "\(bioText) (\(distanceString))"
        }
    }
    
    @ViewBuilder
    private func bioDistanceText(for profile: UserProfile) -> some View {
        if !getBioDistanceText(for: profile).isEmpty {
            Text(getBioDistanceText(for: profile))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .lineLimit(2)
        }
    }
    
    private func getBioMeText(for profile: UserProfile) -> String {
        let bioText = profile.bio?.isEmpty == false ? profile.bio! : ""
        return bioText.isEmpty ? "(Me)" : "\(bioText) (Me)"
    }
    
    @ViewBuilder
    private func bioMeText(for profile: UserProfile) -> some View {
        Text(getBioMeText(for: profile))
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(2)
    }
    
    private func loadStoriesStatus() {
        guard storiesMode, let profile = node.userProfile else {
            hasUnviewedStories = false
            return
        }
        
        Task {
            guard let viewerID = viewModel.currentUserProfile?.deviceID else { return }
            let unviewed = await viewModel.storiesService.hasUnviewedStories(
                for: profile.deviceID,
                viewerDeviceID: viewerID
            )
            await MainActor.run {
                hasUnviewedStories = unviewed
            }
        }
    }
}
