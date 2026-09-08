import Foundation
import CloudKit
import UserNotifications

/// Posts a local notification that looks like a real messenger: sender + preview.
enum MessageBannerNotifier {
    static let requestPrefix = "grid.msg."
    static let senderDeviceIDKey = "senderDeviceID"
    static let messageIDKey = "messageID"

    static func announce(_ message: Message, currentDeviceID: String? = nil) {
        guard MessageBannerLogic.shouldAnnounce(
            senderDeviceID: message.senderDeviceID,
            currentDeviceID: currentDeviceID,
            viewingDeviceID: ForegroundChatState.partnerDeviceID
        ) else {
            MessageDeliveryTrace.log("banner.skip id=\(message.id.prefix(8)) viewing=\(ForegroundChatState.partnerDeviceID?.prefix(8) ?? "none")")
            return
        }

        let body = MessageBannerLogic.previewText(
            message: message,
            decryptedText: decryptedPreview(for: message)
        )

        if let cached = SenderNameCache.name(for: message.senderDeviceID) {
            post(message: message, title: MessageBannerLogic.title(senderName: cached), body: body)
            return
        }

        CKContainer.default().publicCloudDatabase.fetch(
            withRecordID: CKRecord.ID(recordName: message.senderDeviceID)
        ) { record, _ in
            DispatchQueue.main.async {
                let rawName = record.flatMap { UserProfile(record: $0) }?.deviceName
                if let name = ProfileDisplayNameLogic.personName(from: rawName) {
                    SenderNameCache.store(name, for: message.senderDeviceID)
                }
                post(
                    message: message,
                    title: MessageBannerLogic.title(senderName: rawName),
                    body: body
                )
            }
        }
    }

    static func decryptedPreview(for message: Message) -> String? {
        guard message.isEncrypted else { return message.text }
        guard let encoded = message.encryptedContent,
              let data = Data(base64Encoded: encoded),
              let key = CryptoService.shared.getPrivateKey() else {
            return nil
        }
        return CryptoService.shared.decrypt(data: data, withPrivateKey: key)
    }

    private static func post(message: Message, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = message.senderDeviceID
        content.userInfo = [
            senderDeviceIDKey: message.senderDeviceID,
            messageIDKey: message.id
        ]

        let request = UNNotificationRequest(
            identifier: requestPrefix + message.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        MessageDeliveryTrace.log("banner.post title=\(title) body=\(body) id=\(message.id.prefix(8))")
    }
}
