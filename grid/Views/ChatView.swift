import SwiftUI
import PhotosUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
    @ObservedObject var viewModel: GridViewModel // Use GridViewModel directly or a dedicated ChatViewModel
    let recipientDeviceID: String // The device ID of the device being chatted with (can be self for notes)
    
    @State private var newMessageText: String = ""
    @State private var isRefreshing = false
    @State private var galleryImages: [UIImage] = []
    @State private var selectedGalleryItem: PhotosPickerItem? = nil
    @FocusState private var messageFieldFocused: Bool

    private var currentDeviceID: String? {
        viewModel.currentUserProfile?.deviceID
    }

    private var isSelfChat: Bool {
        recipientDeviceID == currentDeviceID
    }
    
    // Filter messages for the current chat
    private var chatMessages: [Message] {
        guard let currentDeviceID = currentDeviceID else { return [] }
        return viewModel.messages.filter {
            ($0.senderDeviceID == currentDeviceID && $0.recipientDeviceID == recipientDeviceID) ||
            ($0.senderDeviceID == recipientDeviceID && $0.recipientDeviceID == currentDeviceID)
        }.sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var gallerySize: CGFloat {
        messageFieldFocused ? 50 : 100
    }
    
    var body: some View {
        VStack {
            // Horizontal gallery of user uploaded images
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(galleryImages.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: gallerySize, height: gallerySize)
                            .clipped()
                            .cornerRadius(8)
                    }
                    if isSelfChat && galleryImages.count < 5 {
                        PhotosPicker(selection: $selectedGalleryItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "plus.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: gallerySize, height: gallerySize)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: gallerySize)
            .animation(.easeInOut, value: gallerySize)
            .onChange(of: selectedGalleryItem) { newItem in
                guard isSelfChat, let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        galleryImages.append(uiImage)
                        viewModel.updateCurrentGalleryPhotos(newPhotoDataArray: [data])
                    }
                }
            }

            // Message display area
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(chatMessages) { message in
                            MessageRow(message: message, isCurrentDeviceSender: message.senderDeviceID == currentDeviceID)
                                .id(message.id) // For ScrollViewReader
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await refreshMessages()
                }
                .onChange(of: chatMessages.count) { _ in // Auto-scroll to new message
                    if let lastMessage = chatMessages.last {
                        withAnimation {
                            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastMessage = chatMessages.last {
                        scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            // Message input area
            HStack {
                TextField("Enter message...", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .focused($messageFieldFocused)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .padding(.trailing)
                }
                .disabled(newMessageText.isEmpty || currentDeviceID == nil)
            }
            .padding()
        }
        .navigationTitle(recipientDeviceID == currentDeviceID ? "My Notes" : "Chat with \(recipientDisplayName())")
        .onAppear {
            // When the view appears, ensure the viewModel knows which device we're chatting with.
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            loadGalleryImages()
        }
    }
    
    @MainActor
    private func refreshMessages() async {
        guard let currentDeviceID = currentDeviceID else { return }
        
        return await withCheckedContinuation { continuation in
            viewModel.fetchMessagesForCurrentDevice(deviceID: currentDeviceID)
            // Give it a moment to complete, then continue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessageText.isEmpty, let currentDeviceID = currentDeviceID else { return }
        let messageText = newMessageText
        newMessageText = "" // Clear input field immediately
        
        viewModel.sendMessage(text: messageText, to: recipientDeviceID)
        
        // Auto-refresh after sending to show the sent message
        Task {
            // Give CloudKit a moment to save the message, then refresh
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            await refreshMessages()
        }
    }

    private func loadGalleryImages() {
        galleryImages = []
        let targetID = isSelfChat ? currentDeviceID : recipientDeviceID
        guard let id = targetID, let profile = profileForDevice(id: id) else { return }
        if let assets = profile.galleryPhotoAssets {
            for asset in assets {
                if let url = asset.fileURL, let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    galleryImages.append(ui)
                }
            }
        }
    }

    private func profileForDevice(id: String) -> UserProfile? {
        if let current = viewModel.currentUserProfile, current.deviceID == id { return current }
        for row in viewModel.gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == id {
                    return profile
                }
            }
        }
        return nil
    }
    
    // Helper to get a display name for the recipient device
    private func recipientDisplayName() -> String {
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
            
            VStack(alignment: isCurrentDeviceSender ? .trailing : .leading) {
                Text(message.text)
                    .padding(10)
                    .background(isCurrentDeviceSender ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                    .foregroundColor(isCurrentDeviceSender ? .white : .primary)
                    .cornerRadius(10)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            if !isCurrentDeviceSender {
                Spacer() // Push message to the left for receiver
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