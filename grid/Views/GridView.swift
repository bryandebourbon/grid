import SwiftUI
import CloudKit // For CKAsset
import PhotosUI // For PhotosPicker
#if canImport(UIKit)
import UIKit // For UIImage support
#endif

// Helper to load image from CKAsset
@MainActor // Ensure UI updates are on the main thread
class ImageLoader: ObservableObject {
    @Published var image: Image? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private var currentAsset: CKAsset?

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

        Task {
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
                guard let uiImage = UIImage(data: data) else {
                    throw NSError(domain: "ImageLoader", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not create UIImage from the asset data."
                    ])
                }
                
                // Successfully loaded image
                await MainActor.run {
                    self.image = Image(uiImage: uiImage)
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
}

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showingEditProfilePhotoSheet = false
    @State private var showingChatView = false
    @State private var selectedChatRecipientDeviceID: String? = nil
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
                                    selectedChatRecipientDeviceID = recipientDeviceID
                                    showingChatView = true
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
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if viewModel.currentUserProfile != nil {
                        Button("Edit Photo") {
                            showingEditProfilePhotoSheet = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("My Notes") {
                        selectedChatRecipientDeviceID = viewModel.currentUserProfile?.deviceID // Chat with self for notes
                        showingChatView = true
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
            .sheet(isPresented: $showingChatView) {
                if let recipientDeviceID = selectedChatRecipientDeviceID {
                    NavigationView {
                        ChatView(viewModel: viewModel, recipientDeviceID: recipientDeviceID)
                    }
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
    @State private var imageToCrop: UIImage? = nil
    @State private var showingCropper = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) var dismiss

    // To display the current image
    @StateObject private var currentImageLoader = ImageLoader()

    var body: some View {
        NavigationView {
            Form {
                VStack(alignment: .center) {
                    Text("Current Photo:")
                    Group {
                        if currentImageLoader.isLoading {
                            ProgressView().frame(width: 150, height: 150)
                        } else if let currentImage = currentImageLoader.image {
                            currentImage.resizable().scaledToFit().frame(width: 150, height: 150).clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill").resizable().scaledToFit().frame(width: 150, height: 150).foregroundColor(.gray)
                        }
                    }
                    .padding(.bottom)

                    Text("New Photo Selection:")
                    if let selectedPhotoData, let uiImage = UIImage(data: selectedPhotoData) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 150, height: 150).clipShape(Circle()).padding(.bottom)
                    } else {
                         Image(systemName: "photo.on.rectangle.angled").resizable().scaledToFit().frame(width:100, height:100).foregroundColor(.gray).padding(.bottom)
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text(selectedPhotoItem == nil ? "Select New Photo" : "Change Selection")
                    }
                    .onChange(of: selectedPhotoItem) { newItem in
                        Task {
                            guard let item = newItem else {
                                self.selectedPhotoData = nil
                                self.errorMessage = nil
                                return
                            }

                            do {
                                if let data = try await item.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    self.imageToCrop = uiImage
                                    self.showingCropper = true
                                    self.errorMessage = nil
                                } else {
                                    print("Photo data is nil but no error thrown by loadTransferable.")
                                    self.selectedPhotoData = nil
                                    self.errorMessage = "Could not retrieve image data. Please select a valid image."
                                }
                            } catch {
                                print("Failed to load photo data: \(error.localizedDescription)")
                                self.selectedPhotoData = nil
                                self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                            }
                        }
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
            #if canImport(UIKit)
            .sheet(isPresented: $showingCropper) {
                if let image = imageToCrop {
                    ImageCropperView(image: image) { cropped in
                        selectedPhotoData = cropped.jpegData(compressionQuality: 0.8)
                    }
                }
            }
            #endif
            .onAppear {
                currentImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
                selectedPhotoItem = nil
                selectedPhotoData = nil
            }
        }
    }

    private func saveProfilePhoto() {
        guard let photoData = selectedPhotoData else {
            errorMessage = "No new photo selected."
            return
        }
        isSaving = true
        errorMessage = nil
        viewModel.updateCurrentProfileImage(newPhotoData: photoData) 
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            dismiss()
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(userID: "previewUser123", profileImage: nil)
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        if !mockViewModel.gridNodes.isEmpty && !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        
        return GridView(viewModel: mockViewModel, signOutAction: {}, deleteAccountAction: {})
    }
} 