import SwiftUI
import PhotosUI

// Data structure for full-screen image display
struct FullScreenImageData {
    let image: Image
    let isEncrypted: Bool
}

struct MessageRow: View {
    let message: Message
    let isCurrentDeviceSender: Bool
    let onImageTap: (FullScreenImageData) -> Void
    @StateObject private var imageLoader = ImageLoader() // For loading CKAsset images
    @EnvironmentObject var viewModel: GridViewModel // To access decryption
    
    // Decrypt message text if needed
    private var displayText: String {
        if message.isEncrypted {
            return viewModel.decryptMessage(message)
        } else {
            return message.text
        }
    }
    
    var body: some View {
        HStack {
            if isCurrentDeviceSender {
                Spacer() // Push message to the right for sender
            }
            
            VStack(alignment: isCurrentDeviceSender ? .trailing : .leading, spacing: 2) { // Added spacing
                // Encryption indicator
                if message.isEncrypted {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Encrypted")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                if let imageAsset = message.imageAsset {
                    // Display unencrypted image
                    if imageLoader.isLoading {
                        ProgressView()
                            .frame(width: 150, height: 150)
                    } else if let loadedImage = imageLoader.image {
                        loadedImage
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200) // Limit image height
                            .cornerRadius(10)
                            .onTapGesture {
                                onImageTap(FullScreenImageData(image: loadedImage, isEncrypted: message.isEncrypted))
                            }
                    } else {
                        // Placeholder or error for image
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 100)
                            .cornerRadius(10)
                            .overlay(Text("Error loading image").font(.caption))
                    }
                } else if message.isEncrypted && message.encryptedImageData != nil {
                    // Display encrypted image
                    if let decryptedImageData = viewModel.decryptImageMessage(message) {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: decryptedImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .onTapGesture {
                                    onImageTap(FullScreenImageData(image: Image(uiImage: uiImage), isEncrypted: message.isEncrypted))
                                }
                        } else {
                            Rectangle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 150, height: 100)
                                .cornerRadius(10)
                                .overlay(Text("Invalid image data").font(.caption))
                        }
                        #else
                        // macOS support
                        if let nsImage = NSImage(data: decryptedImageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .onTapGesture {
                                    onImageTap(FullScreenImageData(image: Image(nsImage: nsImage), isEncrypted: message.isEncrypted))
                                }
                        } else {
                            Rectangle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 150, height: 100)
                                .cornerRadius(10)
                                .overlay(Text("Invalid image data").font(.caption))
                        }
                        #endif
                    } else {
                        Rectangle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 150, height: 100)
                            .cornerRadius(10)
                            .overlay(Text("Failed to decrypt image").font(.caption))
                    }
                } else if !displayText.isEmpty {
                    // Display text if no image and text is not empty
                    Text(displayText)
                        .padding(10)
                        .background(isCurrentDeviceSender ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                        .foregroundColor(isCurrentDeviceSender ? .white : .primary)
                        .cornerRadius(10)
                        .opacity(message.status == .sending ? 0.7 : 1.0) // Dim if sending
                } else {
                    // Fallback for empty message (should ideally not happen if image or text is required)
                     Text("[Empty Message]")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                HStack(spacing: 4) { // HStack for timestamp and status indicator
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    // Status Indicator
                    if isCurrentDeviceSender { // Only show sending/failed status for messages sent by current user
                        switch message.status {
                        case .sending:
                            Text("Sending...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        case .failed:
                            Text("Failed")
                                .font(.caption2)
                                .foregroundColor(.red)
                        case .sent, .received: // .received shouldn't happen for isCurrentDeviceSender true, but good to be exhaustive
                            EmptyView() // No indicator for sent or received (unless you want a checkmark for sent)
                        }
                    }
                }
            }
            
            if !isCurrentDeviceSender {
                Spacer() // Push message to the left for receiver
            }
        }
        .id(message.id) // Ensure the row is uniquely identifiable for list updates
        .onAppear {
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
        .onChange(of: message.imageAsset?.fileURL) { _ in // Reload if asset URL changes
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
    }
}
