import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct GridNodeView: View {
    let node: GridNode
    let viewModel: GridViewModel
    let useCircularPhotos: Bool
    let useSquarePhotos: Bool
    let storiesMode: Bool
    let showBioBubbles: Bool
    var gridColumns: Int = 3
    let onChatTapped: (String) -> Void
    let onStoriesTapped: (UserProfile) -> Void
    @StateObject private var imageLoader = ImageLoader()
    @State private var hasUnviewedStories = false

    var body: some View {
        Button(action: handleCellTap) {
        ZStack {
            // Main profile image
            Group {
                if imageLoader.isLoading {
                    ProgressView()
                } else if let loadedImage = imageLoader.image {
                    loadedImage
                        .resizable()
                        .scaledToFill()
                } else if let profile = node.userProfile, LocalLLMIdentity.isLLM(profile.deviceID) {
                    Image(systemName: "sparkles")
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .foregroundColor(Color.purple.opacity(0.85))
                } else if let profile = node.userProfile {
                    InitialsAvatarFill(
                        name: profile.displayName,
                        seed: profile.deviceID,
                        gridColumns: gridColumns
                    )
                } else {
                    Color.gray.opacity(0.1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity) // Ensure it expands
            .aspectRatio(GridCellLayout.widthOverHeight(square: useSquarePhotos), contentMode: .fit)
            // Circular cells stay transparent at the corners so the grid backdrop shows through.
            // Portrait cells keep a light fill behind the photo.
            .background(useCircularPhotos ? Color.clear : Color.gray.opacity(0.1))
            .modifier(DynamicClipShape(useCircular: useCircularPhotos)) // Dynamic shape based on setting
            
            // Stories ring overlay (only in stories mode)
            if storiesMode, let profile = node.userProfile, !LocalLLMIdentity.isLLM(profile.deviceID) {
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
            
            if showBioBubbles, let profile = node.userProfile {
                let isMe = profile.deviceID == viewModel.currentUserProfile?.deviceID
                if let content = BioStatusBubbleLogic.content(
                    bio: viewModel.statusText(for: profile.deviceID),
                    isMe: isMe
                ) {
                    VStack {
                        BioStatusBubble(
                            text: content.text,
                            isPlaceholder: content.isPlaceholder,
                            fontSize: BioStatusBubbleLogic.fontSize(forGridColumns: gridColumns)
                        )
                            .padding(.top, useCircularPhotos ? 12 : 6)
                            .padding(.horizontal, 6)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }

            if let profile = node.userProfile {
                VStack {
                    HStack {
                        if viewModel.isStarred(profile.deviceID) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.yellow)
                                .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 18, height: 18))
                        }
                        if profile.isDiscoverable == false, viewModel.seesHiddenPeople {
                            HiddenUserBadge(size: 18)
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
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        }
        .buttonStyle(.plain)
        .modifier(DynamicClipShape(useCircular: useCircularPhotos))
        .overlay {
            if GridUITestHarness.isActive, node.userProfile != nil {
                UITestHitButton(
                    title: node.userProfile?.deviceName ?? "Cell",
                    identifier: node.userProfile.map { GridUITestHarness.cellIdentifier(for: $0.deviceID) } ?? ""
                ) {
                    handleCellTap()
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(
            GridUITestHarness.isActive
                ? ""
                : (node.userProfile.map { GridUITestHarness.cellIdentifier(for: $0.deviceID) }
                    ?? "grid.cell.empty.\(node.x).\(node.y)")
        )
        .accessibilityLabel(node.userProfile?.deviceName ?? "Empty cell")
        .task(id: photoLoadKey) {
            imageLoader.loadImage(from: displayedProfileImage, force: true)
            loadStoriesStatus()
        }
        .onChange(of: photoLoadKey) { _ in
            imageLoader.loadImage(from: displayedProfileImage, force: true)
        }
        .onChange(of: storiesMode) { _ in
            loadStoriesStatus()
        }
        .onChange(of: viewModel.storiesService.allActiveStories) { _ in
            loadStoriesStatus()
        }
    }

    private var displayedProfileImage: CKAsset? {
        if node.userProfile?.deviceID == viewModel.currentUserProfile?.deviceID {
            return viewModel.currentUserProfile?.profileImage ?? node.userProfile?.profileImage
        }
        return node.userProfile?.profileImage
    }

    private var photoLoadKey: String {
        "\(node.id)|\(ProfileImageRefreshLogic.loadKey(for: displayedProfileImage))"
    }

    private func handleCellTap() {
        guard let userProfile = node.userProfile,
              let partnerID = GridCellTapLogic.chatPartnerDeviceID(for: node) else { return }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        if storiesMode && !GridUITestHarness.isActive && !LocalLLMIdentity.isLLM(userProfile.deviceID) {
            onStoriesTapped(userProfile)
            return
        }

        let messagingStatus = viewModel.canMessageUser(deviceID: partnerID)
        if GridUITestHarness.isActive
            || messagingStatus.allowed
            || partnerID == viewModel.currentUserProfile?.deviceID
            || viewModel.isBlocked(partnerID) {
            onChatTapped(partnerID)
        } else {
            print("Cannot message user: \(messagingStatus.reason)")
        }
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

struct HiddenUserBadge: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.system(size: size * 0.52, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.62), in: Circle())
            .accessibilityLabel("Hidden")
    }
}
