import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ChatOverlayView: View {
    @ObservedObject var viewModel: GridViewModel
    let recipientDeviceID: String
    var isPresented: Bool = true
    @FocusState.Binding var isComposerFocused: Bool
    let onClose: () -> Void
    @StateObject private var photoLoader = ImageLoader()

    private var partnerProfile: UserProfile? {
        if recipientDeviceID == viewModel.currentUserProfile?.deviceID {
            return viewModel.currentUserProfile
        }
        if LocalLLMIdentity.isLLM(recipientDeviceID) {
            return LocalLLMIdentity.profile
        }
        return ProfileDisplayNameLogic.profile(forDeviceID: recipientDeviceID, in: viewModel.allGridNodes)
            ?? ProfileDisplayNameLogic.profile(forDeviceID: recipientDeviceID, in: viewModel.gridNodes)
    }

    private var headerBio: String? {
        if LocalLLMIdentity.isLLM(recipientDeviceID) {
            let bio = LocalLLMIdentity.bio.trimmingCharacters(in: .whitespacesAndNewlines)
            return bio.isEmpty ? nil : bio
        }
        return viewModel.statusText(for: recipientDeviceID)
    }

    private func recipientDisplayName() -> String {
        ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: recipientDeviceID,
            currentDeviceID: viewModel.currentUserProfile?.deviceID,
            gridNodes: viewModel.allGridNodes
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 8) {
                ChatBackPill(
                    unreadCount: viewModel.incomingUnreadCount(excludingDeviceID: recipientDeviceID),
                    action: onClose
                )
                .accessibilityIdentifier(GridUITestHarness.chatCloseIdentifier)
                .accessibilityLabel("Back")
                .accessibilityAddTraits(.isButton)

                HStack(spacing: 10) {
                    headerPhoto

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipientDisplayName())
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .accessibilityElement()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(GridUITestHarness.chatTitleIdentifier)
                            .accessibilityValue(recipientDeviceID)
                            .accessibilityLabel(recipientDisplayName())

                        if let bio = headerBio {
                            Text(bio)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if recipientDeviceID != viewModel.currentUserProfile?.deviceID,
                           let distanceString = viewModel.getDistanceString(to: recipientDeviceID) {
                            Text(distanceString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.trailing, 8)

                chatActionsButton
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            .onAppear { loadHeaderPhoto() }
            .onChange(of: recipientDeviceID) { _ in loadHeaderPhoto() }
            .onChange(of: partnerProfile?.profileImage?.fileURL) { _ in loadHeaderPhoto() }
            
            // Chat content
            ChatView(
                viewModel: viewModel,
                recipientDeviceID: recipientDeviceID,
                isPresented: isPresented,
                isTextFieldFocused: $isComposerFocused,
                onBack: onClose
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .horizontalEdgeDismiss(onDismiss: onClose)
        .onAppear {
            if isPresented { activateVisibleThread() }
        }
        .onChange(of: isPresented) { presented in
            if presented { activateVisibleThread() }
        }
        .onChange(of: recipientDeviceID) { _ in
            if isPresented { activateVisibleThread() }
        }
    }

    @ViewBuilder
    private var chatActionsButton: some View {
        Menu {
            Button {
                viewModel.requestStar(for: recipientDeviceID)
            } label: {
                Label(
                    viewModel.isStarred(recipientDeviceID) ? "Unstar" : "Star",
                    systemImage: viewModel.isStarred(recipientDeviceID) ? "star.slash" : "star"
                )
            }

            Button(role: viewModel.isBlocked(recipientDeviceID) ? nil : .destructive) {
                viewModel.toggleBlock(for: recipientDeviceID)
            } label: {
                Label(
                    viewModel.isBlocked(recipientDeviceID) ? "Unblock" : "Block",
                    systemImage: viewModel.isBlocked(recipientDeviceID) ? "hand.raised.slash" : "hand.raised"
                )
            }

            Button(role: .destructive) {
                if let profile = partnerProfile {
                    viewModel.selectedUserProfileForReport = ProfileCardUser(
                        id: recipientDeviceID,
                        userProfile: profile
                    )
                }
            } label: {
                Label("Report", systemImage: "exclamationmark.shield")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Chat actions")
        .starGroupPopover(viewModel: viewModel, deviceID: recipientDeviceID)
    }

    private let headerPhotoSize: CGFloat = 44

    private var headerPhoto: some View {
        Group {
            if let image = photoLoader.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: headerPhotoSize, height: headerPhotoSize)
                    .clipped()
            } else {
                Image(systemName: LocalLLMIdentity.isLLM(recipientDeviceID) ? "sparkles" : "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: headerPhotoSize, height: headerPhotoSize)
            }
        }
        .background(Color.primary.opacity(0.08))
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func loadHeaderPhoto() {
        photoLoader.loadImage(from: partnerProfile?.profileImage)
    }

    private func activateVisibleThread() {
        ChatOpenTrace.mark("overlay.activate \(recipientDeviceID.prefix(8))")
        viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
        viewModel.refreshIncomingMessages {
            self.viewModel.markMessagesAsRead(from: self.recipientDeviceID)
        }
    }
}

private struct ChatBackPill: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, unreadCount > 9 ? 4 : 0)
                        .background(Color.white, in: Capsule())
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, unreadCount > 0 ? 10 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
