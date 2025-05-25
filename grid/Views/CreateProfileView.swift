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

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
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

                if let selectedPhotoData, let uiImage = UIImage(data: selectedPhotoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .padding()
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .overlay(Image(systemName: "person.fill").resizable().scaledToFit().frame(width: 100).foregroundColor(.gray))
                        .padding()
                }

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images, // Only pick images
                    photoLibrary: .shared() // Use the shared photo library
                ) {
                    Text(selectedPhotoItem == nil ? "Select Photo" : "Change Photo")
                }
                .padding()
                .onChange(of: selectedPhotoItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedPhotoData = data
                            errorMessage = nil // Clear previous error if new photo is selected
                        } else {
                            print("Failed to load photo data.")
                            errorMessage = "Could not load image. Please try another."
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
                .disabled(selectedPhotoData == nil || isSaving) // Disable if no photo or already saving
                
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
        guard let photoData = selectedPhotoData else {
            errorMessage = "No photo selected."
            return
        }
        guard !appleUserID.isEmpty else {
            errorMessage = "User ID is missing. Cannot save profile."
            return
        }

        isSaving = true
        errorMessage = nil

        // 1. Create a temporary file URL for the CKAsset
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")

        do {
            try photoData.write(to: tempFileURL)
            let photoAsset = CKAsset(fileURL: tempFileURL)
            
            // Create profile with device-specific information
            let newProfile = UserProfile(
                userID: appleUserID,
                deviceID: deviceID,
                deviceName: deviceName,
                profileImage: photoAsset
            )
            
            // Save to PUBLIC database so everyone can see this profile on the grid
            let publicRecord = newProfile.toPublicCKRecord()
            let publicDB = CKContainer.default().publicCloudDatabase

            // Use modifyRecords to handle both insert and update cases
            let modifyOperation = CKModifyRecordsOperation(recordsToSave: [publicRecord], recordIDsToDelete: nil)
            modifyOperation.savePolicy = .changedKeys // Only update changed fields
            modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
                // Attempt to remove the temporary file whether save succeeds or fails
                try? FileManager.default.removeItem(at: tempFileURL)
                
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
        } catch {
            print("Error writing photo data to temporary file: \(error.localizedDescription)")
            self.errorMessage = "Could not process photo for saving."
            isSaving = false
            // Attempt to remove temp file if write failed partway or if other error before CK save
            try? FileManager.default.removeItem(at: tempFileURL)
        }
    }
}

struct CreateProfileView_Previews: PreviewProvider {
    static var previews: some View {
        CreateProfileView(showCreateProfileView: .constant(true), appleUserID: "previewUserID_123")
    }
} 