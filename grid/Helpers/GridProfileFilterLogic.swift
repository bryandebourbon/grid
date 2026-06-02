import Foundation

/// Pure profile filtering for grid display (starred, block, interest filters).
enum GridProfileFilterLogic {

    static func partition(
        profiles: [UserProfile],
        currentUserDeviceID: String
    ) -> (currentUser: UserProfile?, others: [UserProfile]) {
        var current: UserProfile?
        var others: [UserProfile] = []
        for profile in profiles {
            if profile.deviceID == currentUserDeviceID {
                current = profile
            } else {
                others.append(profile)
            }
        }
        return (current, others)
    }

    static func applyDisplayFilters(
        to others: [UserProfile],
        showingStarredOnly: Bool,
        starredUserIDs: Set<String>,
        blockedUserIDs: Set<String>,
        usersWhoBlockedMe: Set<String>,
        selectedInterestFilter: Set<Interest>,
        isDemoMode: Bool
    ) -> [UserProfile] {
        var result = others

        if showingStarredOnly && !isDemoMode {
            result = result.filter { starredUserIDs.contains($0.userID) }
        }

        if !isDemoMode {
            result = result.filter { profile in
                !blockedUserIDs.contains(profile.userID) && !usersWhoBlockedMe.contains(profile.userID)
            }
        }

        if !selectedInterestFilter.isEmpty {
            result = result.filter { profile in
                !Set(profile.interests).intersection(selectedInterestFilter).isEmpty
            }
        }

        return result
    }
}
