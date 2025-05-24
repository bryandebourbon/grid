import SwiftUI
import CloudKit // For CKAsset
import PhotosUI // For PhotosPicker
import UIKit // For UIImage support

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

    var body: some View {
        NavigationView {
            VStack {
                Text(viewModel.connectedPeersText)
                    .font(.caption)
                    .padding(.top)

                if viewModel.currentUserProfile != nil {
                    // No welcome message with username anymore
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: viewModel.gridSize), spacing: 2) {
                        ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                            GridNodeView(node: node)
                        }
                    }
                    .padding()
                    .aspectRatio(1, contentMode: .fit)
                    .border(Color.gray)
                } else {
                    Text("Loading profile or no profile set...")
                }
                Spacer()
            }
            .navigationTitle("The Grid")
            .toolbar {
                 if viewModel.currentUserProfile != nil {
                     Button("Edit Photo") { // Changed from Edit Username
                         showingEditProfilePhotoSheet = true
                     }
                 }
            }
            .sheet(isPresented: $showingEditProfilePhotoSheet) {
                EditProfilePhotoView(viewModel: viewModel) // Changed to EditProfilePhotoView
            }
        }
    }
}

struct GridNodeView: View {
    let node: GridNode
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
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
        .onAppear {
            imageLoader.loadImage(from: node.userProfile?.profileImage)
        }
        .onChange(of: node.userProfile?.profileImage?.fileURL) { _ in // Try to reload if asset URL changes
            imageLoader.loadImage(from: node.userProfile?.profileImage)
        }
    }
}

// Renamed from EditUsernameView to EditProfilePhotoView
struct EditProfilePhotoView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
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
                        // newItem is the selected PhotosPickerItem?
                        Task {
                            guard let item = newItem else { // Use newItem for the new value
                                // newItem is nil (e.g. user deselected the photo)
                                // Clear the selectedPhotoData and any error message.
                                self.selectedPhotoData = nil
                                self.errorMessage = nil
                                return
                            }

                            do {
                                if let data = try await item.loadTransferable(type: Data.self) {
                                    self.selectedPhotoData = data
                                    self.errorMessage = nil
                                } else {
                                    // This case might occur if loadTransferable returns nil for a non-image,
                                    // though 'matching: .images' should prevent this.
                                    print("Photo data is nil but no error thrown by loadTransferable.")
                                    self.selectedPhotoData = nil // Clear potentially stale data
                                    self.errorMessage = "Could not retrieve image data. Please select a valid image."
                                }
                            } catch {
                                print("Failed to load photo data: \(error.localizedDescription)")
                                self.selectedPhotoData = nil // Clear potentially stale data on error
                                self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if let errorMessage = errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }

//                Section {
                    Button(action: { saveProfilePhoto() }) {
                        if isSaving { ProgressView() } else { Text("Save New Photo") }
                    }
                    .disabled(selectedPhotoData == nil || isSaving)

                    if viewModel.currentUserProfile?.profileImage != nil {
//                        Button(action: { removeProfilePhoto() }, role: .destructive) {
//                             if isSaving { ProgressView() } else { Text("Remove Current Photo") }
//                        }
//                        .disabled(isSaving)
                    }
//                }
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
                // Clear selection when view appears
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
        // The ViewModel's method handles CKAsset creation and local update.
        // CloudKit persistence should be triggered by ContentView observing viewModel.currentUserProfile.
        // ViewModel should also manage temporary file cleanup via callbacks or by being responsible for the save.
        // For now, we assume ViewModel sets the local profileImage and ContentView syncs it.
        
        // Simulate a delay for saving then dismiss
        // In a real app, you'd wait for a callback from the ViewModel or CloudKit operation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Short delay to allow UI update
            isSaving = false
            // Check if image was set in viewmodel before dismissing. For now, just dismiss.
            dismiss()
        }
    }

    private func removeProfilePhoto() {
        isSaving = true
        errorMessage = nil
        viewModel.updateCurrentProfileImage(newPhotoData: nil) // Pass nil to remove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            currentImageLoader.loadImage(from: nil) // Clear displayed current image
            dismiss() // Or stay if you want to allow picking another photo
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        // UserProfile now only takes userID and optional profileImage.
        // For preview, we can't easily create a CKAsset, so profileImage will be nil.
        let dummyProfile = UserProfile(userID: "previewUser123", profileImage: nil)
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        // Example: Add a node with a profile for preview
        if !mockViewModel.gridNodes.isEmpty && !mockViewModel.gridNodes[0].isEmpty {
            mockViewModel.gridNodes[0][0].userProfile = dummyProfile
        }
        
        return GridView(viewModel: mockViewModel)
    }
} 
