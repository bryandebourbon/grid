import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel // Use GridViewModel directly or a dedicated ChatViewModel
    let recipientDeviceID: String // The device ID of the device being chatted with (can be self for notes)
    
    @State private var newMessageText: String = ""
    
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
                TextField("Enter message...", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .onSubmit {
                        if !newMessageText.isEmpty {
                            sendMessage()
                        }
                    }
                
                Button(action: sendMessage) {
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
        .onAppear {
            // When the view appears, ensure the viewModel knows which device we're chatting with.
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            print("ChatView: Opened chat with \(recipientDeviceID), \(chatMessages.count) messages ready instantly!")
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
    
    var body: some View {
        HStack {
            if isCurrentDeviceSender {
                Spacer() // Push message to the right for sender
            }
            
            VStack(alignment: isCurrentDeviceSender ? .trailing : .leading, spacing: 2) { // Added spacing
                Text(message.text)
                    .padding(10)
                    .background(isCurrentDeviceSender ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                    .foregroundColor(isCurrentDeviceSender ? .white : .primary)
                    .cornerRadius(10)
                    .opacity(message.status == .sending ? 0.7 : 1.0) // Dim if sending

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