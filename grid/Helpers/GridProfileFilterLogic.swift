import Foundation

/// Pure profile filtering for grid display (block, interest filters).
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
        blockedUserIDs: Set<String>,
        usersWhoBlockedMe: Set<String>,
        selectedInterestFilter: Set<Interest>
    ) -> [UserProfile] {
        var result = others

        result = result.filter { profile in
            !blockedUserIDs.contains(profile.userID) && !usersWhoBlockedMe.contains(profile.userID)
        }

        if !selectedInterestFilter.isEmpty {
            result = result.filter { profile in
                !Set(profile.interests).intersection(selectedInterestFilter).isEmpty
            }
        }

        return result
    }
}
