import Foundation

/// Who may appear as a card on the people grid.
enum GridPresenceLogic {
    static func hasPhoto(_ profile: UserProfile?) -> Bool {
        profile?.profileImage != nil
    }

    static func isLeftoverDebugPeer(_ profile: UserProfile) -> Bool {
        let userID = profile.userID.lowercased()
        let deviceID = profile.deviceID.lowercased()
        if userID.hasPrefix("grid.test-peer.") || userID.hasPrefix("grid.uitest.") { return true }
        if deviceID.hasPrefix("grid.test-peer") || deviceID.hasPrefix("uitest-") { return true }
        if profile.deviceName.compare("Test Peer", options: .caseInsensitive) == .orderedSame {
            return true
        }
        if profile.deviceName.localizedCaseInsensitiveContains("UI Test") { return true }
        return (profile.bio ?? "").localizedCaseInsensitiveContains("simulator test peer")
    }

    static func shouldShowPeer(_ profile: UserProfile) -> Bool {
        !isLeftoverDebugPeer(profile)
    }
}
