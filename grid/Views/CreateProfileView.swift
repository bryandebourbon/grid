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

    @State private var selectedPhotoData: Data? = nil // For single main photo
    @State private var selectedInterests: Set<Interest> = [] // NEW: Selected interests
    @State private var personName: String = ProfileDisplayNameLogic.pendingPersonName() ?? ""
    @State private var currentStep: Int = 1 // 1: Name, 2: Photos, 3: Interests, 4: Review
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @FocusState private var nameFieldFocused: Bool

    // Generate device-specific info consistently across build types
    private var deviceID: String {
        return generateConsistentDeviceID(for: appleUserID)
    }

    // Generate a consistent device ID that works across dev builds, TestFlight, and App Store
    private func generateConsistentDeviceID(for userID: String) -> String {
        // Check if we have a stored device ID for this user
        let deviceID = DeviceIdentityLogic.resolvedDeviceID(forAppleUserID: userID)
        print("Generated consistent device ID: \(deviceID) for user: \(userID)")
        return deviceID
    }

    var body: some View {
        NavigationView {
            VStack {
                // Progress indicator
                HStack {
                    ForEach(1...4, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                        if step < 4 {
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
                        nameEntryStep
                    case 2:
                        photoSelectionStep
                    case 3:
                        interestSelectionStep
                    case 4:
                        reviewStep
                    default:
                        nameEntryStep
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
                        if currentStep < 4 {
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
    
    private var nameEntryStep: some View {
        VStack(spacing: 20) {
            Text("What’s your name?")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This is how people see you in chat and notifications.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("Your name", text: $personName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
                .focused($nameFieldFocused)
                .submitLabel(.next)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            nameFieldFocused = true
        }
    }

    // MARK: - Photo Selection Step
    
    private var photoSelectionStep: some View {
        VStack(spacing: 20) {
            Text("Add Your Profile Photo")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Select your main profile photo and position it perfectly")
                .font(.subheadline)
                .foregroundColor(.secondary)

            CircularPhotoEditor(
                selectedPhotoData: $selectedPhotoData,
                circleSize: 200,
                placeholder: "Add Profile Photo",
                onPhotoChanged: { _ in
                    errorMessage = nil
                }
            )
            .padding(.vertical, 20)

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
                if let photoData = selectedPhotoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Name:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(resolvedProfileName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Photo:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(selectedPhotoData != nil ? "1 selected" : "None selected")
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

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var resolvedProfileName: String {
        if let name = ProfileDisplayNameLogic.normalizedPersonName(personName) {
            return name
        }
        if isTestPeer {
            return "Test Peer"
        }
        return personName
    }

    private var stepTitle: String {
        switch currentStep {
        case 1: return "Your Name"
        case 2: return "Add Photo"
        case 3: return "Select Interests"
        case 4: return "Review Profile"
        default: return "Create Profile"
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case 1: return "Next: Photo"
        case 2: return "Next: Interests"
        case 3: return "Next: Review"
        case 4: return isSaving ? "Saving..." : "Create Profile"
        default: return "Next"
        }
    }
    
    private var isTestPeer: Bool {
        TestPeerIdentity.isTest(appleUserID)
    }

    private var isNextButtonDisabled: Bool {
        switch currentStep {
        case 1:
            #if DEBUG
            if isTestPeer { return false }
            #endif
            return !ProfileDisplayNameLogic.isUsablePersonName(personName)
        case 2:
            #if DEBUG
            if isTestPeer { return false }
            #endif
            return selectedPhotoData == nil
        case 3: return selectedInterests.isEmpty
        case 4: return isSaving
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
        var photoData = selectedPhotoData
        #if DEBUG
        if photoData == nil && isTestPeer {
            photoData = ProfileCreationLogic.placeholderPhotoJPEG()
            selectedPhotoData = photoData
        }
        #endif
        guard let photoData else {
            errorMessage = "No photo selected."
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
        let profileName = resolvedProfileName
        guard ProfileDisplayNameLogic.isUsablePersonName(profileName) else {
            errorMessage = "Please enter your name."
            currentStep = 1
            return
        }

        isSaving = true
        errorMessage = nil

        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                guard status == .available else {
                    self.isSaving = false
                    self.errorMessage = ProfileCreationLogic.userFacingCloudKitError(
                        accountStatus: status,
                        saveError: nil
                    )
                    return
                }
                self.writeProfileToCloudKit(photoData: photoData)
            }
        }
    }

    private func writeProfileToCloudKit(photoData: Data) {
        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        do {
            try photoData.write(to: tempFileURL)
        } catch {
            errorMessage = "Could not process photo for saving."
            isSaving = false
            return
        }

        let newProfile = UserProfile(
            userID: appleUserID,
            deviceID: deviceID,
            deviceName: resolvedProfileName,
            profileImage: CKAsset(fileURL: tempFileURL),
            bio: isTestPeer ? "Simulator test peer" : nil,
            interests: Array(selectedInterests)
        )
        let publicRecord = newProfile.toPublicCKRecord()

        CKContainer.default().publicCloudDatabase.save(publicRecord) { _, error in
            try? FileManager.default.removeItem(at: tempFileURL)
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    print("Error saving profile to public CloudKit: \(error.localizedDescription)")
                    self.errorMessage = ProfileCreationLogic.userFacingCloudKitError(
                        accountStatus: .available,
                        saveError: error
                    )
                    return
                }
                print("Profile saved successfully with \(self.selectedInterests.count) interests!")
                ProfileDisplayNameLogic.clearPendingPersonName()
                self.showCreateProfileView = false
            }
        }
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