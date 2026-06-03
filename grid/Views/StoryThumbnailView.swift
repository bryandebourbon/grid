import SwiftUI

struct StoryThumbnailView: View {
    let story: Story
    let isSelected: Bool
    let onTapped: () -> Void

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

            if let caption = story.caption, !caption.isEmpty {
                VStack {
                    Spacer()
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
        .onAppear {
            thumbnailImageLoader.loadImage(from: story.imageAsset)
        }
    }
}
