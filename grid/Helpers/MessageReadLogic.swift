import Foundation

/// Unread message counting for chat badges.
enum MessageReadLogic {

    static func unreadCount(
        from senderDeviceID: String,
        currentDeviceID: String,
        messages: [Message],
        readReceipts: Set<String>
    ) -> Int {
        messages.filter { message in
            message.senderDeviceID == senderDeviceID &&
            message.recipientDeviceID == currentDeviceID &&
            !readReceipts.contains(message.id)
        }.count
    }

    /// Incoming unread across chats, optionally skipping the open thread.
    static func incomingUnreadCount(
        currentDeviceID: String,
        messages: [Message],
        readReceipts: Set<String>,
        excludingSenderDeviceID: String? = nil
    ) -> Int {
        messages.filter { message in
            message.recipientDeviceID == currentDeviceID &&
            !readReceipts.contains(message.id) &&
            message.senderDeviceID != excludingSenderDeviceID
        }.count
    }
}
