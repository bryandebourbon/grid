import SwiftUI
import PhotosUI

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel // Use GridViewModel directly or a dedicated ChatViewModel
    let recipientDeviceID: String // The device ID of the device being chatted with (can be self for notes)
    
    @State private var newMessageText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil // For the new photo picker
    @State private var showPhotoPicker = false // To present the picker
    @State private var fullScreenImage: FullScreenImageData? = nil // For full-screen image display
    @FocusState private var isTextFieldFocused: Bool // NEW: For automatic keyboard focus
    
    // Add dismiss environment for closing the sheet
    @Environment(\.dismiss) var dismiss
    
    private var currentDeviceID: String? {
        viewModel.currentUserProfile?.deviceID
    }
    
    // Use preloaded messages from GridViewModel - instant access!
    private var chatMessages: [Message] {
        return viewModel.getMessagesForConversation(with: recipientDeviceID)
    }
    
    var body: some View {
        VStack {
            // Message display area
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
                                    .id(message.id) // For ScrollViewReader
                                    .environmentObject(viewModel)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: chatMessages.count) { _ in // Auto-scroll to new message
                    scrollToBottom(scrollViewProxy)
                }
                .onAppear {
                    scrollToBottom(scrollViewProxy)
                }
            }
            
            // Message input area
            HStack {
                // Button to open PhotosPicker
                Button(action: { showPhotoPicker = true }) {
                    Image(systemName: "photo.on.rectangle")
                        .padding(.leading)
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
                .onChange(of: selectedPhotoItem) { newItem in
                    Task {
                        if let item = newItem {
                            // Load data and send image message
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                viewModel.sendImageMessage(imageData: data, to: recipientDeviceID)
                                selectedPhotoItem = nil // Reset picker after sending
                            } else {
                                print("ChatView: Failed to load image data from PhotosPickerItem")
                                selectedPhotoItem = nil // Reset picker
                                // Optionally show an error to the user
                            }
                        }
                    }
                }

                TextField("Enter message...", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .focused($isTextFieldFocused) // NEW: Connect to focus state
                    .onSubmit {
                        if !newMessageText.isEmpty {
                            sendMessage()
                        }
                    }
                
                Button(action: {
                    if !newMessageText.isEmpty {
                        let messageToSend = newMessageText
                        newMessageText = "" // Clear input immediately for better UX
                        
                        // Use content-filtered message sending
                        // Note: encryption mode is handled internally by GridViewModel based on isEncryptionMode
                        viewModel.sendMessageWithModeration(text: messageToSend, to: recipientDeviceID)
                        
                        // Keep focus on text field for continued typing
                        isTextFieldFocused = true
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .padding(.trailing)
                        .foregroundColor(newMessageText.isEmpty ? .gray : .blue)
                }
                .disabled(newMessageText.isEmpty || currentDeviceID == nil)
            }
            .padding()
        }
        .navigationTitle(recipientDeviceID == currentDeviceID ? "My Notes" : "Chat with \(recipientDisplayName())")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recipientDeviceID != currentDeviceID {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            // First dismiss the chat sheet, then show report
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // Find the recipient's profile
                                for row in viewModel.gridNodes {
                                    for node in row {
                                        if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                                            viewModel.selectedUserProfileForReport = ProfileCardUser(id: recipientDeviceID, userProfile: profile)
                                            return
                                        }
                                    }
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
            // When the view appears, ensure the viewModel knows which device we're chatting with.
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            print("ChatView: Opened chat with \(recipientDeviceID), \(chatMessages.count) messages ready instantly!")
            
            // Mark all messages from this device as read
            viewModel.markMessagesAsRead(from: recipientDeviceID)
            
            // NEW: Automatically focus the text field to bring up keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .overlay {
            // Full-screen image viewer
            if let imageData = fullScreenImage {
                FullScreenImageView(imageData: imageData) {
                    fullScreenImage = nil // Close the full-screen view
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
        guard !newMessageText.isEmpty, let currentDeviceID = currentDeviceID else { return }
        let messageText = newMessageText
        newMessageText = "" // Clear input field immediately
        
        print("ChatView: Sending message instantly (no wait): \(messageText)")
        viewModel.sendMessage(text: messageText, to: recipientDeviceID)
        
        // Keep focus on text field for continued typing
        isTextFieldFocused = true
        
        // Messages are automatically updated via the real-time subscription
        // No need to manually refresh - the message will appear when CloudKit confirms it
    }
    
    private func recipientDisplayName() -> String {
        ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: recipientDeviceID,
            currentDeviceID: currentDeviceID,
            gridNodes: viewModel.gridNodes
        )
    }
}
