import Foundation

/// Synthetic grid identity for the on-device assistant. Never uploaded to CloudKit.
enum LocalLLMIdentity {
    static let deviceID = "grid.local-llm"
    static let userID = "grid.local-llm"
    static let displayName = "Local LLM"
    static let bio = "On this phone"
    static let enabledDefaultsKey = "grid.localLLM.enabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledDefaultsKey) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }

    static func isLLM(_ deviceID: String) -> Bool {
        deviceID == self.deviceID
    }

    static func involves(_ message: Message) -> Bool {
        isLLM(message.senderDeviceID) || isLLM(message.recipientDeviceID)
    }

    static var profile: UserProfile {
        UserProfile(
            userID: userID,
            deviceID: deviceID,
            deviceName: displayName,
            bio: bio
        )
    }
}

enum LocalLLMMessageStore {
    static let defaultsKey = "grid.localLLM.messages"

    static func load() -> [Message] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    static func save(_ messages: [Message]) {
        let local = messages.filter { LocalLLMIdentity.involves($0) && $0.status != .sending }
        guard let data = try? JSONEncoder().encode(local) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
