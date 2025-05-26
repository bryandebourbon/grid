import SwiftUI
import CloudKit // For CKAsset
import PhotosUI // For PhotosPicker
#if canImport(UIKit)
import UIKit // For UIImage support
#endif

// Explicit imports for project-specific types:
// Ensure these types are accessible (public/internal) and correctly named.

// struct UserProfile is defined in Models/UserProfile.swift
// struct GridViewModel is defined in ViewModels/GridViewModel.swift (contains GridNode)
// struct Message is defined in Models/Message.swift
// struct ChatView is defined in Views/ChatView.swift (if it exists as a separate file)

// Add explicit imports for model types to resolve compilation errors
// These should be available since they're in the same target
// but explicit imports help with clarity and resolve any module issues
// Assuming GridNode is defined in GridViewModel or a similar accessible location.
// Assuming Message is in Models and ChatView is in Views.
// If these paths are incorrect, the build will fail, and we can adjust.

// Helper to load image from CKAsset
@MainActor // Ensure UI updates are on the main thread
class ImageLoader: ObservableObject {
    @Published var image: Image? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private var currentAsset: CKAsset?
    private var imageLoadingTask: Task<Void, Never>? // Store the task to allow cancellation

    func loadImage(from asset: CKAsset?) {
        guard let asset = asset else {
            self.image = nil
            self.currentAsset = nil
            return
        }
        // Avoid reloading the same asset if already loaded or loading
        guard asset.fileURL?.absoluteString != currentAsset?.fileURL?.absoluteString || image == nil else { return }
        
        isLoading = true
        self.currentAsset = asset
        self.errorMessage = nil

        // Cancel any existing task before starting a new one
        imageLoadingTask?.cancel()

        imageLoadingTask = Task {
            do {
                var validFileURL: URL?
                
                // First, check if we have a valid fileURL that points to an existing file
                if let fileURL = asset.fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                    validFileURL = fileURL
                } else {
                    // The asset's fileURL is either nil or points to a non-existent file
                    // This commonly happens with CloudKit assets that need to be downloaded
                    print("ImageLoader: CKAsset fileURL is missing or invalid. Attempting to handle CloudKit asset...")
                    
                    // For CloudKit assets, we need to ensure the file is downloaded
                    // Unfortunately, CKAsset doesn't provide a direct download method in client code
                    // The download typically happens automatically when the record is fetched with the proper options
                    
                    // If we still don't have a valid fileURL after checking, we'll have to throw an error
                    throw NSError(domain: "ImageLoader", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "CKAsset file is not available locally. This may be due to the asset not being downloaded from CloudKit, or the original temp file being deleted."
                    ])
                }
                
                // Load the image data from the valid file URL
                guard let finalFileURL = validFileURL else {
                    throw NSError(domain: "ImageLoader", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No valid file URL available for CKAsset."
                    ])
                }
                
                let data = try Data(contentsOf: finalFileURL)
                #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create UIImage from the asset data."
                    ])
                }
                #else
                // For macOS or other platforms without UIKit
                guard let nsImage = NSImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create NSImage from the asset data."
                    ])
                }
                let uiImage = nsImage
                #endif
                
                // Successfully loaded image
                await MainActor.run {
                    #if canImport(UIKit)
                    self.image = Image(uiImage: uiImage)
                    #else
                    self.image = Image(nsImage: uiImage) // uiImage is actually nsImage on macOS
                    #endif
                    self.isLoading = false
                }
                
            } catch {
                print("Failed to load image from CKAsset: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Could not load image."
                    self.image = nil // Clear previous image on error
                    self.isLoading = false
                }
            }
        }
    }

    func cancel() {
        imageLoadingTask?.cancel()
        isLoading = false // Optionally reset loading state
        // currentAsset = nil // Optionally clear current asset
        print("ImageLoader: Cancelled image loading task.")
    }
}

// Define an Identifiable struct for the chat recipient
struct ChatRecipient: Identifiable {
    let id: String // Represents the deviceID
}

