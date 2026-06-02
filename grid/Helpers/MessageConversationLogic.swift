import Foundation

/// Pure conversation grouping/filtering used by `GridViewModel` (no CloudKit).
enum MessageConversationLogic {

    struct ConversationSummary {
        let deviceID: String
        let displayName: String
        let lastMessage: Message?
        let messageCount: Int
    }

    static func messages(
        inConversationWith partnerDeviceID: String,
        currentDeviceID: String,
        from allMessages: [Message]
    ) -> [Message] {
        allMessages.filter { message in
            (message.senderDeviceID == currentDeviceID && message.recipientDeviceID == partnerDeviceID) ||
            (message.senderDeviceID == partnerDeviceID && message.recipientDeviceID == currentDeviceID)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func conversationList(
        currentDeviceID: String,
        messages: [Message],
        displayNameLookup: (String) -> String
    ) -> [ConversationSummary] {
        let grouped = Dictionary(grouping: messages) { message in
            message.senderDeviceID == currentDeviceID ? message.recipientDeviceID : message.senderDeviceID
        }

        return grouped.map { partnerID, thread in
            let sorted = thread.sorted { $0.timestamp < $1.timestamp }
            let name = partnerID == currentDeviceID ? "My Notes" : displayNameLookup(partnerID)
            return ConversationSummary(
                deviceID: partnerID,
                displayName: name,
                lastMessage: sorted.last,
                messageCount: thread.count
            )
        }
        .sorted { lhs, rhs in
            guard let d1 = lhs.lastMessage?.timestamp, let d2 = rhs.lastMessage?.timestamp else {
                return lhs.lastMessage != nil && rhs.lastMessage == nil
            }
            return d1 > d2
        }
    }
}
