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

    static func lastSelfMessage(for deviceID: String, in messages: [Message]) -> Message? {
        messages
            .filter { $0.senderDeviceID == deviceID && $0.recipientDeviceID == deviceID }
            .max { $0.timestamp < $1.timestamp }
    }

    static func conversationList(
        currentDeviceID: String,
        messages: [Message],
        displayNameLookup: (String) -> String
    ) -> [ConversationSummary] {
        let grouped = Dictionary(grouping: messages) { message in
            message.senderDeviceID == currentDeviceID ? message.recipientDeviceID : message.senderDeviceID
        }

        return grouped.compactMap { partnerID, thread -> ConversationSummary? in
            guard partnerID != currentDeviceID else { return nil }
            let sorted = thread.sorted { $0.timestamp < $1.timestamp }
            return ConversationSummary(
                deviceID: partnerID,
                displayName: displayNameLookup(partnerID),
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
