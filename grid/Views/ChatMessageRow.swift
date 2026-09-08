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
    var onReact: (String) -> Void = { _ in }
    var isReactionPickerVisible = false
    var onToggleReactionPicker: () -> Void = {}
    @StateObject private var imageLoader = ImageLoader()
    @EnvironmentObject var viewModel: GridViewModel

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
                Spacer()
            }

            VStack(alignment: isCurrentDeviceSender ? .trailing : .leading, spacing: 4) {
                ZStack(alignment: isCurrentDeviceSender ? .topTrailing : .topLeading) {
                    bubble
                        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 48) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onToggleReactionPicker()
                        }

                    if isReactionPickerVisible {
                        MessageReactionPicker { emoji in
                            onReact(emoji)
                            onToggleReactionPicker()
                        }
                        .offset(y: -46)
                    }

                    MessageReactionChips(
                        reactions: message.reactions,
                        currentDeviceID: viewModel.currentUserProfile?.deviceID,
                        onToggle: onReact
                    )
                    .offset(y: -10)
                    .padding(.horizontal, 6)
                }
                .padding(.top, isReactionPickerVisible ? 46 : (message.reactions.isEmpty ? 0 : 10))

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)

                    if isCurrentDeviceSender {
                        switch message.status {
                        case .sending:
                            Text("Sending...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        case .failed:
                            Text("Failed")
                                .font(.caption2)
                                .foregroundColor(.red)
                        case .sent, .received:
                            EmptyView()
                        }
                    }
                }
            }

            if !isCurrentDeviceSender {
                Spacer()
            }
        }
        .id(message.id)
        .onAppear {
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
        .onChange(of: message.imageAsset?.fileURL) { _ in
            if let asset = message.imageAsset {
                imageLoader.loadImage(from: asset)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if let imageAsset = message.imageAsset {
            if imageLoader.isLoading {
                ProgressView()
                    .frame(width: 150, height: 150)
            } else if let loadedImage = imageLoader.image {
                loadedImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(10)
                    .onTapGesture {
                        onImageTap(FullScreenImageData(image: loadedImage, isEncrypted: message.isEncrypted))
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 100)
                    .cornerRadius(10)
                    .overlay(Text("Error loading image").font(.caption))
            }
        } else if message.isEncrypted && message.encryptedImageData != nil {
            encryptedImageBubble
        } else if !displayText.isEmpty {
            Text(displayText)
                .padding(10)
                .background(isCurrentDeviceSender ? Color.blue.opacity(0.7) : Color.gray.opacity(0.3))
                .foregroundColor(isCurrentDeviceSender ? .white : .primary)
                .cornerRadius(10)
                .opacity(message.status == .sending ? 0.7 : 1.0)
                .accessibilityIdentifier(GridUITestHarness.chatMessageIdentifier)
                .accessibilityValue(displayText)
        } else {
            Text("[Empty Message]")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private var encryptedImageBubble: some View {
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
    }
}
