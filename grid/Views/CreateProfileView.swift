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
    @State private var selectedInterests: Set<Interest> = [] // NEW: Selected interests
    @State private var currentStep: Int = 1 // NEW: Step tracking (1: Photos, 2: Interests, 3: Review)
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    // Generate device-specific info consistently across build types
    private var deviceID: String {
        return generateConsistentDeviceID(for: appleUserID)
    }
    private let deviceName = UIDevice.current.name

    // Generate a consistent device ID that works across dev builds, TestFlight, and App Store
    private func generateConsistentDeviceID(for userID: String) -> String {
        // Check if we have a stored device ID for this user
        let storedKey = "consistentDeviceID_\(userID)"
        if let storedDeviceID = UserDefaults.standard.string(forKey: storedKey) {
            return storedDeviceID
        }
        
        // Generate a stable device ID based on the Apple User ID
        // This ensures the same user gets the same device ID across dev builds, TestFlight, and App Store
        // We take the last part of the Apple User ID (after the last dot) and use it as our device identifier
        let userIDComponents = userID.components(separatedBy: ".")
        let userSuffix = userIDComponents.last ?? "default"
        let deviceID = "\(userSuffix)-DEVICE"
        
        // Store it for future use
        UserDefaults.standard.set(deviceID, forKey: storedKey)
        
        print("Generated consistent device ID: \(deviceID) for user: \(userID)")
        return deviceID
    }

    var body: some View {
        NavigationView {
            VStack {
                // Progress indicator
                HStack {
                    ForEach(1...3, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        if step < 3 {
                            Rectangle()
                                .fill(step < currentStep ? Color.blue : Color.gray.opacity(0.3))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Step content
                Group {
                    switch currentStep {
                    case 1:
                        photoSelectionStep
                    case 2:
                        interestSelectionStep
                    case 3:
                        reviewStep
                    default:
                        photoSelectionStep
                    }
                }
                
                Spacer()
                
                // Navigation buttons
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    Button(nextButtonTitle) {
                        if currentStep < 3 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        } else {
                            saveProfile()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isNextButtonDisabled)
                }
                .padding()
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if !isSaving {
                            showCreateProfileView = false
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Photo Selection Step
    
    private var photoSelectionStep: some View {
        VStack(spacing: 20) {
            Text("Add Your Photos")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Choose up to 10 photos to showcase yourself")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Device: \(deviceName)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Display selected photos
            if !selectedPhotoDataArray.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(selectedPhotoDataArray.enumerated()), id: \.offset) { index, photoData in
                            if let uiImage = UIImage(data: photoData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    if index == 0 {
                                        Text("Main")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .offset(x: -5, y: 5)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 120)
            } else {
                // Placeholder for no photos
                VStack(spacing: 15) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60)
                                .foregroundColor(.gray)
                        )
                    
                    Text("No photos selected")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 30)
            }

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images, 
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: selectedPhotoItems.isEmpty ? "photo" : "photo.badge.plus")
                    Text(selectedPhotoItems.isEmpty ? "Select Photos" : "Change Photos (\(selectedPhotoDataArray.count))")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)
            .onChange(of: selectedPhotoItems) { newItems in
                Task {
                    selectedPhotoDataArray.removeAll()
                    var loadedDataArray: [Data] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            loadedDataArray.append(data)
                        } else {
                            print("Failed to load photo data for an item.")
                        }
                    }
                    selectedPhotoDataArray = loadedDataArray
                    if !loadedDataArray.isEmpty {
                        errorMessage = nil
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
        }
    }
    
    // MARK: - Interest Selection Step
    
    private var interestSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 10) {
                    Text("What Are You Into?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Select your interests to find like-minded people nearby")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("\(selectedInterests.count) interests selected")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
                
                // Interest categories
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Interest.categories) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.name)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                ForEach(category.interests) { interest in
                                    InterestButton(
                                        interest: interest,
                                        isSelected: selectedInterests.contains(interest)
                                    ) {
                                        toggleInterest(interest)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Review Step
    
    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 25) {
                Text("Looking Good!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Review your profile before saving")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Photo preview
                if let firstPhoto = selectedPhotoDataArray.first,
                   let uiImage = UIImage(data: firstPhoto) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Device:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(deviceName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Photos:")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(selectedPhotoDataArray.count) selected")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interests (\(selectedInterests.count)):")
                            .fontWeight(.medium)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                            ForEach(Array(selectedInterests).sorted { $0.rawValue < $1.rawValue }) { interest in
                                Text(interest.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                
                if isSaving {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Creating your profile...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var stepTitle: String {
        switch currentStep {
        case 1: return "Add Photos"
        case 2: return "Select Interests"
        case 3: return "Review Profile"
        default: return "Create Profile"
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case 1: return "Next: Interests"
        case 2: return "Next: Review"
        case 3: return isSaving ? "Saving..." : "Create Profile"
        default: return "Next"
        }
    }
    
    private var isNextButtonDisabled: Bool {
        switch currentStep {
        case 1: return selectedPhotoDataArray.isEmpty
        case 2: return selectedInterests.isEmpty
        case 3: return isSaving
        default: return false
        }
    }
    
    private func toggleInterest(_ interest: Interest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }

    private func saveProfile() {
        guard !selectedPhotoDataArray.isEmpty else {
            errorMessage = "No photos selected."
            return
        }
        guard !selectedInterests.isEmpty else {
            errorMessage = "Please select at least one interest."
            return
        }
        guard !appleUserID.isEmpty else {
            errorMessage = "User ID is missing. Cannot save profile."
            return
        }

        isSaving = true
        errorMessage = nil

        var photoAssets: [CKAsset] = []
        var tempFileURLs: [URL] = []

        for photoData in selectedPhotoDataArray {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            
            do {
                try photoData.write(to: tempFileURL)
                photoAssets.append(CKAsset(fileURL: tempFileURL))
                tempFileURLs.append(tempFileURL)
            } catch {
                print("Error writing photo data to temporary file: \(error.localizedDescription)")
                errorMessage = "Could not process one or more photos for saving."
                for url in tempFileURLs {
                    try? FileManager.default.removeItem(at: url)
                }
                isSaving = false
                return
            }
        }

        let mainProfileImage = photoAssets.first 
        let additionalPhotos = photoAssets.count > 1 ? Array(photoAssets.dropFirst()) : nil

        let newProfile = UserProfile(
            userID: appleUserID,
            deviceID: deviceID,
            deviceName: deviceName,
            profileImage: mainProfileImage,
            additionalPhotos: additionalPhotos,
            bio: nil,
            interests: Array(selectedInterests)
        )
        
        let publicRecord = newProfile.toPublicCKRecord()
        let publicDB = CKContainer.default().publicCloudDatabase

        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [publicRecord], recordIDsToDelete: nil)
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            for url in tempFileURLs {
                try? FileManager.default.removeItem(at: url)
            }
            
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    print("Error saving profile to public CloudKit: \(error.localizedDescription)")
                    self.errorMessage = "Failed to save profile: \(error.localizedDescription)"
                } else if savedRecords?.first != nil {
                    print("Profile saved successfully with \(self.selectedInterests.count) interests!")
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

// MARK: - Interest Button Component

struct InterestButton: View {
    let interest: Interest
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 14))
                Text(interest.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CreateProfileView_Previews: PreviewProvider {
    static var previews: some View {
        CreateProfileView(showCreateProfileView: .constant(true), appleUserID: "previewUserID_123")
    }
} 