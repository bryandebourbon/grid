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
    
    private var partnerProfile: UserProfile? {
        if recipientDeviceID == viewModel.currentUserProfile?.deviceID {
            return viewModel.currentUserProfile
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
            gridNodes: viewModel.gridNodes
        )
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
                .accessibilityIdentifier(GridUITestHarness.chatCloseIdentifier)
                .accessibilityLabel("Close chat")
                .accessibilityAddTraits(.isButton)
                
                Spacer()
                
                VStack(spacing: 2) {
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
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if recipientDeviceID != viewModel.currentUserProfile?.deviceID,
                       let distanceString = viewModel.getDistanceString(to: recipientDeviceID) {
                        Text(distanceString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
                
                if LocalLLMIdentity.isLLM(recipientDeviceID)
                    || recipientDeviceID == viewModel.currentUserProfile?.deviceID {
                    Color.clear.frame(width: 44, height: 44)
                } else {
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
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Chat actions")
                    .starGroupPopover(viewModel: viewModel, deviceID: recipientDeviceID)
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            
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
        .overlay(alignment: .leading) {
            edgeBackSwipe { $0 > 70 }
        }
        .overlay(alignment: .trailing) {
            edgeBackSwipe { $0 < -70 }
        }
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

    private func activateVisibleThread() {
        ChatOpenTrace.mark("overlay.activate \(recipientDeviceID.prefix(8))")
        viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
        viewModel.refreshIncomingMessages {
            self.viewModel.markMessagesAsRead(from: self.recipientDeviceID)
        }
    }

    private func edgeBackSwipe(_ isBackSwipe: @escaping (CGFloat) -> Bool) -> some View {
        Color.clear
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let isMostlyHorizontal = abs(value.translation.width) > abs(value.translation.height)
                        if isMostlyHorizontal && isBackSwipe(value.translation.width) {
                            onClose()
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}
