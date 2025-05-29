import SwiftUI
import PhotosUI // Import for PhotosPickerItem

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel // Use GridViewModel directly or a dedicated ChatViewModel
    let recipientDeviceID: String // The device ID of the device being chatted with (can be self for notes)
    
    @State private var newMessageText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil // For the new photo picker
    @State private var showPhotoPicker = false // To present the picker
    
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
                                MessageRow(message: message, isCurrentDeviceSender: message.senderDeviceID == currentDeviceID)
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
        
        // Messages are automatically updated via the real-time subscription
        // No need to manually refresh - the message will appear when CloudKit confirms it
    }
    
    // Helper to get a display name for the recipient device
    private func recipientDisplayName() -> String {
        // Check if this is a self-chat first
        if recipientDeviceID == currentDeviceID {
            return "My Notes"
        }
        
        // Find the recipient's profile to get their display name
        for row in viewModel.gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                    return profile.displayName
                }
            }
        }
        return "Device \(String(recipientDeviceID.prefix(8)))"
    }
}

struct MessageRow: View {
    let message: Message
    let isCurrentDeviceSender: Bool
    @StateObject private var imageLoader = ImageLoader() // For loading CKAsset images
    @EnvironmentObject var viewModel: GridViewModel // To access decryption
    
    // Decrypt message text if needed
    private var displayText: String {
        if message.isEncrypted {
            return viewModel.decryptMessage(message)
        } else {
            return message.text
        }
    }
    
    var body: some View {
        HStack {
            if isCurrentDeviceSender {
                Spacer() // Push message to the right for sender
            }
            
            VStack(alignment: isCurrentDeviceSender ? .trailing : .leading, spacing: 2) { // Added spacing
                // Encryption indicator
                if message.isEncrypted {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Encrypted")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                if let imageAsset = message.imageAsset {
                    // Display image if present
                    if imageLoader.isLoading {
                        ProgressView()
                            .frame(width: 150, height: 150)
                    } else if let loadedImage = imageLoader.image {
                        loadedImage
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200) // Limit image height
                            .cornerRadius(10)
                            .onTapGesture { /* Allow full screen view? */ }
                    } else {
                        // Placeholder or error for image
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 100)
                            .cornerRadius(10)
                            .overlay(Text("Error loading image").font(.caption))
                    }
                } else if !displayText.isEmpty {
                    // Display text if no image and text is not empty
                    Text(displayText)
                        .padding(10)
                        .background(isCurrentDeviceSender ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                        .foregroundColor(isCurrentDeviceSender ? .white : .primary)
                        .cornerRadius(10)
                        .opacity(message.status == .sending ? 0.7 : 1.0) // Dim if sending
                } else {
                    // Fallback for empty message (should ideally not happen if image or text is required)
                     Text("[Empty Message]")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                HStack(spacing: 4) { // HStack for timestamp and status indicator
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    // Status Indicator
                    if isCurrentDeviceSender { // Only show sending/failed status for messages sent by current user
                        switch message.status {
                        case .sending:
                            Text("Sending...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        case .failed:
                            Text("Failed")
                                .font(.caption2)
                                .foregroundColor(.red)
                                // TODO: Add tap to retry action here later
                        case .sent, .received: // .received shouldn't happen for isCurrentDeviceSender true, but good to be exhaustive
                            EmptyView() // No indicator for sent or received (unless you want a checkmark for sent)
                        }
                    }
                }
            }
            
            if !isCurrentDeviceSender {
                Spacer() // Push message to the left for receiver
            }
        }
        .id(message.id) // Ensure the row is uniquely identifiable for list updates
        .onAppear {
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
        .onChange(of: message.imageAsset?.fileURL) { _ in // Reload if asset URL changes
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
    }
}

#if DEBUG
//struct ChatView_Previews: PreviewProvider {
//    static var previews: some View {
//        // Create a mock GridViewModel
//        let mockViewModel = GridViewModel(networkService: NetworkService(), messagingService: MessagingService())
//        // Create a mock current user profile
//        let mockDevice = UserProfile(userID: "currentUser123", deviceID: "device123", deviceName: "iPhone")
//        mockViewModel.currentUserProfile = mockDevice
//        
//        // Create mock messages
//        let recipientDeviceID = "device456"
//        mockViewModel.messages = [
//            Message(senderDeviceID: "device123", recipientDeviceID: recipientDeviceID, senderUserID: "currentUser123", recipientUserID: "user456", text: "Hello!", timestamp: Date().addingTimeInterval(-3600)),
//            Message(senderDeviceID: recipientDeviceID, recipientDeviceID: "device123", senderUserID: "user456", recipientUserID: "currentUser123", text: "Hi there! How are you?", timestamp: Date().addingTimeInterval(-3000)),
//            Message(senderDeviceID: "device123", recipientDeviceID: recipientDeviceID, senderUserID: "currentUser123", recipientUserID: "user456", text: "I'm good, thanks! Just testing this chat UI. It needs to handle long messages as well to see how the layout behaves.", timestamp: Date().addingTimeInterval(-2400)),
//            Message(senderDeviceID: recipientDeviceID, recipientDeviceID: "device123", senderUserID: "user456", recipientUserID: "currentUser123", text: "Looks good so far!", timestamp: Date().addingTimeInterval(-1800))
//        ]
//        
//        return NavigationView {
//            ChatView(viewModel: mockViewModel, recipientDeviceID: recipientDeviceID)
//        }
//    }
//}
#endif 