import Foundation
import CoreLocation

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

    /// Other people only see this profile on the grid when that surface is on.
    static func isVisibleToOthers(_ profile: UserProfile) -> Bool {
        shouldShowPeer(profile) && profile.isVisibleOnGrid
    }

    /// Other people only see this profile on the map when that surface is on.
    static func isVisibleOnMapToOthers(_ profile: UserProfile) -> Bool {
        shouldShowPeer(profile) && profile.isVisibleOnMap
    }

    /// Hidden users do not appear as themselves on the grid or map.
    static func showsSelfAvatar(isDiscoverable: Bool, showsSelfOnGrid: Bool) -> Bool {
        isDiscoverable && showsSelfOnGrid
    }
}

/// All is a 25-cell grid. Missing GPS used to sort last, so a brand-new account never appeared.
enum NearbyProfileSortLogic {
    static let recentActivity: TimeInterval = 24 * 60 * 60

    static func sorted(
        _ profiles: [UserProfile],
        from location: CLLocation?,
        now: Date = Date()
    ) -> [UserProfile] {
        profiles.sorted { lhs, rhs in
            let left = rankDistance(lhs, from: location, now: now)
            let right = rankDistance(rhs, from: location, now: now)
            if left != right { return left < right }
            return lhs.lastActiveTimestamp > rhs.lastActiveTimestamp
        }
    }

    static func rankDistance(
        _ profile: UserProfile,
        from location: CLLocation?,
        now: Date = Date()
    ) -> CLLocationDistance {
        if let location, let theirs = profile.location {
            return location.distance(from: theirs)
        }
        if now.timeIntervalSince(profile.lastActiveTimestamp) < recentActivity {
            return 0
        }
        return .greatestFiniteMagnitude
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

    static func shouldShowOnMap(_ profile: UserProfile, includeHidden: Bool) -> Bool {
        if includeHidden { return GridPresenceLogic.shouldShowPeer(profile) }
        return GridPresenceLogic.isVisibleOnMapToOthers(profile)
    }

    static func showsHiddenBadge(isDiscoverable: Bool, unlocked: Bool) -> Bool {
        unlocked && isDiscoverable == false
    }
}

enum VisibilityOnboardingLogic {
    /// Production CloudKit does not have an `isDiscoverable` field yet.
    /// Visibility is stored on the existing public `interests` list.
    static let visibleToken = "grid.visible"
    static let mapToken = "grid.visible.map"
    static let gridToken = "grid.visible.grid"

    /// Missing CloudKit value means hidden.
    static func discoverable(stored: Bool?) -> Bool {
        stored ?? false
    }

    static func discoverable(field: Bool?, interestStrings: [String]) -> Bool {
        if let field { return field }
        return interestStrings.contains(visibleToken)
    }

    static func surfaceVisible(
        field: Bool?,
        token: String,
        interestStrings: [String],
        legacy: Bool
    ) -> Bool {
        if let field { return field }
        if interestStrings.contains(token) { return true }
        let hasSpecificSurface = interestStrings.contains(mapToken) || interestStrings.contains(gridToken)
        if hasSpecificSurface { return false }
        return legacy
    }

    static func publicInterestStrings(
        from interests: [Interest],
        isVisibleOnMap: Bool,
        isVisibleOnGrid: Bool
    ) -> [String] {
        var values = interests.map(\.rawValue).filter {
            $0 != visibleToken && $0 != mapToken && $0 != gridToken
        }
        if isVisibleOnMap { values.append(mapToken) }
        if isVisibleOnGrid { values.append(gridToken) }
        if isVisibleOnMap || isVisibleOnGrid {
            values.append(visibleToken)
        }
        return values
    }

    static func interests(from strings: [String]) -> [Interest] {
        strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                $0.isEmpty == false
                    && $0 != visibleToken
                    && $0 != mapToken
                    && $0 != gridToken
            }
            .map { Interest(rawValue: $0) }
    }

    static func shouldAskOnLogin(isNewAccount: Bool) -> Bool {
        false
    }
}

/// Production cannot query `recordName`, so `TRUEPREDICATE` fails.
/// Merge every queryable field and fill gaps by record ID.
enum UserProfileQueryLogic {
    static func fetchPredicates(now: Date = Date()) -> [NSPredicate] {
        _ = now
        return [
            NSPredicate(format: "userID != %@", ""),
            NSPredicate(format: "deviceID != %@", ""),
            NSPredicate(format: "lastActiveTimestamp > %@", Date.distantPast as NSDate)
        ]
    }

    static func isUnqueryableField(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("not marked queryable") || text.contains("not queryable")
    }

    static func missingRecordNames(fetched: [String], known: [String]) -> [String] {
        let have = Set(fetched.filter { $0.isEmpty == false })
        var seen = Set<String>()
        return known.filter { name in
            name.isEmpty == false && have.contains(name) == false && seen.insert(name).inserted
        }
    }

    static func stubDisplayName(from deviceID: String) -> String {
        let trimmed = deviceID.replacingOccurrences(of: "-DEVICE", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? deviceID : trimmed
    }

    static func stubProfile(deviceID: String) -> UserProfile {
        UserProfile(
            userID: "missing.\(deviceID)",
            deviceID: deviceID,
            deviceName: stubDisplayName(from: deviceID),
            isDiscoverable: false
        )
    }

    static func uniqueProfiles(_ profiles: [UserProfile]) -> [UserProfile] {
        var seen = Set<String>()
        return profiles.filter { seen.insert($0.deviceID).inserted }
    }
}
