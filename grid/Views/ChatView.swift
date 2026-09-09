import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel
    let recipientDeviceID: String
    var isPresented: Bool = true
    @FocusState.Binding var isTextFieldFocused: Bool
    var onBack: () -> Void = {}

    @State private var newMessageText: String = ""
    @StateObject private var photoLibrary = RecentPhotoLibrary()
    @State private var showPhotoStrip = false
    @AppStorage("grid.chatPartnerPins") private var showPartnerPins = true
    @AppStorage("grid.chatAlbumButton") private var showChatAlbumButton = false
    @State private var fullScreenImage: FullScreenImageData? = nil
    @State private var reactingMessageID: String?
    @State private var ignoreReactionScrollDismissUntil = Date.distantPast
    @State private var keyboardActivation = 0

    private var currentDeviceID: String? {
        viewModel.currentUserProfile?.deviceID
    }

    private var chatMessages: [Message] {
        viewModel.getMessagesForConversation(with: recipientDeviceID)
    }

    private var latestMessageID: String? {
        chatMessages.last?.id
    }

    private var hasPartnerPins: Bool {
        (viewModel.userAlbums[recipientDeviceID]?.photosCount ?? 0) > 0
    }

    private var showsPartnerPinStrip: Bool {
        hasPartnerPins && partnerProfile != nil && (showChatAlbumButton ? showPartnerPins : true)
    }

    private var accessoryHeight: CGFloat {
        var height: CGFloat = 0
        if showsPartnerPinStrip { height += 100 }
        return height
    }

    @ViewBuilder
    private var chatAccessoryStrips: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPartnerPinStrip, let partnerProfile {
                ProfilePinnedStoriesRow(
                    viewModel: viewModel,
                    userProfile: partnerProfile,
                    showsTitle: false,
                    showsAddSlots: false,
                    onSelectImage: { image in
                        fullScreenImage = FullScreenImageData(image: image, isEncrypted: false)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showPhotoStrip {
                ChatRecentPhotoStrip(
                    library: photoLibrary,
                    onSelect: { data in
                        viewModel.sendImageMessage(imageData: data, to: recipientDeviceID)
                    },
                    onOpenSettings: {
                        #if canImport(UIKit)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if chatMessages.isEmpty {
                                VStack {
                                    Image(systemName: "message")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                    Text("No messages yet")
                                        .foregroundColor(.gray)
                                    Text("Send a message to start the conversation!")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 50)
                            } else {
                                ForEach(chatMessages) { message in
                                    MessageRow(
                                        message: message,
                                        isCurrentDeviceSender: message.senderDeviceID == currentDeviceID,
                                        onImageTap: { imageData in
                                            fullScreenImage = imageData
                                        },
                                        onReact: { emoji in
                                            viewModel.toggleReaction(emoji, on: message.id)
                                        },
                                        isReactionPickerVisible: reactingMessageID == message.id,
                                        onToggleReactionPicker: {
                                            toggleReactionPicker(for: message.id)
                                        }
                                    )
                                    .id(message.id)
                                    .zIndex(reactingMessageID == message.id ? 1 : 0)
                                    .environmentObject(viewModel)
                                }
                            }

                            Color.clear
                                .frame(height: max(accessoryHeight, 1))
                                .id(Self.bottomAnchorID)
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.never)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { oldOffset, newOffset in
                        dismissReactionPickerIfUserScrolled(from: oldOffset, to: newOffset)
                    }
                    .onChange(of: chatMessages.count) { _ in
                        guard reactingMessageID == nil else { return }
                        pinToLatest(scrollViewProxy)
                    }
                    .onChange(of: latestMessageID) { _ in
                        guard reactingMessageID == nil else { return }
                        pinToLatest(scrollViewProxy)
                    }
                    .onChange(of: recipientDeviceID) { _ in
                        resetComposer()
                        pinToLatest(scrollViewProxy)
                    }
                    .onChange(of: isPresented) { presented in
                        if presented { pinToLatest(scrollViewProxy) }
                    }
                    .onAppear {
                        pinToLatest(scrollViewProxy)
                    }
                }

                chatAccessoryStrips
            }

            ChatMessageComposer(
                text: $newMessageText,
                isFocused: $isTextFieldFocused,
                isPhotoStripOpen: showPhotoStrip,
                isPartnerPinsOpen: showPartnerPins,
                showsPartnerPinsButton: showChatAlbumButton && hasPartnerPins,
                keyboardActivation: keyboardActivation,
                onBack: onBack,
                onAdd: {
                    showPhotoStrip.toggle()
                },
                onTogglePartnerPins: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPartnerPins.toggle()
                    }
                },
                onSend: sendMessage
            )
            .background(Color(.systemBackground))
        }
        .task(id: recipientDeviceID) {
            _ = await viewModel.getAlbum(for: recipientDeviceID)
            await photoLibrary.prepare()
        }
        .onAppear {
            if isPresented {
                isTextFieldFocused = true
                keyboardActivation += 1
            }
        }
        .onChange(of: isPresented) { presented in
            if !presented {
                showPhotoStrip = false
            }
        }
        .overlay {
            if let imageData = fullScreenImage {
                FullScreenImageView(imageData: imageData) {
                    fullScreenImage = nil
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if fullScreenImage != nil {
                PhotoCloseButton {
                    fullScreenImage = nil
                }
                .frame(width: 56, height: 56)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private static let bottomAnchorID = "chat-bottom"

    private func pinToLatest(_ scrollViewProxy: ScrollViewProxy) {
        guard isPresented, reactingMessageID == nil else { return }
        let target = latestMessageID ?? Self.bottomAnchorID
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollViewProxy.scrollTo(target, anchor: .bottom)
            scrollViewProxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
        DispatchQueue.main.async {
            guard isPresented, reactingMessageID == nil else { return }
            var next = Transaction()
            next.disablesAnimations = true
            withTransaction(next) {
                if let latestMessageID {
                    scrollViewProxy.scrollTo(latestMessageID, anchor: .bottom)
                }
                scrollViewProxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func resetComposer() {
        newMessageText = ""
        showPhotoStrip = false
        fullScreenImage = nil
        reactingMessageID = nil
        if isPresented {
            isTextFieldFocused = true
        }
    }

    private func toggleReactionPicker(for messageID: String) {
        ignoreReactionScrollDismissUntil = Date().addingTimeInterval(0.55)
        if reactingMessageID == messageID {
            reactingMessageID = nil
        } else {
            reactingMessageID = messageID
        }
    }

    private func dismissReactionPickerIfUserScrolled(from oldOffset: CGFloat, to newOffset: CGFloat) {
        guard reactingMessageID != nil else { return }
        guard Date() >= ignoreReactionScrollDismissUntil else { return }
        guard abs(newOffset - oldOffset) > 24 else { return }
        reactingMessageID = nil
    }

    private func sendMessage() {
        let trimmed = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentDeviceID != nil else { return }
        newMessageText = ""
        viewModel.sendMessageWithModeration(text: trimmed, to: recipientDeviceID)
    }
}
