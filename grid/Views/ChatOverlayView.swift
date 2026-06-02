import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ChatOverlayView: View {
    @ObservedObject var viewModel: GridViewModel
    let recipientDeviceID: String
    let onClose: () -> Void
    
    // Helper to get recipient display name
    private func recipientDisplayName() -> String {
        if recipientDeviceID == viewModel.currentUserProfile?.deviceID {
            return "My Notes"
        }
        
        // Find the recipient's profile to get their display name
        for row in viewModel.gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                    return profile.deviceName ?? "User"
                }
            }
        }
        return "Chat"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(recipientDisplayName())
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if recipientDeviceID != viewModel.currentUserProfile?.deviceID {
                        if let distanceString = viewModel.getDistanceString(to: recipientDeviceID) {
                            Text(distanceString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Menu button
                Menu {
                    if recipientDeviceID != viewModel.currentUserProfile?.deviceID {
                        Button(action: {
                            // Find the recipient's profile
                            for row in viewModel.gridNodes {
                                for node in row {
                                    if let profile = node.userProfile, profile.deviceID == recipientDeviceID {
                                        onClose()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            viewModel.selectedUserProfileForReport = ProfileCardUser(id: recipientDeviceID, userProfile: profile)
                                        }
                                        return
                                    }
                                }
                            }
                        }) {
                            Label("Report User", systemImage: "exclamationmark.shield")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            
            // Chat content
            ChatView(viewModel: viewModel, recipientDeviceID: recipientDeviceID)
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .frame(maxWidth: min(400, UIScreen.main.bounds.width - 40))
        .frame(maxHeight: min(600, UIScreen.main.bounds.height - 100))
        .padding(.bottom, 20)
        .onAppear {
            // When the view appears, ensure the viewModel knows which device we're chatting with
            viewModel.selectChatPartner(partnerDeviceID: recipientDeviceID)
            print("ChatOverlayView: Opened chat with \(recipientDeviceID)")
            
            // Mark all messages from this device as read
            viewModel.markMessagesAsRead(from: recipientDeviceID)
        }
    }
}
