import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ProfileCardView: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    @Environment(\.dismiss) var dismiss
    let onChatTapped: (String) -> Void

    @State private var bioText: String = ""
    @State private var isEditingBio: Bool = false
    @State private var isEditingInterests: Bool = false
    @State private var selectedInterests: Set<Interest> = []

    // Image loaders for main photo
    @StateObject private var mainImageLoader = ImageLoader()
    
    // Photo editing states
    @State private var selectedMainPhotoData: Data? = nil
    @State private var isSavingPhotos = false
    @State private var isEditingPhoto = false

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

                        ProfilePinnedStoriesRow(viewModel: viewModel, userProfile: userProfile)

                        // Main photo editing (only for current user)
                        if isCurrentUserProfile {
                            Button("Edit Photo") {
                                isEditingPhoto = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
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
                                        viewModel.updateUserProfileBioWithModeration(bio: bioText) { success, error in
                                            if success {
                                                print("Bio updated successfully.")
                                            } else {
                                                print("Failed to update bio: \(error ?? "Unknown error")")
                                                // Show error to user - could add an alert here
                                                bioText = viewModel.currentUserProfile?.bio ?? ""
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
                    
                    Divider()
                    
                    // Interests Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Interests")
                                .font(.headline)
                            
                            Spacer()
                            
                            if isCurrentUserProfile {
                                Button(isEditingInterests ? "Done" : "Edit") {
                                    if isEditingInterests {
                                        // Save interests
                                        saveInterests()
                                    } else {
                                        // Start editing
                                        selectedInterests = Set(viewModel.currentUserProfile?.interests ?? [])
                                    }
                                    isEditingInterests.toggle()
                                }
                                .foregroundColor(.blue)
                                .font(.subheadline)
                            }
                        }
                        
                        if isEditingInterests && isCurrentUserProfile {
                            // Interest editing interface
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Select your interests (\(selectedInterests.count) selected)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(Interest.categories) { category in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(category.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                                                ForEach(category.interests) { interest in
                                                    EditableInterestButton(
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
                                .padding(.vertical, 8)
                            }
                        } else {
                            // Display interests
                            let interests = isCurrentUserProfile ? (viewModel.currentUserProfile?.interests ?? []) : userProfile.interests
                            
                            if interests.isEmpty {
                                Text(isCurrentUserProfile ? "No interests selected. Tap Edit to add some." : "No interests listed.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.vertical, 8)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 8) {
                                    ForEach(interests) { interest in
                                        HStack(spacing: 4) {
                                            Text(interest.emoji)
                                                .font(.caption)
                                            Text(interest.rawValue)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
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
                    // Star button
                    if !isCurrentUserProfile {
                        Button(action: {
                            viewModel.toggleStar(for: userProfile.deviceID)
                        }) {
                            Image(systemName: viewModel.isStarred(userProfile.deviceID) ? "star.fill" : "star")
                                .foregroundColor(viewModel.isStarred(userProfile.deviceID) ? .yellow : .primary)
                        }
                    }
                    
                    // Chat Button
                    if !isCurrentUserProfile {
                        Button("Chat") {
                            dismiss()
                            onChatTapped(userProfile.deviceID)
                        }
                    } else {
                        Button("My Notes") {
                            dismiss()
                            onChatTapped(userProfile.deviceID)
                        }
                    }
                    
                    // Block button
                    if !isCurrentUserProfile {
                        Menu {
                            Button(action: {
                                viewModel.toggleBlock(for: userProfile.deviceID)
                            }) {
                                Label(viewModel.isBlocked(userProfile.deviceID) ? "Unblock" : "Block", 
                                      systemImage: viewModel.isBlocked(userProfile.deviceID) ? "nosign" : "hand.raised")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                dismiss()
                                viewModel.selectedUserProfileForReport = ProfileCardUser(id: userProfile.deviceID, userProfile: userProfile)
                            }) {
                                Label("Report User", systemImage: "exclamationmark.shield")
                            }
                            .foregroundColor(.red)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onAppear {
                mainImageLoader.loadImage(from: userProfile.profileImage)
                bioText = isCurrentUserProfile ? (viewModel.currentUserProfile?.bio ?? "") : (userProfile.bio ?? "")
                selectedInterests = Set(isCurrentUserProfile ? (viewModel.currentUserProfile?.interests ?? []) : userProfile.interests)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isEditingPhoto) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Edit Profile Photo")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    CircularPhotoEditor(
                        selectedPhotoData: $selectedMainPhotoData,
                        circleSize: 250,
                        placeholder: "Update Profile Photo",
                        onPhotoChanged: { _ in
                            // Photo was changed, will be saved when user taps Done
                        }
                    )
                    
                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            selectedMainPhotoData = nil
                            isEditingPhoto = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            saveMainPhoto()
                            isEditingPhoto = false
                        }
                        .disabled(selectedMainPhotoData == nil)
                    }
                }
            }
            .onAppear {
                // Initialize with current photo if available
                if let currentImage = userProfile.profileImage,
                   let url = currentImage.fileURL,
                   let data = try? Data(contentsOf: url) {
                    selectedMainPhotoData = data
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleInterest(_ interest: Interest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }
    
    private func saveInterests() {
        viewModel.updateUserProfileInterests(interests: Array(selectedInterests)) { success in
            if success {
                print("Interests updated successfully.")
            } else {
                print("Failed to update interests.")
                // Revert to original interests on failure
                selectedInterests = Set(viewModel.currentUserProfile?.interests ?? [])
            }
        }
    }
    
    // MARK: - Photo Management Functions
    
    private func saveMainPhoto() {
        guard let photoData = selectedMainPhotoData else { return }
        
        isSavingPhotos = true
        
        viewModel.updateCurrentProfileImageWithModeration(newPhotoData: photoData)
        
        // Reload the main image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            mainImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
            selectedMainPhotoData = nil
            isSavingPhotos = false
        }
    }
}
