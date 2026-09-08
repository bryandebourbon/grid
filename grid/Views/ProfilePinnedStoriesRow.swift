import SwiftUI
import CloudKit
import PhotosUI

/// Five equal-width pinnable photo slots that span the available width.
struct ProfilePinnedStoriesRow: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    var showsTitle = true
    var photoShape: GridPhotoShape = .card

    @State private var album: Album?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pinAlertTitle = ""
    @State private var pinAlertMessage = ""
    @State private var showingPinAlert = false

    private var isOwner: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }

    private var slotAspect: CGFloat {
        GridCellLayout.widthOverHeight(square: photoShape.usesSquareProportion)
    }

    private let tileHeight: CGFloat = 88
    private let albumCorner: CGFloat = 12

    private var tileWidth: CGFloat {
        tileHeight * slotAspect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTitle {
                Text("Album")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<Album.maxPhotos, id: \.self) { index in
                        slot(at: index)
                            .frame(height: tileHeight)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.28), value: photoShape)
        }
        .task(id: userProfile.deviceID) {
            album = await viewModel.getAlbum(for: userProfile.deviceID)
        }
        .onChange(of: pickerItem) { newItem in
            guard let newItem else { return }
            Task { await pinPickedPhoto(newItem) }
        }
        .alert(pinAlertTitle, isPresented: $showingPinAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pinAlertMessage)
        }
    }

    @ViewBuilder
    private func slot(at index: Int) -> some View {
        let metadata = album.flatMap { album in
            index < album.photoMetadata.count ? album.photoMetadata[index] : nil
        }
        let asset = album.flatMap { album in
            index < album.pinnedPhotos.count ? album.pinnedPhotos[index] : nil
        }

        if let metadata, let asset {
            PinnedStoryThumbnail(
                asset: asset,
                fallbackAspect: slotAspect,
                cornerRadius: albumCorner,
                onRemove: isOwner ? { Task { await unpin(storyID: metadata.storyID) } } : nil
            )
        } else if isOwner {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                emptySlot
            }
            .buttonStyle(.plain)
        } else {
            emptySlot
        }
    }

    private var emptySlot: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if isOwner {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: tileWidth, height: tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: albumCorner, style: .continuous))
    }

    private func pinPickedPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run {
                pinAlertTitle = "Could not pin"
                pinAlertMessage = "Try another photo."
                showingPinAlert = true
            }
            return
        }
        let result = await viewModel.pinPhotoDataToAlbum(data)
        await MainActor.run {
            if !result.success {
                pinAlertTitle = "Could not pin"
                pinAlertMessage = result.error ?? "Try again."
                showingPinAlert = true
            }
        }
        album = await viewModel.getAlbum(for: userProfile.deviceID)
    }

    private func unpin(storyID: String) async {
        let result = await viewModel.unpinStoryIDFromAlbum(storyID)
        await MainActor.run {
            if !result.success {
                pinAlertTitle = "Could not unpin"
                pinAlertMessage = result.error ?? "Try again."
                showingPinAlert = true
            }
        }
        album = await viewModel.getAlbum(for: userProfile.deviceID)
    }
}

private struct PinnedStoryThumbnail: View {
    let asset: CKAsset
    var fallbackAspect: CGFloat = 1
    var cornerRadius: CGFloat = 12
    var onRemove: (() -> Void)? = nil

    @StateObject private var loader = ImageLoader()

    private var photoAspect: CGFloat {
        guard let size = loader.imageSize, size.height > 0 else { return fallbackAspect }
        return size.width / size.height
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFit()
            }

            if onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary.opacity(0.7), Color.white.opacity(0.92))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove photo")
            }
        }
        .aspectRatio(photoAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { loader.loadImage(from: asset) }
        .onChange(of: asset.fileURL) { _ in
            loader.loadImage(from: asset)
        }
    }
}
