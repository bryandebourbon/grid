import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct ChatRecentPhotoStrip: View {
    @ObservedObject var library: RecentPhotoLibrary
    let onSelect: (Data) -> Void
    var onOpenSettings: (() -> Void)?

    private let tileSize: CGFloat = 80

    var body: some View {
        Group {
            switch library.authorization {
            case .denied, .restricted:
                permissionRow
            default:
                photoScroll
            }
        }
        .frame(height: tileSize + 12)
        .background(Color.clear)
        .task {
            await library.prepare()
        }
    }

    private var photoScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(library.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    RecentPhotoTile(asset: asset, size: tileSize) { data in
                        onSelect(data)
                    }
                    .onAppear {
                        if index >= library.assets.count - 6 {
                            library.loadNextPage()
                        }
                    }
                }

                if library.isLoading {
                    ProgressView()
                        .frame(width: tileSize, height: tileSize)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundColor(.secondary)
            Text("Allow photo access to pick from recent shots.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Settings") {
                onOpenSettings?()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
    }
}

private struct RecentPhotoTile: View {
    let asset: PHAsset
    let size: CGFloat
    let onSelect: (Data) -> Void

    @State private var thumbnail: UIImage?
    @State private var isSending = false

    var body: some View {
        Button {
            Task { await send() }
        } label: {
            ZStack {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray5)
                    }
                }
                .frame(width: size, height: size)
                .clipped()

                if isSending {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(isSending)
        .accessibilityIdentifier("grid.album.item")
        .accessibilityLabel("Recent photo")
        .task {
            thumbnail = await loadThumbnail()
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        if let data = await RecentPhotoLibrary.jpegData(for: asset) {
            onSelect(data)
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var resumed = false
            let scale = UIScreen.main.scale
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: size * scale, height: size * scale),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    resumed = true
                    continuation.resume(returning: image)
                    return
                }
                if !degraded {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
