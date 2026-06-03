import SwiftUI
import CloudKit

/// Up to three stories the profile owner pinned under their photo (visible on bio/profile).
struct ProfilePinnedStoriesRow: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile

    @State private var album: Album?
    @State private var showingPinPicker = false
    @State private var pinCandidates: [Story] = []
    @State private var pinAlertTitle = ""
    @State private var pinAlertMessage = ""
    @State private var showingPinAlert = false

    private var isOwner: Bool {
        viewModel.currentUserProfile?.deviceID == userProfile.deviceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Stories")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            if let album, !album.photoMetadata.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(album.photoMetadata.enumerated()), id: \.element.id) { index, metadata in
                            if index < album.pinnedPhotos.count {
                                PinnedStoryThumbnail(asset: album.pinnedPhotos[index], caption: metadata.caption) {
                                    if isOwner {
                                        Task { await unpin(storyID: metadata.storyID) }
                                    }
                                }
                            }
                        }

                        if isOwner, album.hasSpace {
                            addPinButton
                        }
                    }
                }
            } else if isOwner {
                HStack(spacing: 10) {
                    Text("Pin up to 3 of your stories for others to see here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    addPinButton
                }
            } else {
                Text("No pinned stories")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .task(id: userProfile.deviceID) {
            album = await viewModel.getAlbum(for: userProfile.deviceID)
        }
        .sheet(isPresented: $showingPinPicker) {
            pinPickerSheet
        }
        .alert(pinAlertTitle, isPresented: $showingPinAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pinAlertMessage)
        }
    }

    private var addPinButton: some View {
        Button {
            Task { await preparePinPicker() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Pin")
                    .font(.caption2)
            }
            .foregroundColor(.blue)
            .frame(width: 60, height: 80)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
        }
        .disabled(!isOwner)
    }

    private var pinPickerSheet: some View {
        NavigationView {
            List {
                if pinCandidates.isEmpty {
                    Text("Post a story first, then pin it here.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(pinCandidates) { story in
                        Button {
                            Task {
                                await pin(story: story)
                                showingPinPicker = false
                            }
                        } label: {
                            HStack {
                                Text(story.caption?.isEmpty == false ? story.caption! : "Story")
                                Spacer()
                                Text(story.timestamp, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pin a Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { showingPinPicker = false }
                }
            }
        }
    }

    private func preparePinPicker() async {
        guard let deviceID = viewModel.currentUserProfile?.deviceID else { return }
        await viewModel.storiesService.refreshStories()
        let pinnedIDs = Set(album?.photoMetadata.map(\.storyID) ?? [])
        pinCandidates = viewModel.storiesService.allActiveStories
            .filter { $0.deviceID == deviceID && $0.isValid && !pinnedIDs.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
        showingPinPicker = true
    }

    private func pin(story: Story) async {
        let result = await viewModel.pinStoryToAlbum(story)
        await MainActor.run {
            if result.success {
                pinAlertTitle = "Pinned"
                pinAlertMessage = "Story added to your profile."
            } else {
                pinAlertTitle = "Could not pin"
                pinAlertMessage = result.error ?? "Try again."
            }
            showingPinAlert = true
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
        self.album = await viewModel.getAlbum(for: userProfile.deviceID)
    }
}

private struct PinnedStoryThumbnail: View {
    let asset: CKAsset
    let caption: String?
    let onTap: () -> Void

    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(width: 60, height: 80)
            .clipped()
            .cornerRadius(8)
            .onTapGesture(perform: onTap)

            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(4)
                .background(Circle().fill(Color.blue))
                .padding(4)
        }
        .onAppear { loader.loadImage(from: asset) }
    }
}
