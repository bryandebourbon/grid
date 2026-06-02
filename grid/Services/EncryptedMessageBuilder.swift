import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

/// Builds optimistic encrypted (or fallback) messages before CloudKit send.
enum EncryptedMessageBuilder {

    static func buildTextMessage(
        text: String,
        sender: UserProfile,
        recipientDeviceID: String,
        recipient: UserProfile,
        encryptionProfiles: [String: EncryptionProfile]
    ) -> Message {
        let temporaryID = UUID().uuidString
        var message = Message(
            id: temporaryID,
            senderDeviceID: sender.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: sender.userID,
            recipientUserID: recipient.userID,
            text: text,
            timestamp: Date(),
            status: .sending
        )

        if let profile = encryptionProfile(for: recipientDeviceID, sender: sender, profiles: encryptionProfiles),
           let encrypted = CryptoService.shared.encrypt(text: text, withPublicKey: profile.publicKey) {
            message.isEncrypted = true
            message.encryptedContent = encrypted.base64EncodedString()
            message.encryptionKeyID = profile.id
            message.text = "[Encrypted Message]"
        } else {
            message.isEncrypted = false
        }
        return message
    }

    /// Returns the message and an optional temp file URL to delete after send (unencrypted images only).
    static func buildImageMessage(
        imageData: Data,
        sender: UserProfile,
        recipientDeviceID: String,
        recipient: UserProfile,
        encryptionProfiles: [String: EncryptionProfile]
    ) -> (message: Message, cleanupURL: URL?) {
        let temporaryID = UUID().uuidString
        var processed = compressForEncryption(imageData)

        var message = Message(
            id: temporaryID,
            senderDeviceID: sender.deviceID,
            recipientDeviceID: recipientDeviceID,
            senderUserID: sender.userID,
            recipientUserID: recipient.userID,
            text: "",
            timestamp: Date(),
            status: .sending
        )

        if let profile = encryptionProfile(for: recipientDeviceID, sender: sender, profiles: encryptionProfiles),
           let encrypted = CryptoService.shared.encryptImage(data: processed, withPublicKey: profile.publicKey) {
            let encoded = encrypted.base64EncodedString()
            if encoded.count <= 800 * 1024 {
                message.isEncrypted = true
                message.encryptedImageData = encoded
                message.encryptionKeyID = profile.id
                message.text = "[Encrypted Image]"
                return (message, nil)
            }
        }

        message.isEncrypted = false
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try imageData.write(to: tempURL)
            message.imageAsset = CKAsset(fileURL: tempURL)
            return (message, tempURL)
        } catch {
            return (message, nil)
        }
    }

    static func encryptionProfile(
        for recipientDeviceID: String,
        sender: UserProfile,
        profiles: [String: EncryptionProfile]
    ) -> EncryptionProfile? {
        let key = recipientDeviceID == sender.deviceID ? sender.deviceID : recipientDeviceID
        return profiles[key]
    }

    #if canImport(UIKit)
    static func compressForEncryption(_ imageData: Data) -> Data {
        let maxSize = 400 * 1024
        guard imageData.count > maxSize, let uiImage = UIImage(data: imageData) else { return imageData }
        var quality: CGFloat = 0.8
        while quality > 0.1 {
            if let compressed = uiImage.jpegData(compressionQuality: quality), compressed.count <= maxSize {
                return compressed
            }
            quality -= 0.1
        }
        return imageData
    }
    #else
    static func compressForEncryption(_ imageData: Data) -> Data { imageData }
    #endif
}

enum OptimisticMessageSync {
    static func applySendResult(
        messages: inout [Message],
        temporaryID: String,
        result: Result<Message, Error>
    ) {
        guard let index = messages.firstIndex(where: { $0.id == temporaryID && $0.status == .sending }) else {
            return
        }
        switch result {
        case .success(let saved):
            messages[index].id = saved.id
            messages[index].recordID = saved.recordID
            messages[index].timestamp = saved.timestamp
            messages[index].status = .sent
            messages[index].imageAsset = saved.imageAsset
        case .failure:
            messages[index].status = .failed
        }
        messages.sort { $0.timestamp < $1.timestamp }
    }
}
