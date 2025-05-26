import SwiftUI
#if canImport(UIKit)
import UIKit // For iOS
#elseif canImport(AppKit)
import AppKit // For macOS
#endif
import CloudKit
import PhotosUI // Import for PhotosPicker

struct CreateProfileView: View {
    @Binding var showCreateProfileView: Bool
    let appleUserID: String 

    @State private var selectedPhotoItems: [PhotosPickerItem] = [] // For multiple photos
    @State private var selectedPhotoDataArray: [Data] = [] // Store data for multiple photos
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    // Generate device-specific info
    private let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let deviceName = UIDevice.current.name

    var body: some View {
        NavigationView {
            VStack {
                Text("Set Your Profile Photo")
                    .font(.largeTitle)
                    .padding()
                
                Text("Device: \(deviceName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)

                // Display selected photos
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedPhotoDataArray, id: \.self) { photoData in
                            if let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.trailing, 5)
                            }
                        }
                    }
                }
                .frame(height: 110) // Adjust height as needed
                .padding(.bottom)

                if selectedPhotoDataArray.isEmpty {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .overlay(Image(systemName: "person.fill").resizable().scaledToFit().frame(width: 100).foregroundColor(.gray))
                        .padding()
                }

                PhotosPicker(
                    selection: $selectedPhotoItems, // Bind to the array for multiple items
                    maxSelectionCount: 10, // Allow up to 10 photos
                    matching: .images, 
                    photoLibrary: .shared()
                ) {
                    Text(selectedPhotoItems.isEmpty ? "Select Photos" : "Change Photos")
                }
                .padding()
                .onChange(of: selectedPhotoItems) { newItems in
                    Task {
                        selectedPhotoDataArray.removeAll() // Clear previous selections
                        var loadedDataArray: [Data] = []
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                loadedDataArray.append(data)
                            } else {
                                print("Failed to load photo data for an item.")
                                // Optionally show an error for the specific item that failed
                            }
                        }
                        selectedPhotoDataArray = loadedDataArray
                        if !loadedDataArray.isEmpty {
                            errorMessage = nil // Clear error if photos are loaded
                        } else if !newItems.isEmpty {
                             errorMessage = "Could not load any of the selected images. Please try again."
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }

                Button(action: saveProfile) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save Profile")
                    }
                }
                .padding()
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhotoDataArray.isEmpty || isSaving) // Disable if no photos or already saving
                
                Spacer()
            }
            .navigationTitle("Create Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Only dismiss if not currently saving, or provide a way to cancel saving (more complex)
                        if !isSaving {
                            showCreateProfileView = false
                        }
                    }
                }
            }
        }
    }

    private func saveProfile() {
        guard !selectedPhotoDataArray.isEmpty else {
            errorMessage = "No photos selected."
            return
        }
        guard !appleUserID.isEmpty else {
            errorMessage = "User ID is missing. Cannot save profile."
            return
        }

        isSaving = true
        errorMessage = nil

        var photoAssets: [CKAsset] = []
        var tempFileURLs: [URL] = [] // Keep track of temp files to delete

        for photoData in selectedPhotoDataArray {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            
            do {
                try photoData.write(to: tempFileURL)
                photoAssets.append(CKAsset(fileURL: tempFileURL))
                tempFileURLs.append(tempFileURL) // Add to list for cleanup
            } catch {
                print("Error writing photo data to temporary file: \(error.localizedDescription)")
                errorMessage = "Could not process one or more photos for saving."
                // Attempt to clean up any files created so far before bailing
                for url in tempFileURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                isSaving = false
                return
            }
        }

        // Assuming the first photo is the main profile image, and the rest are additional.
        // You might want a separate picker or UI to distinguish the main profile image.
        let mainProfileImage = photoAssets.first 
        let additionalPhotos = photoAssets.count > 1 ? Array(photoAssets.dropFirst()) : nil

        let newProfile = UserProfile(
            userID: appleUserID,
            deviceID: deviceID,
            deviceName: deviceName,
            profileImage: mainProfileImage,
            additionalPhotos: additionalPhotos
        )
        
        // Save to PUBLIC database so everyone can see this profile on the grid
        let publicRecord = newProfile.toPublicCKRecord()
        let publicDB = CKContainer.default().publicCloudDatabase

        // Use modifyRecords to handle both insert and update cases
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [publicRecord], recordIDsToDelete: nil)
        modifyOperation.savePolicy = .changedKeys // Only update changed fields
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            // Attempt to remove ALL temporary files whether save succeeds or fails
            for url in tempFileURLs {
                try? FileManager.default.removeItem(at: url)
            }
            
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    print("Error saving/updating profile to public CloudKit: \(error.localizedDescription)")
                    self.errorMessage = "Failed to save profile: \(error.localizedDescription)"
                } else if savedRecords?.first != nil {
                    print("Profile saved/updated successfully to public database for device \(self.deviceName) (ID: \(self.deviceID))!")
                    self.showCreateProfileView = false 
                } else {
                    print("Unknown error saving profile.")
                    self.errorMessage = "An unknown error occurred while saving."
                }
            }
        }
        
        publicDB.add(modifyOperation)
    }
}

struct CreateProfileView_Previews: PreviewProvider {
    static var previews: some View {
        CreateProfileView(showCreateProfileView: .constant(true), appleUserID: "previewUserID_123")
    }
} 