// Define an Identifiable struct for the profile card
struct ProfileCardUser: Identifiable { // NEW
    let id: String // deviceID of the user whose profile to show
    let userProfile: UserProfile // The actual profile
}

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showingConversationsList = false  // NEW: For conversations list
    @State private var selectedUserProfileForCard: ProfileCardUser? = nil // NEW: For profile card
    @State private var showProfileOverlay = false
    @State private var overlayProfile: UserProfile? = nil
    @State private var showingSettingsMenu = false
    @State private var gridColumns: Int = 3 // Dynamic column count
    @State private var baseColumns: Int = 3 // The confirmed column count
    @State private var currentScale: CGFloat = 1.0
    @State private var isScaling = false
    var signOutAction: () -> Void
    var deleteAccountAction: () -> Void

    @State private var showingDeleteConfirmation = false
    
    // Define column count limits
    private let minColumns = 2
    private let maxColumns = 5
    
    // Calculate preview columns based on scale
    private func previewColumns(for scale: CGFloat) -> Int {
        let scaleThreshold: CGFloat = 0.25
        let columnDelta = Int((1.0 - scale) / scaleThreshold)
        let previewCols = baseColumns + columnDelta
        return max(minColumns, min(maxColumns, previewCols))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let profile = viewModel.currentUserProfile {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns), spacing: 2) {
                            ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                                GridNodeView(
                                    node: node,
                                    viewModel: viewModel,
                                    onProfileTapped: { profile in // For long press
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            self.overlayProfile = profile
                                            self.showProfileOverlay = true
                                        }
                                    },
                                    onChatTapped: { recipientDeviceID in
                                        viewModel.chatRecipientToPresent = ChatRecipient(id: recipientDeviceID)
                                    }
                                )
                            }
                        }
                        .padding()
                        .onAppear {
                            let totalNodes = viewModel.gridNodes.flatMap { $0 }.count
                            let rowCount = Int(ceil(Double(totalNodes) / Double(gridColumns)))
                            print("GridView Debug: Total nodes: \(totalNodes), Columns: \(gridColumns), Rows: \(rowCount)")
                            print("GridView Debug: isScaling: \(isScaling)")
                        }
                    }
                    .scrollDisabled(isScaling) // Disable scroll during pinch
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                if !isScaling {
                                    isScaling = true
                                    baseColumns = gridColumns
                                    
                                    // Haptic feedback when starting pinch
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    #endif
                                }
                                currentScale = value
                                
                                // Update columns in real-time based on scale
                                let newColumns = previewColumns(for: value)
                                if newColumns != gridColumns {
                                    // Haptic feedback on column change
                                    #if os(iOS)
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    #endif
                                    
                                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                                        gridColumns = newColumns
                                    }
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    // Confirm the column count
                                    baseColumns = gridColumns
                                    currentScale = 1.0
                                    isScaling = false
                                }
                                
                                // Final haptic feedback
                                #if os(iOS)
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                #endif
                            }
                    )
                    .refreshable {
                        await refreshGrid()
                    }
                } else {
                    Text("Loading profile or no profile set...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .onAppear {
                // Auto-refresh when grid appears
                viewModel.handleGridAppeared()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingConversationsList = true }) {
                            Label("Conversations", systemImage: "message")
                        }
                        
                        Button(action: {
                            if let myDeviceID = viewModel.currentUserProfile?.deviceID {
                                viewModel.chatRecipientToPresent = ChatRecipient(id: myDeviceID)
                            }
                        }) {
                            Label("My Notes", systemImage: "note.text")
                        }
                        
                        Divider()
                        
                        Button(action: signOutAction) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Account", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                }
            }
            .sheet(isPresented: $showingConversationsList) {
                ConversationsListView(viewModel: viewModel) { deviceID in
                    showingConversationsList = false
                    viewModel.chatRecipientToPresent = ChatRecipient(id: deviceID)
                }
            }
            .sheet(item: $viewModel.chatRecipientToPresent) { (recipient: ChatRecipient) in
                NavigationView {
                    ChatView(viewModel: viewModel, recipientDeviceID: recipient.id)
                }
            }
            .sheet(item: $selectedUserProfileForCard) { profileUser in // NEW: Sheet for Profile Card
                // Placeholder for ProfileCardView - will be created next
                // For now, just a simple view to confirm it works
                ProfileCardView(viewModel: viewModel, userProfile: profileUser.userProfile)
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteAccountAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
        }
        .overlay(
            // Profile overlay that appears on long press
            Group {
                if showProfileOverlay, let profile = overlayProfile {
                    ZStack {
                        // Semi-transparent background to dim the grid
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                            }
                        
                        // Profile card overlay
                        ProfileOverlayView(
                            userProfile: profile,
                            viewModel: viewModel,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                            },
                            onChat: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showProfileOverlay = false
                                    overlayProfile = nil
                                }
                                viewModel.chatRecipientToPresent = ChatRecipient(id: profile.deviceID)
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showProfileOverlay)
        )
    }
    
    @MainActor
    private func refreshGrid() async {
        print("GridView: Refreshing grid via pull-to-refresh")
        
        // Call the viewModel's refresh method
        viewModel.refreshPublicGrid()
        
        return await withCheckedContinuation { continuation in
            // Give it a moment to refresh, then complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }
    }
}

