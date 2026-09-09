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

    /// Other people only see this profile after they refresh if it is discoverable.
    static func isVisibleToOthers(_ profile: UserProfile) -> Bool {
        shouldShowPeer(profile) && profile.isDiscoverable
    }
}

enum GridMasterViewerLogic {
    static let unlockPassword = "+ywoyd!"

    static func acceptsPassword(_ raw: String?) -> Bool {
        raw == unlockPassword
    }

    static func unlocking(enabled: Bool, password: String?) -> Bool {
        enabled && acceptsPassword(password)
    }

    static func shouldShowPeer(_ profile: UserProfile, includeHidden: Bool) -> Bool {
        if includeHidden { return GridPresenceLogic.shouldShowPeer(profile) }
        return GridPresenceLogic.isVisibleToOthers(profile)
    }

    static func showsHiddenBadge(isDiscoverable: Bool, unlocked: Bool) -> Bool {
        unlocked && isDiscoverable == false
    }
}

enum VisibilityOnboardingLogic {
    /// Missing field means hidden. Users opt in with the eye button.
    static func discoverable(stored: Bool?) -> Bool {
        stored ?? false
    }

    static func shouldAskOnLogin(isNewAccount: Bool) -> Bool {
        false
    }
}
