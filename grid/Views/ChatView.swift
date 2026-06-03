import SwiftUI
import PhotosUI

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel
    let recipientDeviceID: String

    @State private var newMessageText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showPhotoPicker = false
    @State private var fullScreenImage: FullScreenImageData? = nil
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.dismiss) var dismiss

    private var currentDeviceID: String? {
        viewModel.currentUserProfile?.deviceID
    }

    private var chatMessages: [Message] {
        viewModel.getMessagesForConversation(with: recipientDeviceID)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                                    }
                                )
                                .id(message.id)
                                .environmentObject(viewModel)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: chatMessages.count) { _ in
                    scrollToBottom(scrollViewProxy)
                }
                .onAppear {
                    scrollToBottom(scrollViewProxy)
                }
            }

            HStack(alignment: .bottom, spacing: 4) {
                Button(action: { showPhotoPicker = true }) {
                    Image(systemName: "photo.on.rectangle")
                        .padding(.leading, 8)
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
                .onChange(of: selectedPhotoItem) { newItem in
                    Task {
                        if let item = newItem,
                           let data = try? await item.loadTransferable(type: Data.self) {
                            viewModel.sendImageMessage(imageData: data, to: recipientDeviceID)
                            selectedPhotoItem = nil
                        } else {
                            selectedPhotoItem = nil
                        }
                    }
                }

                ChatMessageComposer(
                    text: $newMessageText,
                    isFocused: $isTextFieldFocused,
                    onSend: sendMessage
                )
            }
            .background(Color(.systemBackground))
        }
        .navigationTitle(recipientDeviceID == currentDeviceID ? "My Notes" : "Chat with \(recipientDisplayName())")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
            }
            if recipientDeviceID != currentDeviceID {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if let profile = ProfileDisplayNameLogic.profile(
                                    forDeviceID: recipientDeviceID,
                                    in: viewModel.gridNodes
                                ) {
                                    viewModel.selectedUserProfileForReport = ProfileCardUser(
                                        id: recipientDeviceID,
                                        userProfile: profile
                                    )
                                }
                            }
                        }) {
                            Label("Report User", systemImage: "exclamationmark.shield")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            viewModel.markMessagesAsRead(from: recipientDeviceID)
            AppLog.messaging.debug("Opened chat thread")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .overlay {
            if let imageData = fullScreenImage {
                FullScreenImageView(imageData: imageData) {
                    fullScreenImage = nil
                }
            }
        }
    }

    private func scrollToBottom(_ scrollViewProxy: ScrollViewProxy) {
        if let lastMessage = chatMessages.last {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func sendMessage() {
        let trimmed = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentDeviceID != nil else { return }
        newMessageText = ""
        viewModel.sendMessageWithModeration(text: trimmed, to: recipientDeviceID)
        isTextFieldFocused = true
    }

    private func recipientDisplayName() -> String {
        ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: recipientDeviceID,
            currentDeviceID: currentDeviceID,
            gridNodes: viewModel.gridNodes
        )
    }
}
