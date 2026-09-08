import SwiftUI
import Photos
import CloudKit
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
        .task {
            await library.prepare()
        }
    }

    private var photoScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
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

struct ChatPartnerPinnedPhotoStrip: View {
    @ObservedObject var viewModel: GridViewModel
    let deviceID: String
    let onSelect: (Image) -> Void

    @State private var album: Album?

    private let tileHeight: CGFloat = 80

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<Album.maxPhotos, id: \.self) { index in
                slot(at: index)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: tileHeight + 12)
        .onAppear { album = viewModel.userAlbums[deviceID] }
        .onChange(of: viewModel.userAlbums[deviceID]?.photosCount) { _ in
            album = viewModel.userAlbums[deviceID]
        }
        .task(id: deviceID) {
            if let cached = viewModel.userAlbums[deviceID] {
                album = cached
                return
            }
            album = await viewModel.getAlbum(for: deviceID)
        }
    }

    @ViewBuilder
    private func slot(at index: Int) -> some View {
        let asset = album.flatMap { album in
            index < album.pinnedPhotos.count ? album.pinnedPhotos[index] : nil
        }
        ChatPartnerPinTile(asset: asset, onSelect: onSelect)
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
    }
}

private struct ChatPartnerPinTile: View {
    let asset: CKAsset?
    let onSelect: (Image) -> Void
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Button {
            if let image = loader.image {
                onSelect(image)
            }
        } label: {
            Group {
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(asset == nil || loader.image == nil)
        .task(id: asset?.fileURL?.path) {
            if let asset {
                loader.loadImage(from: asset)
            }
        }
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
