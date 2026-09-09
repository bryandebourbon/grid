import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ConversationsListView: View {
    @ObservedObject var viewModel: GridViewModel
    var bottomInset: CGFloat = 0
    var onSelect: (String) -> Void

    var body: some View {
        let tab = viewModel.peopleTab
        let home = viewModel.getMessagesHome()

        List {
            if home.pinned.isEmpty == false {
                Section {
                    PinnedChatsGrid(
                        viewModel: viewModel,
                        people: home.pinned,
                        onSelect: onSelect,
                        onUnpin: { viewModel.removePinInCurrentCategory(deviceID: $0) },
                        onBlock: { viewModel.blockConversation(with: $0) },
                        onDelete: { viewModel.hideConversation(with: $0) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            if home.conversations.isEmpty && home.pinned.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "message")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Messages")
                        .font(.title3.weight(.semibold))
                    Text(emptyListDetail(for: tab))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(home.conversations, id: \.deviceID) { conversation in
                    ConversationRowView(
                        viewModel: viewModel,
                        conversation: conversation
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(conversation.deviceID)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.hideConversation(with: conversation.deviceID)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }

                        Button {
                            viewModel.blockConversation(with: conversation.deviceID)
                        } label: {
                            Label("Block", systemImage: "hand.raised.fill")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            viewModel.toggleFavoriteInCurrentCategory(for: conversation.deviceID)
                        } label: {
                            Label(
                                viewModel.isFavoritedInCurrentCategory(conversation.deviceID) ? "Unpin" : "Favorite",
                                systemImage: viewModel.isFavoritedInCurrentCategory(conversation.deviceID) ? "star.slash.fill" : "star.fill"
                            )
                        }
                        .tint(.yellow)
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("grid.messages.list")
    }

    private func emptyListDetail(for tab: GridPeopleTab) -> String {
        switch tab {
        case .all:
            return "Tap someone on the grid to start a chat."
        default:
            return "No chats for this filter."
        }
    }
}

private struct PinnedChatsGrid: View {
    @ObservedObject var viewModel: GridViewModel
    let people: [MessageConversationLogic.PinnedPerson]
    let onSelect: (String) -> Void
    var onUnpin: (String) -> Void = { _ in }
    var onBlock: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }

    private var rows: [[MessageConversationLogic.PinnedPerson]] {
        stride(from: 0, to: people.count, by: 3).map { start in
            Array(people[start..<min(start + 3, people.count)])
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row, id: \.deviceID) { person in
                        PinnedChatCell(
                            viewModel: viewModel,
                            person: person,
                            action: { onSelect(person.deviceID) }
                        )
                        .frame(maxWidth: .infinity)
                        .contextMenu {
                            Button {
                                onUnpin(person.deviceID)
                            } label: {
                                Label("Unpin", systemImage: "star.slash")
                            }
                            Button(role: .destructive) {
                                onBlock(person.deviceID)
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                            Button(role: .destructive) {
                                onDelete(person.deviceID)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { index in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .id("pin-pad-\(index)")
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct PinnedChatCell: View {
    @ObservedObject var viewModel: GridViewModel
    let person: MessageConversationLogic.PinnedPerson
    let action: () -> Void
    @StateObject private var photoLoader = ImageLoader()

    private let avatarSize: CGFloat = 76

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ConversationAvatar(image: photoLoader.image, size: avatarSize)

                    if person.unreadCount > 0 {
                        Text(person.unreadCount > 99 ? "99+" : "\(person.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, person.unreadCount > 9 ? 5 : 6)
                            .padding(.vertical, 3)
                            .background(Color.blue, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }

                Text(person.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 88)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.displayName)
        .onAppear {
            photoLoader.loadImage(from: viewModel.profile(forDeviceID: person.deviceID)?.profileImage)
        }
        .onChange(of: person.deviceID) { _ in
            photoLoader.loadImage(from: viewModel.profile(forDeviceID: person.deviceID)?.profileImage)
        }
    }
}

struct ConversationRowView: View {
    @ObservedObject var viewModel: GridViewModel
    let conversation: MessageConversationLogic.ConversationSummary
    @StateObject private var photoLoader = ImageLoader()

    private var me: String? { viewModel.currentUserProfile?.deviceID }

    private var preview: String {
        guard let message = conversation.lastMessage else { return "No messages yet" }
        let decrypted = viewModel.decryptMessage(message)
        let text = decrypted == MessageBannerLogic.encryptedTextPlaceholder
            || decrypted == MessageBannerLogic.encryptedImagePlaceholder
            || MessageDecryptabilityLogic.isUndecryptableText(decrypted)
            ? nil
            : decrypted
        return MessageConversationLogic.previewLine(
            message: message,
            currentDeviceID: me ?? "",
            partnerName: conversation.displayName,
            decryptedText: text,
            nameForDevice: { viewModel.displayName(forDeviceID: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(conversation.unreadCount > 0 ? Color.blue : Color.clear)
                .frame(width: 10, height: 10)

            ConversationAvatar(image: photoLoader.image, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = conversation.lastMessage?.timestamp {
                        Text(MessageConversationLogic.listTimestamp(date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onAppear {
            photoLoader.loadImage(from: viewModel.profile(forDeviceID: conversation.deviceID)?.profileImage)
        }
        .onChange(of: conversation.deviceID) { _ in
            photoLoader.loadImage(from: viewModel.profile(forDeviceID: conversation.deviceID)?.profileImage)
        }
    }
}

private struct ConversationAvatar: View {
    let image: Image?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.08))
        .clipShape(Circle())
    }
}
