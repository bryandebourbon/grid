import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

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
                
                // Action buttons
                HStack(spacing: 16) {
                    // Star button
                    if !isCurrentUser {
                        Button(action: {
                            viewModel.toggleStar(for: userProfile.deviceID)
                        }) {
                            VStack {
                                Image(systemName: viewModel.isStarred(userProfile.deviceID) ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isStarred(userProfile.deviceID) ? .yellow : .gray)
                                Text(viewModel.isStarred(userProfile.deviceID) ? "Starred" : "Star")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Chat button
                    Button(action: onChat) {
                        VStack {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text(isCurrentUser ? "Notes" : "Chat")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    // Block button
                    if !isCurrentUser {
                        Button(action: {
                            viewModel.toggleBlock(for: userProfile.deviceID)
                        }) {
                            VStack {
                                Image(systemName: viewModel.isBlocked(userProfile.deviceID) ? "nosign" : "hand.raised")
                                    .font(.title2)
                                    .foregroundColor(viewModel.isBlocked(userProfile.deviceID) ? .red : .gray)
                                Text(viewModel.isBlocked(userProfile.deviceID) ? "Blocked" : "Block")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Report button
                    if !isCurrentUser {
                        Button(action: {
                            // First close the overlay, then show report dialog
                            onClose()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.selectedUserProfileForReport = ProfileCardUser(id: userProfile.deviceID, userProfile: userProfile)
                            }
                        }) {
                            VStack {
                                Image(systemName: "exclamationmark.shield")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                Text("Report")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
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
