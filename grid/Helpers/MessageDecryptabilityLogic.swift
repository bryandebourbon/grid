import Foundation

/// Old ciphertext from a previous account is another person's data.
/// If this key cannot open it, it does not exist in the UI.
enum MessageDecryptabilityLogic {
    static let failedTextPlaceholder = "[Failed to decrypt message]"

    static func counts(
        isEncrypted: Bool,
        hasEncryptedImage: Bool,
        decryptedText: String?,
        hasDecryptedImage: Bool
    ) -> Bool {
        if hasEncryptedImage {
            return hasDecryptedImage
        }
        if isEncrypted {
            guard let decryptedText else { return false }
            return !isUndecryptableText(decryptedText)
        }
        return true
    }

    static func isUndecryptableText(_ text: String) -> Bool {
        text == failedTextPlaceholder
            || text == MessageBannerLogic.encryptedTextPlaceholder
    }

    static func isReadable(_ message: Message) -> Bool {
        if message.encryptedImageData != nil {
            return decryptedImage(message) != nil
        }
        if message.isEncrypted {
            return counts(
                isEncrypted: true,
                hasEncryptedImage: false,
                decryptedText: decryptedText(message),
                hasDecryptedImage: false
            )
        }
        return true
    }

    static func visible(in messages: [Message]) -> [Message] {
        messages.filter(isReadable)
    }

    static func decryptedText(_ message: Message) -> String? {
        guard message.isEncrypted else { return message.text }
        guard let encoded = message.encryptedContent,
              let data = Data(base64Encoded: encoded),
              let key = CryptoService.shared.getPrivateKey() else {
            return nil
        }
        return CryptoService.shared.decrypt(data: data, withPrivateKey: key)
    }

    static func decryptedImage(_ message: Message) -> Data? {
        guard let encoded = message.encryptedImageData,
              let data = Data(base64Encoded: encoded),
              let key = CryptoService.shared.getPrivateKey() else {
            return nil
        }
        return CryptoService.shared.decryptImage(data: data, withPrivateKey: key)
    }
}
