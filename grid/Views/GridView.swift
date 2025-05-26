import SwiftUI
import CloudKit // For CKAsset
import PhotosUI // For PhotosPicker
#if canImport(UIKit)
import UIKit // For UIImage support
#endif

// Import the model files to resolve type errors
// These should be available since they're in the same target
// but explicit imports help with clarity and resolve any module issues

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

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showingEditProfilePhotoSheet = false
    @State private var showingConversationsList = false  // NEW: For conversations list
    var signOutAction: () -> Void
    var deleteAccountAction: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationView {
            VStack {
                // Location permission status and coordinates
                Text(viewModel.locationPermissionStatus)
                    .font(.caption2)
                    .foregroundColor(viewModel.locationPermissionStatus.contains("granted") ? .green : .orange)
                    .padding(.horizontal)
                
                // DEBUG: Show current location coordinates
                if let profile = viewModel.currentUserProfile,
                   let lat = profile.latitude,
                   let lon = profile.longitude {
                    Text("My Position: \(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                }
                
                if let profile = viewModel.currentUserProfile {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: viewModel.gridSize), spacing: 2) {
                            ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                                GridNodeView(node: node, viewModel: viewModel, onChatTapped: { recipientDeviceID in
                                    viewModel.chatRecipientToPresent = ChatRecipient(id: recipientDeviceID)
                                })
                            }
                        }
                        .padding()
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .refreshable {
                        await refreshGrid()
                    }
                    .border(Color.gray)
                } else {
                    Text("Loading profile or no profile set...")
                }
                Spacer()
            }
            .navigationTitle("The Grid")
            .onAppear {
                // Auto-refresh when grid appears
                viewModel.handleGridAppeared()
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if viewModel.currentUserProfile != nil {
                        Button("Edit Photo") {
                            showingEditProfilePhotoSheet = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Conversations") {
                        showingConversationsList = true
                    }
                    Button("My Notes") {
                        if let myDeviceID = viewModel.currentUserProfile?.deviceID {
                            viewModel.chatRecipientToPresent = ChatRecipient(id: myDeviceID)
                        }
                    }
                    Button("Sign Out") {
                        signOutAction()
                    }
                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .sheet(isPresented: $showingEditProfilePhotoSheet) {
                EditProfilePhotoView(viewModel: viewModel)
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
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteAccountAction() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
        }
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
    let onChatTapped: (String) -> Void
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
                    Spacer()
                    
                    // Bottom overlay: Distance only (simplified)
                    if let currentUserDeviceID = viewModel.currentUserProfile?.deviceID,
                       profile.deviceID == currentUserDeviceID {
                        // "Me" label for current user
                        Text("Me")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(8)
                            .padding(.bottom, 4)
                    } else {
                        // Just show distance for other users
                        if let distanceString = viewModel.getDistanceString(to: profile.deviceID) {
                            Text(distanceString)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(6)
                                .padding(.bottom, 4)
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
        .onTapGesture {
            // When tapping a grid node with a user, check if messaging is allowed
            if let userProfile = node.userProfile {
                let messagingStatus = viewModel.canMessageUser(deviceID: userProfile.deviceID)
                if messagingStatus.allowed || userProfile.deviceID == viewModel.currentUserProfile?.deviceID {
                    // Allow chat if messaging is allowed or it's the current user (for notes)
                    onChatTapped(userProfile.deviceID)
                } else {
                    // TODO: Show alert explaining why messaging is not allowed
                    print("Cannot message user: \(messagingStatus.reason)")
                }
            }
        }
    }
}

// Profile photo editing view
struct EditProfilePhotoView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) var dismiss

    @StateObject private var currentImageLoader = ImageLoader()
    @State private var additionalImageLoaders: [ImageLoader] = [] // Changed from @StateObject
    @State private var existingAdditionalPhotoAssets: [CKAsset] = []

    // For new photo selections
    @State private var newSelectedPhotoItems: [PhotosPickerItem] = []
    @State private var newSelectedPhotoDataArray: [Data] = []

    var body: some View {
        NavigationView {
            Form {
                VStack(spacing: 20) {
                    Text("Main Profile Photo").font(.headline)
                    // Current main profile photo display
                    Group {
                        if currentImageLoader.isLoading {
                            ProgressView().frame(width: 150, height: 150)
                        } else if let loadedImage = currentImageLoader.image {
                            loadedImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(Color.secondary.opacity(0.3)).frame(width: 150, height: 150)
                                .overlay(Image(systemName: "person.fill").resizable().scaledToFit().frame(width: 75).foregroundColor(.gray))
                        }
                    }

                    // Picker for new MAIN photo (singular)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text(selectedPhotoData != nil ? "Change Main Photo" : "Select Main Photo")
                    }
                    .onChange(of: selectedPhotoItem) { newItem in
                        Task {
                            if let item = newItem, let data = try? await item.loadTransferable(type: Data.self) {
                                self.selectedPhotoData = data // This is for the main profile image
                                self.errorMessage = nil
                            } else {
                                self.selectedPhotoData = nil
                                // Optionally show an error if loading the main photo fails
                            }
                        }
                    }
                    
                    Divider()
                    
                    Text("Additional Photos (up to 9)").font(.headline)
                    
                    // Display existing additional photos
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(zip(additionalImageLoaders.indices, additionalImageLoaders)), id: \.0) { index, loader in
                                ZStack(alignment: .topTrailing) {
                                    if loader.isLoading { ProgressView().frame(width: 100, height: 100) }
                                    else if let img = loader.image {
                                        img.resizable().scaledToFill().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.2)).frame(width: 100, height: 100)
                                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                                    }
                                    Button(action: { removeAdditionalPhoto(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Circle().fill(Color.white))
                                    }
                                    .padding(4)
                                }
                                .padding(.trailing, 5)
                            }
                        }
                    }
                    .frame(height: 110)

                    // Picker for ADDING NEW additional photos
                    if (existingAdditionalPhotoAssets.count + newSelectedPhotoDataArray.count) < 9 {
                        PhotosPicker(
                            selection: $newSelectedPhotoItems,
                            maxSelectionCount: 9 - (existingAdditionalPhotoAssets.count + newSelectedPhotoDataArray.count), // Limit to remaining slots
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("Add More Photos")
                        }
                        .onChange(of: newSelectedPhotoItems) { items in
                            Task {
                                // Append new data, don't replace existing newSelectedPhotoDataArray entirely unless intended
                                for item in items {
                                    if let data = try? await item.loadTransferable(type: Data.self) {
                                        if !newSelectedPhotoDataArray.contains(data) { // Avoid duplicates if re-picking
                                           newSelectedPhotoDataArray.append(data)
                                        }
                                    } else {
                                        print("Failed to load data for an additional photo item.")
                                    }
                                }
                                // Clear the picker selection to allow picking more or the same items again if needed
                                newSelectedPhotoItems = [] 
                            }
                        }
                    }
                    
                    // Display newly selected additional photos (not yet saved)
                    if !newSelectedPhotoDataArray.isEmpty {
                        Text("New photos to add:").font(.caption)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(newSelectedPhotoDataArray, id: \.self) { data in
                                    if let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 8))
                                            .padding(.trailing, 5)
                                    }
                                }
                            }
                        }
                        .frame(height: 80)
                    }
                }
                .frame(maxWidth: .infinity)

                if let errorMessage = errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }

                Button(action: { saveProfilePhoto() }) {
                    if isSaving { ProgressView() } else { Text("Save New Photo") }
                }
                .disabled(selectedPhotoData == nil || isSaving)
            }
            .navigationTitle("Edit Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { if !isSaving { dismiss() } }
                }
            }
            .onAppear {
                currentImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
                selectedPhotoItem = nil 
                selectedPhotoData = nil
                
                // Load existing additional photos
                existingAdditionalPhotoAssets = viewModel.currentUserProfile?.additionalPhotos ?? [] // Renamed field
                additionalImageLoaders.forEach { $0.cancel() } // Cancel any ongoing loads
                additionalImageLoaders = existingAdditionalPhotoAssets.map { asset in
                    let loader = ImageLoader()
                    loader.loadImage(from: asset)
                    return loader
                }
                newSelectedPhotoItems = []
                newSelectedPhotoDataArray = []
            }
        }
    }

    private func removeAdditionalPhoto(at index: Int) {
        guard index < existingAdditionalPhotoAssets.count else { return }
        existingAdditionalPhotoAssets.remove(at: index)
        // also remove the corresponding loader
        additionalImageLoaders.remove(at: index)
        // The UI will update automatically. The actual deletion from CloudKit will happen on save.
    }

    private func saveProfilePhoto() {
        // This function now needs to handle:
        // 1. A potentially new main profile image (selectedPhotoData).
        // 2. An updated list of additional photos (from existingAdditionalPhotoAssets and newSelectedPhotoDataArray).
        isSaving = true
        errorMessage = nil

        var finalAdditionalPhotoAssets: [CKAsset] = existingAdditionalPhotoAssets
        var tempNewAssetFileURLs: [URL] = []

        // Convert new additional photo data to CKAssets
        for photoData in newSelectedPhotoDataArray {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do {
                try photoData.write(to: tempFileURL)
                finalAdditionalPhotoAssets.append(CKAsset(fileURL: tempFileURL))
                tempNewAssetFileURLs.append(tempFileURL)
            } catch {
                print("Error writing new additional photo data to temp file: \(error.localizedDescription)")
                errorMessage = "Could not process one of the new additional photos."
                isSaving = false
                // Clean up any temp files created in this loop so far
                for url in tempNewAssetFileURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }
        }
        
        // Limit to 9 additional photos (as per earlier logic, could be 10 based on total)
        if finalAdditionalPhotoAssets.count > 9 {
            // This case should ideally be prevented by the UI, but as a safeguard:
            finalAdditionalPhotoAssets = Array(finalAdditionalPhotoAssets.prefix(9))
            // Note: Temp files for truncated assets won't be cleaned up here unless managed carefully.
            // Best to ensure UI prevents >9 additional photos from being staged.
        }

        viewModel.updateProfilePhotos(mainPhotoData: selectedPhotoData, additionalPhotoAssets: finalAdditionalPhotoAssets) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    dismiss()
                } else {
                    errorMessage = "Failed to save photos. Please try again."
                    // viewModel should handle cleanup of its own temp files on failure.
                    // Cleanup temp files created in *this* view for *new* assets if viewModel doesn't take ownership or on failure
                    for url in tempNewAssetFileURLs {
                         try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(userID: "previewUser123", 
                                       deviceID: "previewDeviceID_789", 
                                       deviceName: "Preview Device", 
                                       profileImage: nil)
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        if !mockViewModel.gridNodes.isEmpty && !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        
        return GridView(viewModel: mockViewModel, signOutAction: {}, deleteAccountAction: {})
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