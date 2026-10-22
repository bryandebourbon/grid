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
    var showBioBubbles = false
    @Binding var showingInterestCapPopover: Bool
    var onSearchInterests: () -> Void = {}
    var onDeleteInterest: (Interest) -> Void = { _ in }
    var onChatTapped: (String) -> Void = { _ in }
    var expandedTrailing: AnyView = AnyView(EmptyView())
    var gridContent: AnyView = AnyView(EmptyView())
    var isMapOverlay = false
    var showsOwnProfile = false
    var containerHeight: CGFloat = 1
    var splitFraction: Binding<Double> = .constant(0.5)
    var splitDragOrigin: Binding<Double?> = .constant(nil)
    @State private var dragOffset: CGFloat = 0
    @StateObject private var profileImageLoader = ImageLoader()
    @State private var profilePhotoItem: PhotosPickerItem?
    @State private var bioText = ""
    @State private var nameText = ""
    @State private var interestPendingDelete: Interest?

    /// Interest tabs plus a little room for the first grid row when the drawer is short.
    static let peekHeight: CGFloat = 88

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

    private let expandedHeight: CGFloat = 700
    private let peekCorner: CGFloat = 28

    private var level: InterestDrawerLevel {
        isExpanded ? .expanded : .peek
    }

    var body: some View {
        Group {
            if showsOwnProfile {
                ownProfileSheet
            } else {
                drawer
            }
        }
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
            profileImageLoader.loadImage(from: viewModel.currentUserProfile?.profileImage, force: true)
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

    private var ownProfileSheet: some View {
        NavigationStack {
            ScrollView {
                expandedContent
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isExpanded = false }
                }
            }
        }
    }

    private var drawer: some View {
        VStack(spacing: 0) {
            ZStack {
                if isMapOverlay {
                    handle
                }
                interestIcons
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
            }
            gridContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if isMapOverlay {
                UnevenRoundedRectangle(topLeadingRadius: peekCorner, topTrailingRadius: peekCorner)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(alignment: .top) {
            if isMapOverlay {
                UnevenRoundedRectangle(topLeadingRadius: peekCorner, topTrailingRadius: peekCorner)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: isMapOverlay ? peekCorner : 0, topTrailingRadius: isMapOverlay ? peekCorner : 0))
        .ignoresSafeArea(edges: .bottom)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.primary.opacity(0.28))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("Map height")
            .accessibilityIdentifier("grid.map.split")
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if splitDragOrigin.wrappedValue == nil {
                            splitDragOrigin.wrappedValue = splitFraction.wrappedValue
                        }
                        guard let origin = splitDragOrigin.wrappedValue, containerHeight > 0 else { return }
                        let next = origin + Double(value.translation.height / containerHeight)
                        let clamped = min(0.72, max(0.18, next))
                        guard abs(clamped - splitFraction.wrappedValue) > 0.0005 else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            splitFraction.wrappedValue = clamped
                        }
                    }
                    .onEnded { _ in
                        splitDragOrigin.wrappedValue = nil
                    }
            )
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

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            if let profile = viewModel.currentUserProfile {
                HStack(alignment: .center, spacing: 12) {
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

                    expandedTrailing
                    Spacer(minLength: 0)
                }

                nameSection

                bioSection

                interestsSection

                ProfilePinnedStoriesRow(
                    viewModel: viewModel,
                    userProfile: profile
                )

                Toggle(isOn: Binding(
                    get: { viewModel.isVisibleOnMap },
                    set: { viewModel.setVisibleOnMap($0) }
                )) {
                    Text("Visible on map")
                        .font(.subheadline)
                }
                .tint(.blue)
                .accessibilityIdentifier("grid.visibility.map")

                Toggle(isOn: Binding(
                    get: { viewModel.isVisibleOnGrid },
                    set: { viewModel.setVisibleOnGrid($0) }
                )) {
                    Text("Visible on grid")
                        .font(.subheadline)
                }
                .tint(.blue)
                .accessibilityIdentifier("grid.visibility.grid")
            } else {
                Text("Loading profile…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomSafeArea + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    private var mainPhotoWidth: CGFloat { 96 }
    private var mainPhotoHeight: CGFloat {
        mainPhotoWidth * GridCellLayout.portraitHeightToWidth
    }

    private var peekPhotoWidth: CGFloat { 28 }
    private var peekPhotoHeight: CGFloat {
        peekPhotoWidth * GridCellLayout.portraitHeightToWidth
    }

    private var mainPhoto: some View {
        profileImage
            .frame(width: mainPhotoWidth, height: mainPhotoHeight)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: GridCellLayout.cornerRadius, style: .continuous))
            .overlay { photoStroke }
    }

    private var profileImage: some View {
        Group {
            if let image = profileImageLoader.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(22)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photoStroke: some View {
        RoundedRectangle(cornerRadius: GridCellLayout.cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
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
                if viewModel.canAddInterestPage {
                    Button {
                        viewModel.showingInterestSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Search interests")
                } else {
                    Text("Delete interest to add a new one")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
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

    private var interestIcons: some View {
        HStack(spacing: 6) {
            peekCircleButton(systemImage: "square.grid.2x2", label: "All", isSelected: viewModel.peopleTab == .all) {
                viewModel.peopleTab = .all
            }
            .accessibilityIdentifier("people.tab.all")

            ForEach(viewModel.interestPages) { interest in
                let selected = isInterestSelected(interest)
                Text(interest.emoji)
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .background(peekChipFill(isSelected: selected), in: Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        viewModel.peopleTab = .interest(interest.rawValue)
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        interestPendingDelete = interest
                    }
                    .accessibilityLabel(interest.rawValue)
                    .accessibilityHint("Press and hold to remove")
                    .accessibilityIdentifier("people.tab.interest.\(interest.rawValue)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }

            if viewModel.canAddInterestPage {
                peekCircleButton(systemImage: "plus", label: "Add interest", isSelected: false) {
                    onSearchInterests()
                }
                .accessibilityIdentifier("people.tab.search")
            }
        }
        .confirmationDialog(
            interestPendingDelete.map { "Remove \($0.rawValue)?" } ?? "Remove interest?",
            isPresented: Binding(
                get: { interestPendingDelete != nil },
                set: { if !$0 { interestPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let interest = interestPendingDelete else { return }
                interestPendingDelete = nil
                onDeleteInterest(interest)
            }
            Button("Keep", role: .cancel) {}
        } message: {
            if let interest = interestPendingDelete {
                Text("You’ll leave \(interest.rawValue) and this page will close. People looking for \(interest.rawValue) won’t see you here.")
            }
        }
    }

    private func isInterestSelected(_ interest: Interest) -> Bool {
        guard case .interest(let raw) = viewModel.peopleTab else { return false }
        return raw.compare(interest.rawValue, options: .caseInsensitive) == .orderedSame
    }

    private func peekChipFill(isSelected: Bool) -> Color {
        Color.primary.opacity(isSelected ? 0.18 : 0.08)
    }

    private func peekCircleButton(
        systemImage: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 32, height: 32)
                .background(peekChipFill(isSelected: isSelected), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var profileAvatar: some View {
        profileImage
            .frame(width: peekPhotoWidth, height: peekPhotoHeight)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
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
