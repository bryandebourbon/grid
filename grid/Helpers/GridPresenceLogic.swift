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

    /// Hidden users do not appear as themselves on the grid or map.
    static func showsSelfAvatar(isDiscoverable: Bool, showsSelfOnGrid: Bool) -> Bool {
        isDiscoverable && showsSelfOnGrid
    }
}

enum GridMasterViewerLogic {
    static let unlockPassword = "+ywoyd!"
    static let defaultsKey = "grid.masterViewerUnlocked"

    static func acceptsPassword(_ raw: String?) -> Bool {
        raw == unlockPassword
    }

    static func unlocking(enabled: Bool, password: String?) -> Bool {
        enabled && acceptsPassword(password)
    }

    static func loadEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func storeEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
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
    /// Production CloudKit does not have an `isDiscoverable` field yet.
    /// Visibility is stored on the existing public `interests` list.
    static let visibleToken = "grid.visible"

    /// Missing CloudKit value means hidden.
    static func discoverable(stored: Bool?) -> Bool {
        stored ?? false
    }

    static func discoverable(field: Bool?, interestStrings: [String]) -> Bool {
        if let field { return field }
        return interestStrings.contains(visibleToken)
    }

    static func publicInterestStrings(from interests: [Interest], isDiscoverable: Bool) -> [String] {
        var values = interests.map(\.rawValue).filter { $0 != visibleToken }
        if isDiscoverable {
            values.append(visibleToken)
        }
        return values
    }

    static func interests(from strings: [String]) -> [Interest] {
        strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0 != visibleToken }
            .map { Interest(rawValue: $0) }
    }

    static func shouldAskOnLogin(isNewAccount: Bool) -> Bool {
        false
    }
}
