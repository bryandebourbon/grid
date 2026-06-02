import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct StoryThumbnailView: View {
    let story: Story
    let isSelected: Bool
    let isPinned: Bool
    let isCurrentUser: Bool
    let onTapped: () -> Void
    let onLongPress: (Story) -> Void

    @StateObject private var thumbnailImageLoader = ImageLoader()

    var body: some View {
        ZStack {
            Group {
                if thumbnailImageLoader.isLoading {
                    ProgressView()
                        .frame(width: 60, height: 80)
                } else if let image = thumbnailImageLoader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.gray)
                        )
                }
            }
            .cornerRadius(8)

            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 60, height: 80)
            }

            VStack {
                if isPinned {
                    HStack {
                        Spacer()
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.blue).frame(width: 18, height: 18))
                            .padding(4)
                    }
                }
                Spacer()
                if let caption = story.caption, !caption.isEmpty {
                    HStack {
                        Spacer()
                        Image(systemName: "text.bubble.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 16, height: 16))
                            .padding(4)
                    }
                }
            }
        }
        .onTapGesture { onTapped() }
        .onLongPressGesture {
            guard isCurrentUser else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onLongPress(story)
        }
        .onAppear {
            thumbnailImageLoader.loadImage(from: story.imageAsset)
        }
    }
}
