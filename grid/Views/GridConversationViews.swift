import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ConversationsListView: View {
    @ObservedObject var viewModel: GridViewModel
    @Environment(\.dismiss) var dismiss
    @State private var path: [String] = []
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let conversations = viewModel.getConversationList()

                if conversations.isEmpty {
                    VStack {
                        Image(systemName: "message.circle")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No conversations yet")
                            .foregroundColor(.gray)
                        Text("Tap on someone in the grid to start chatting!")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text("Long press a square to view a profile")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations, id: \.deviceID) { conversation in
                        Button {
                            ChatOpenTrace.start("list \(conversation.deviceID.prefix(8))")
                            path = [conversation.deviceID]
                            isComposerFocused = true
                        } label: {
                            ConversationRowView(
                                displayName: conversation.displayName,
                                lastMessage: conversation.lastMessage,
                                messageCount: conversation.messageCount
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Label("Close", systemImage: "xmark.circle.fill")
                    }
                }
            }
            .navigationDestination(for: String.self) { deviceID in
                ChatOverlayView(
                    viewModel: viewModel,
                    recipientDeviceID: deviceID,
                    isPresented: true,
                    isComposerFocused: $isComposerFocused,
                    onClose: {
                        isComposerFocused = false
                        KeyboardPresentation.dismissKeyboard()
                        viewModel.deselectChatPartner()
                        if path.isEmpty == false {
                            path.removeLast()
                        }
                    }
                )
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .onChange(of: path) { newPath in
            if newPath.isEmpty {
                isComposerFocused = false
                KeyboardPresentation.dismissKeyboard()
                viewModel.deselectChatPartner()
            }
        }
    }
}

struct ConversationRowView: View {
    let displayName: String
    let lastMessage: Message?
    let messageCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if messageCount > 0 {
                        Text("\(messageCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }

                if let lastMessage = lastMessage {
                    HStack {
                        Text(lastMessage.text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Spacer()

                        Text(lastMessage.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
