import SwiftUI
import CloudKit

struct BlockedUsersView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var blockedUserProfiles: [UserProfile] = []
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading blocked users...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if blockedUserProfiles.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Blocked Users")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Users you block will appear here. You can unblock them to see them on the grid again.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // List of blocked users
                    List {
                        ForEach(blockedUserProfiles, id: \.deviceID) { profile in
                            BlockedUserRowView(
                                profile: profile,
                                viewModel: viewModel,
                                onUnblock: {
                                    // Remove from local list immediately for better UX
                                    blockedUserProfiles.removeAll { $0.userID == profile.userID }
                                }
                            )
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                if let error = errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadBlockedUsers()
                    }
                }
            }
            .onAppear {
                loadBlockedUsers()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func loadBlockedUsers() {
        isLoading = true
        errorMessage = nil
        blockedUserProfiles = []
        
        // Get the list of blocked userIDs from the view model
        let blockedUserIDs = Array(viewModel.getBlockedUserIDs())
        
        guard !blockedUserIDs.isEmpty else {
            isLoading = false
            return
        }
        
        // Fetch profiles for blocked users from CloudKit
        let publicDB = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(format: "userID IN %@", blockedUserIDs)
        let query = CKQuery(recordType: "UserProfiles", predicate: predicate)
        
        // Use CKFetchRecordsOperation to properly download assets
        publicDB.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                
                guard let records = records else { return }
                
                // Convert records to UserProfile objects
                blockedUserProfiles = records.compactMap { UserProfile(record: $0) }
                    .sorted { $0.deviceName < $1.deviceName }
            }
        }
    }
}

struct BlockedUserRowView: View {
    let profile: UserProfile
    @ObservedObject var viewModel: GridViewModel
    let onUnblock: () -> Void
    
    @StateObject private var imageLoader = ImageLoader()
    @State private var showingUnblockConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            Group {
                if imageLoader.isLoading {
                    ProgressView()
                        .frame(width: 50, height: 50)
                } else if let image = imageLoader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text("User ID: \(profile.userID.prefix(8))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Unblock button
            Button("Unblock") {
                showingUnblockConfirmation = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
        .alert("Unblock User?", isPresented: $showingUnblockConfirmation) {
            Button("Unblock") {
                print("Unblocking user: \(profile.deviceName) (ID: \(profile.userID))")
                viewModel.unblockUser(userID: profile.userID)
                onUnblock()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to unblock \(profile.deviceName)? They will appear on your grid again and you'll be able to see and message them.")
        }
        .onAppear {
            imageLoader.loadImage(from: profile.profileImage)
        }
    }
} 