import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct ConversationsListView: View {
    @ObservedObject var viewModel: GridViewModel
    let onChatSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
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
                        Text("Double tap or long press to view profile")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations, id: \.deviceID) { conversation in
                        ConversationRowView(
                            displayName: conversation.displayName,
                            lastMessage: conversation.lastMessage,
                            messageCount: conversation.messageCount,
                            onTap: {
                                onChatSelected(conversation.deviceID)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct ConversationRowView: View {
    let displayName: String
    let lastMessage: Message?
    let messageCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
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
        }
        .buttonStyle(PlainButtonStyle())
    }
}
