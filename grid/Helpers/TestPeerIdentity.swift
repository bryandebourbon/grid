import Foundation

/// Debug-only Grid identity so a simulator can message a real phone without
/// Sign in with Apple. Uses a distinct userID so it is not "yourself".
enum TestPeerIdentity {
    static let userIDPrefix = "grid.test-peer."
    static let storedUserIDKey = "grid.testPeerUserID"
    static let debugSenderUserID = "grid.test-peer.debug"
    static let debugSenderDeviceID = "grid.test-peer.debug-DEVICE"

    static var debugSenderProfile: UserProfile {
        UserProfile(
            userID: debugSenderUserID,
            deviceID: debugSenderDeviceID,
            deviceName: "Test Peer"
        )
    }

    static func isTest(_ userID: String) -> Bool {
        userID.hasPrefix(userIDPrefix)
    }

    static func isSimulatorPeer(_ profile: UserProfile) -> Bool {
        isTest(profile.userID)
            || profile.deviceID.hasPrefix("grid.test-peer")
            || (profile.bio ?? "").localizedCaseInsensitiveContains("simulator test peer")
    }

    /// Real accounts should not see simulator debug peers on the grid.
    static func belongsOnRealUserGrid(_ profile: UserProfile, currentUser: UserProfile?) -> Bool {
        guard isSimulatorPeer(profile) else { return true }
        return currentUser.map { isTest($0.userID) } ?? false
    }

    static func userID(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let existing = defaults.string(forKey: storedUserIDKey), isTest(existing) {
            return existing
        }
        let token = DeviceIdentityLogic.peerToken(defaults: defaults, environment: environment)
            ?? String(UUID().uuidString.prefix(8))
        let id = userIDPrefix + token
        defaults.set(id, forKey: storedUserIDKey)
        return id
    }
}
