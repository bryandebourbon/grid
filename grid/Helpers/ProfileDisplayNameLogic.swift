import Foundation

/// Resolves chat and conversation titles from grid state (no CloudKit).
enum ProfileDisplayNameLogic {
    static let fallbackTitle = "Someone"
    static let pendingNameDefaultsKey = "grid.pendingPersonName"
    static let maxNameLength = 40

    static func chatTitle(
        recipientDeviceID: String,
        currentDeviceID: String?,
        gridNodes: [[GridNode]]
    ) -> String {
        if recipientDeviceID == currentDeviceID {
            return "You"
        }
        if LocalLLMIdentity.isLLM(recipientDeviceID) {
            return LocalLLMIdentity.displayName
        }
        if let profile = profile(forDeviceID: recipientDeviceID, in: gridNodes),
           let name = personName(from: profile.deviceName) {
            return name
        }
        if let cached = SenderNameCache.name(for: recipientDeviceID),
           let name = personName(from: cached) {
            return name
        }
        return fallbackTitle
    }

    static func profile(forDeviceID deviceID: String, in gridNodes: [[GridNode]]) -> UserProfile? {
        for row in gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == deviceID {
                    return profile
                }
            }
        }
        return nil
    }

    static func personName(from raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isUsablePersonName(trimmed) else { return nil }
        return trimmed
    }

    static func isMissingPersonName(_ raw: String?) -> Bool {
        personName(from: raw) == nil
    }

    static func isUsablePersonName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maxNameLength).contains(trimmed.count) else { return false }
        return !looksLikeDeviceName(trimmed)
    }

    static func normalizedPersonName(_ raw: String) -> String? {
        personName(from: raw)
    }

    static func formattedAppleName(givenName: String?, familyName: String?) -> String? {
        let parts = [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return personName(from: parts.joined(separator: " "))
    }

    static func pendingPersonName(defaults: UserDefaults = .standard) -> String? {
        personName(from: defaults.string(forKey: pendingNameDefaultsKey))
    }

    static func storePendingPersonName(_ name: String, defaults: UserDefaults = .standard) {
        guard let name = personName(from: name) else { return }
        defaults.set(name, forKey: pendingNameDefaultsKey)
    }

    static func clearPendingPersonName(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingNameDefaultsKey)
    }

    private static func looksLikeDeviceName(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        let placeholders: Set<String> = [
            "iphone", "ipad", "ipod", "ipod touch", "apple watch",
            "mac", "macbook", "imac", "mac mini", "mac pro",
            "unknown device", "unknown user", "phone"
        ]
        if placeholders.contains(lowered) { return true }
        if lowered.contains("iphone") || lowered.contains("ipad") || lowered.contains("ipod") {
            return true
        }
        if lowered.hasPrefix("device ") { return true }
        return false
    }
}
