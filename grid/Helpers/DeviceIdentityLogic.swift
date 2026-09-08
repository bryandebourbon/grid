import Foundation

/// Stable per-user device IDs, with an optional peer token so two simulators
/// (or `-GridPeerName Alice`) do not collide when they share one Apple ID.
enum DeviceIdentityLogic {
    static let peerNameDefaultsKey = "GridPeerName"

    static func deviceID(forAppleUserID userID: String, stored: String?, peerToken: String?) -> String {
        if let stored, stored.isEmpty == false { return stored }
        let userSuffix = userID.split(separator: ".").last.map(String.init) ?? "default"
        if let peerToken, peerToken.isEmpty == false {
            return "\(userSuffix)-\(peerToken)-DEVICE"
        }
        return "\(userSuffix)-DEVICE"
    }

    static func storageKey(forAppleUserID userID: String, peerToken: String?) -> String {
        let base = "consistentDeviceID_\(userID)"
        guard let peerToken, peerToken.isEmpty == false else { return base }
        return "\(base)_\(peerToken)"
    }

    static func sanitizedPeerToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `-GridPeerName Alice` wins; otherwise the simulator UDID prefix.
    /// Real devices have neither, so production IDs stay unchanged.
    static func peerToken(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let named = defaults.string(forKey: peerNameDefaultsKey) {
            let token = sanitizedPeerToken(named)
            if token.isEmpty == false { return token }
        }
        if let udid = environment["SIMULATOR_UDID"], udid.isEmpty == false {
            return String(udid.prefix(8))
        }
        return nil
    }

    static func resolvedDeviceID(
        forAppleUserID userID: String,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let token = peerToken(defaults: defaults, environment: environment)
        let key = storageKey(forAppleUserID: userID, peerToken: token)
        let id = deviceID(forAppleUserID: userID, stored: defaults.string(forKey: key), peerToken: token)
        defaults.set(id, forKey: key)
        return id
    }
}
