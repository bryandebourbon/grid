import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

enum InterestDrawerLevel {
    case peek
    case expanded
}

/// Bottom drawer with two snap heights: Maps-style peek, or the current user's profile.
struct GridInterestBrowseSection: View {
    @ObservedObject var viewModel: GridViewModel
    @Binding var isExpanded: Bool
    var photoShape: GridPhotoShape = .card
    var showBioBubbles = false
    var onChatTapped: (String) -> Void = { _ in }
    @State private var dragOffset: CGFloat = 0
    @StateObject private var profileImageLoader = ImageLoader()
    @State private var profilePhotoItem: PhotosPickerItem?
    @State private var bioText = ""
    @State private var nameText = ""
    @State private var interestPendingDelete: Interest?

    static let peekHeight: CGFloat = 78

    static func peekHeight(hasSelectedFilters: Bool = false) -> CGFloat {
        peekHeight + bottomSafeArea
    }

    static var bottomSafeArea: CGFloat {
        #if canImport(UIKit)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom
            ?? windows.first?.safeAreaInsets.bottom
            ?? 0
        #else
        return 0
        #endif
    }

    private let expandedHeight: CGFloat = 620
    private let peekCorner: CGFloat = 28

    private var level: InterestDrawerLevel {
        isExpanded ? .expanded : .peek
    }

