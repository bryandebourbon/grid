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
}