struct GridNodeView: View {
    let node: GridNode
    let viewModel: GridViewModel
    let onProfileTapped: (UserProfile) -> Void // NEW: For single tap
    let onChatTapped: (String) -> Void // For double tap (was single tap)
    @StateObject private var imageLoader = ImageLoader()

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
            .background(Color.gray.opacity(0.1)) // Background for empty or loading states
            .clipShape(Rectangle()) // Or Circle(), depending on desired node shape
            
            // Distance and status overlays
            if let profile = node.userProfile {
                VStack {
                    // Top right: Unread message badge
                    HStack {
                        Spacer()
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
                                .padding(4)
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom overlay: Distance only (simplified)
                    if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
                       profile.deviceID == currentUserDeviceID {
                        // "Me" label for current user
                        Text("Me")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    } else {
                        // Just show distance for other users
                        if let distanceString = viewModel.getDistanceString(to: profile.deviceID) {
                            Text(distanceString)
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                // .padding(.horizontal, 8)
                                // .padding(.vertical, 4)
                                // .background(Color.black.opacity(0.7))
                                // .cornerRadius(6)
                                // .padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .onAppear {
            imageLoader.loadImage(from: node.userProfile?.profileImage)
        }
        .onChange(of: node.userProfile?.profileImage?.fileURL) { _ in // Try to reload if asset URL changes
            imageLoader.loadImage(from: node.userProfile?.profileImage)
        }
        // Double tap gesture for profile overlay (must be before single tap)
        .onTapGesture(count: 2) {
            if let userProfile = node.userProfile {
                // Haptic feedback for double tap
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                #endif
                
                onProfileTapped(userProfile)
            }
        }
        // Single tap gesture for chat
        .onTapGesture {
            if let userProfile = node.userProfile {
                let messagingStatus = viewModel.canMessageUser(deviceID: userProfile.deviceID)
                if messagingStatus.allowed || userProfile.deviceID == viewModel.currentUserProfile?.deviceID {
                    onChatTapped(userProfile.deviceID)
                } else {
                    print("Cannot message user: \(messagingStatus.reason)")
                    // Optionally show an alert here
                }
            }
        }
        // Long press gesture for profile overlay
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
}

// NEW: Conversations List for instant chat access
struct ConversationsListView: View {
    @ObservedObject var viewModel: GridViewModel
    let onChatSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                let conversations = viewModel.getConversationList()
                
                if conversations.isEmpty {
                    VStack {
                        Image(systemName: "message.circle")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No conversations yet")
                            .foregroundColor(.gray)
                        Text("Tap on someone in the grid to start chatting!")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text("Double tap or long press to view profile")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations, id: \.deviceID) { conversation in
                        ConversationRowView(
                            displayName: conversation.displayName,
                            lastMessage: conversation.lastMessage,
                            messageCount: conversation.messageCount,
                            onTap: {
                                onChatSelected(conversation.deviceID)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let displayName: String
    let lastMessage: Message?
    let messageCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if messageCount > 0 {
                            Text("\(messageCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let lastMessage = lastMessage {
                        HStack {
                            Text(lastMessage.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            Spacer()
                            
                            Text(lastMessage.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Overlay View (for long press)

struct ProfileOverlayView: View {
    let userProfile: UserProfile
    let viewModel: GridViewModel
    let onClose: () -> Void
    let onChat: () -> Void
    
    @StateObject private var imageLoader = ImageLoader()
    
    private var isCurrentUser: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Close button bar
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding()
            }
            
            // Main content card
            VStack(spacing: 16) {
                // Profile image
                Group {
                    if imageLoader.isLoading {
                        ProgressView()
                            .frame(width: 120, height: 120)
                    } else if let image = imageLoader.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(30)
                                    .foregroundColor(.gray)
                            )
                    }
                }
                
                // Name
                Text(userProfile.deviceName ?? "Unknown User")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Distance (if not current user)
                if !isCurrentUser {
                    if let distanceString = viewModel.getDistanceString(to: userProfile.deviceID) {
                        Text(distanceString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Bio
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(userProfile.bio ?? "No bio available.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.horizontal)
                
                // Chat button
                Button(action: onChat) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(isCurrentUser ? "My Notes" : "Chat")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.top)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 10)
            .frame(maxWidth: 350)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            imageLoader.loadImage(from: userProfile.profileImage)
        }
    }
}

// MARK: - Profile Card View (NEW)

struct ProfileCardView: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    @Environment(\.dismiss) var dismiss

    @State private var bioText: String = ""
    @State private var isEditingBio: Bool = false

    // Image loaders for main photo
    @StateObject private var mainImageLoader = ImageLoader()
    
    // Photo editing states
    @State private var selectedMainPhotoItem: PhotosPickerItem? = nil
    @State private var selectedMainPhotoData: Data? = nil
    @State private var isSavingPhotos = false

    private var isCurrentUserProfile: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Profile Photo Section
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Group {
                                if mainImageLoader.isLoading {
                                    ProgressView().frame(width: 120, height: 120)
                                } else if let image = mainImageLoader.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    Circle().fill(Color.gray.opacity(0.3))
                                        .frame(width: 120, height: 120)
                                        .overlay(Image(systemName: "person.fill").resizable().scaledToFit().padding(30).foregroundColor(.gray))
                                }
                            }
                            Spacer()
                        }

                        Text(userProfile.deviceName ?? "User")
                            .font(.title)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // Main photo editing (only for current user)
                        if isCurrentUserProfile {
                            PhotosPicker(selection: $selectedMainPhotoItem, matching: .images, photoLibrary: .shared()) {
                                Text(selectedMainPhotoData != nil ? "Change Main Photo" : "Update Main Photo")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .onChange(of: selectedMainPhotoItem) { newItem in
                                Task {
                                    if let item = newItem, let data = try? await item.loadTransferable(type: Data.self) {
                                        selectedMainPhotoData = data
                                        saveMainPhoto()
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Bio Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Me")
                            .font(.headline)
                        
                        if isCurrentUserProfile {
                            if isEditingBio {
                                TextEditor(text: $bioText)
                                    .frame(height: 100)
                                    .border(Color.gray.opacity(0.5), width: 1)
                                HStack {
                                    Button("Cancel") {
                                        isEditingBio = false
                                        bioText = viewModel.currentUserProfile?.bio ?? ""
                                    }
                                    .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Save Bio") {
                                        isEditingBio = false
                                        viewModel.updateUserProfileBio(bio: bioText) { success in
                                            if success {
                                                print("Bio updated successfully.")
                                            } else {
                                                print("Failed to update bio.")
                                            }
                                        }
                                    }
                                    .foregroundColor(.blue)
                                }
                            } else {
                                Text(bioText.isEmpty ? "No bio yet. Tap to edit." : bioText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        isEditingBio = true
                                    }
                            }
                        } else {
                            Text(userProfile.bio ?? "No bio available.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Chat Button
                    if !isCurrentUserProfile {
                        Button("Chat") {
                            dismiss()
                            viewModel.chatRecipientToPresent = ChatRecipient(id: userProfile.deviceID)
                        }
                    } else {
                        Button("My Notes") {
                            dismiss()
                            viewModel.chatRecipientToPresent = ChatRecipient(id: userProfile.deviceID)
                        }
                    }
                }
            }
            .onAppear {
                mainImageLoader.loadImage(from: userProfile.profileImage)
                bioText = isCurrentUserProfile ? (viewModel.currentUserProfile?.bio ?? "") : (userProfile.bio ?? "")
            }
        }
    }
    
    // MARK: - Photo Management Functions
    
    private func saveMainPhoto() {
        guard let photoData = selectedMainPhotoData else { return }
        
        isSavingPhotos = true
        
        viewModel.updateCurrentProfileImage(newPhotoData: photoData)
        
        // Reload the main image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            mainImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
            selectedMainPhotoData = nil
            selectedMainPhotoItem = nil
            isSavingPhotos = false
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(userID: "previewUser123", 
                                       deviceID: "previewDeviceID_789", 
                                       deviceName: "Preview Device", 
                                       profileImage: nil as CKAsset?)
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        if !mockViewModel.gridNodes.isEmpty && !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        
        return GridView(viewModel: mockViewModel, signOutAction: {}, deleteAccountAction: {})
    }
} 
