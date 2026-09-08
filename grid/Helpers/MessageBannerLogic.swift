import Foundation

/// Title/body for an incoming-message banner. Decrypt happens on-device;
/// CloudKit never sees the plaintext.
enum MessageBannerLogic {
    static let fallbackTitle = "New Message"
    static let photoBody = "Photo"
    static let genericBody = "Message"
    static let maxPreviewLength = 140

    static let encryptedTextPlaceholder = "[Encrypted Message]"
    static let encryptedImagePlaceholder = "[Encrypted Image]"

    static func title(senderName: String?) -> String {
        ProfileDisplayNameLogic.personName(from: senderName) ?? fallbackTitle
    }

    static func previewText(message: Message, decryptedText: String?) -> String {
        if message.encryptedImageData != nil || message.imageAsset != nil {
            return photoBody
        }
        let raw = (decryptedText ?? message.text).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == encryptedTextPlaceholder || raw == encryptedImagePlaceholder {
            return genericBody
        }
        if raw.count <= maxPreviewLength {
            return raw
        }
        return String(raw.prefix(maxPreviewLength - 1)) + "…"
    }

    static func shouldAnnounce(
        senderDeviceID: String,
        currentDeviceID: String?,
        viewingDeviceID: String?
    ) -> Bool {
        if LocalLLMIdentity.isLLM(senderDeviceID) { return false }
        if let currentDeviceID, senderDeviceID == currentDeviceID { return false }
        if let viewingDeviceID, viewingDeviceID == senderDeviceID { return false }
        return true
    }
}

enum ForegroundChatState {
    static var partnerDeviceID: String?
}

enum SenderNameCache {
    static let defaultsKey = "grid.senderDisplayNames"

    static func name(for deviceID: String, defaults: UserDefaults = .standard) -> String? {
        (defaults.dictionary(forKey: defaultsKey) as? [String: String])?[deviceID]
    }

    static func store(_ name: String, for deviceID: String, defaults: UserDefaults = .standard) {
        guard let trimmed = ProfileDisplayNameLogic.personName(from: name) else { return }
        var map = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        map[deviceID] = trimmed
        defaults.set(map, forKey: defaultsKey)
    }

    static func store(profiles: [UserProfile], defaults: UserDefaults = .standard) {
        for profile in profiles {
            store(profile.deviceName, for: profile.deviceID, defaults: defaults)
        }
    }
}