    var body: some View {
        drawer
            .frame(maxWidth: .infinity)
            .frame(height: currentHeight, alignment: .top)
            .background(drawerMaterial, in: UnevenRoundedRectangle(topLeadingRadius: peekCorner, topTrailingRadius: peekCorner))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: peekCorner, topTrailingRadius: peekCorner)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
            .ignoresSafeArea(edges: .bottom)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isExpanded)
            .onAppear {
                profileImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
                bioText = viewModel.currentUserProfile?.bio ?? ""
                nameText = viewModel.currentUserProfile?.displayName ?? ""
            }
            .onChange(of: viewModel.currentUserProfile?.deviceID) { _ in
                profileImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
                bioText = viewModel.currentUserProfile?.bio ?? ""
                nameText = viewModel.currentUserProfile?.displayName ?? ""
            }
            .onChange(of: viewModel.currentUserProfile?.profileImage?.fileURL) { _ in
                profileImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
            }
            .onChange(of: viewModel.currentUserProfile?.bio) { newBio in
                if !bioIsDirty {
                    bioText = newBio ?? ""
                }
            }
            .onChange(of: viewModel.currentUserProfile?.deviceName) { _ in
                if !nameIsDirty {
                    nameText = viewModel.currentUserProfile?.displayName ?? ""
                }
            }
            .onChange(of: profilePhotoItem) { item in
                guard let item else { return }
                Task { await applyPickedProfilePhoto(item) }
            }
    }

    private var drawerMaterial: Material {
        .ultraThinMaterial
    }

    private var currentPeekHeight: CGFloat {
        Self.peekHeight()
    }

    private var currentHeight: CGFloat {
        let expanded = expandedHeight + Self.bottomSafeArea
        let base = level == .peek ? currentPeekHeight : expanded
        return min(expanded, max(currentPeekHeight, base - dragOffset))
    }

    private var drawer: some View {
        VStack(spacing: 0) {
            handle
                .onTapGesture { toggleLevel() }

            if isExpanded {
                expandedContent
            } else {
                peekContent
                    .onTapGesture { toggleLevel() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.primary.opacity(0.28))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private var peekContent: some View {
        HStack(spacing: 12) {
            profileAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentUserProfile?.displayName ?? "Your profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Swipe up to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            if let profile = viewModel.currentUserProfile {
                PhotosPicker(selection: $profilePhotoItem, matching: .images) {
                    mainPhoto
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    if showBioBubbles, let content = BioStatusBubbleLogic.content(bio: bioText, isMe: true) {
                        BioStatusBubble(text: content.text, isPlaceholder: content.isPlaceholder)
                            .offset(y: 8)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Change profile photo")

                nameSection

                bioSection

                interestsSection

                ProfilePinnedStoriesRow(
                    viewModel: viewModel,
                    userProfile: profile,
                    photoShape: photoShape
                )

                Spacer(minLength: 0)
            } else {
                Text("Loading profile…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomSafeArea + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    private var mainPhotoWidth: CGFloat { 96 }
    private var mainPhotoHeight: CGFloat {
        photoShape == .card ? mainPhotoWidth * GridCellLayout.portraitHeightToWidth : mainPhotoWidth
    }

    private var peekPhotoWidth: CGFloat { photoShape == .card ? 28 : 40 }
    private var peekPhotoHeight: CGFloat {
        photoShape == .card ? peekPhotoWidth * GridCellLayout.portraitHeightToWidth : peekPhotoWidth
    }

    private var mainPhoto: some View {
        profileImage
            .frame(width: mainPhotoWidth, height: mainPhotoHeight)
            .background(Color.primary.opacity(0.08))
            .modifier(DynamicClipShape(useCircular: photoShape.usesCircleClip))
            .overlay { photoStroke }
            .animation(.easeInOut(duration: 0.28), value: photoShape)
    }

    private var profileImage: some View {
        Group {
            if let image = profileImageLoader.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(photoShape == .card ? 22 : 28)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photoStroke: some View {
        if photoShape.usesCircleClip {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        } else {
            RoundedRectangle(cornerRadius: GridCellLayout.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Your name", text: $nameText)
                .font(.subheadline)
                .lineLimit(1)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .onSubmit { saveName() }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                if !nameIsDirty {
                    Spacer()
                } else {
                    Button("Cancel") {
                        nameText = viewModel.currentUserProfile?.displayName ?? ""
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        saveName()
                    }
                    .fontWeight(.semibold)
                    .disabled(!ProfileDisplayNameLogic.isUsablePersonName(nameText))
                }
            }
            .font(.caption)
            .frame(minHeight: 18)
        }
    }

    @ViewBuilder
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Interests")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.showingInterestSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Search interests")
            }

            HStack(spacing: 6) {
                ForEach(0..<InterestPageStore.maxPages, id: \.self) { index in
                    interestSlot(at: index)
                }
            }
            .padding(.top, 6)
        }
        .popover(item: $interestPendingDelete) { interest in
            deleteInterestPopover(interest)
        }
    }

    @ViewBuilder
    private func interestSlot(at index: Int) -> some View {
        let pages = viewModel.interestPages
        if index < pages.count {
            let interest = pages[index]
            ZStack(alignment: .topTrailing) {
                Button {
                    viewModel.peopleTab = .interest(interest.rawValue)
                    isExpanded = false
                } label: {
                    HStack(spacing: 4) {
                        Text(interest.emoji)
                        Text(interest.rawValue)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(interest.rawValue)

                Button {
                    interestPendingDelete = interest
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary.opacity(0.55), Color.primary.opacity(0.08))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -6)
                .accessibilityLabel("Remove \(interest.rawValue)")
            }
        } else {
            Button {
                viewModel.showingInterestSearch = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add interest")
        }
    }

    private func deleteInterestPopover(_ interest: Interest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove \(interest.rawValue)?")
                .font(.headline)
            Text("You’ll leave this interest and this page will close. People looking for \(interest.rawValue) won’t see you here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Keep") {
                    interestPendingDelete = nil
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    let toDelete = interest
                    interestPendingDelete = nil
                    viewModel.unregisterFromInterest(toDelete)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("What's going on?", text: $bioText)
                .font(.subheadline)
                .lineLimit(1)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit { saveBio() }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                if !bioIsDirty {
                    Spacer()
                } else {
                    Button("Cancel") {
                        bioText = viewModel.currentUserProfile?.bio ?? ""
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        saveBio()
                    }
                    .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .frame(minHeight: 18)
        }
    }

    private var nameIsDirty: Bool {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
            != (viewModel.currentUserProfile?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bioIsDirty: Bool {
        bioText.trimmingCharacters(in: .whitespacesAndNewlines)
            != (viewModel.currentUserProfile?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProfileDisplayNameLogic.isUsablePersonName(trimmed) else {
            nameText = viewModel.currentUserProfile?.displayName ?? ""
            return
        }
        viewModel.updatePersonName(trimmed) { success in
            if !success {
                nameText = viewModel.currentUserProfile?.displayName ?? ""
                viewModel.presentUserFacingAlert("Couldn’t save your name. Try again.")
            }
        }
    }

    private func saveBio() {
        viewModel.updateUserProfileBioWithModeration(bio: bioText) { success, error in
            if !success {
                bioText = viewModel.currentUserProfile?.bio ?? ""
                if let error {
                    viewModel.presentUserFacingAlert(error)
                }
            }
        }
    }

    private func applyPickedProfilePhoto(_ item: PhotosPickerItem) async {
        defer { profilePhotoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            viewModel.updateCurrentProfileImageWithModeration(newPhotoData: data)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        await MainActor.run {
            profileImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage)
        }
    }

    private var profileAvatar: some View {
        profileImage
            .frame(width: peekPhotoWidth, height: peekPhotoHeight)
            .background(Color.primary.opacity(0.08))
            .modifier(DynamicClipShape(useCircular: photoShape.usesCircleClip))
            .overlay { photoStroke }
            .animation(.easeInOut(duration: 0.28), value: photoShape)
    }

    private func toggleLevel() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if !isExpanded && (value.translation.height < -40 || predicted < -80) {
                        isExpanded = true
                    } else if isExpanded && (value.translation.height > 40 || predicted > 80) {
                        isExpanded = false
                    }
                    dragOffset = 0
                }
            }
    }
}
