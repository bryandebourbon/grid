import Foundation

/// Ranks interests by how many nearby people share them.
struct RankedInterest: Identifiable, Equatable {
    var id: String { interest.rawValue }
    let interest: Interest
    let count: Int
}

enum NearbyInterestRanking {
    static func ranked(
        from profiles: [UserProfile],
        excludingDeviceID: String? = nil,
        limit: Int = 10
    ) -> [RankedInterest] {
        var counts: [Interest: Int] = [:]
        for profile in profiles {
            if let excludingDeviceID, profile.deviceID == excludingDeviceID { continue }
            if LocalLLMIdentity.isLLM(profile.deviceID) { continue }
            for interest in Set(profile.interests) {
                counts[interest, default: 0] += 1
            }
        }
        let ranked: [RankedInterest] = counts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key.rawValue < $1.key.rawValue
            }
            .prefix(limit)
            .map { RankedInterest(interest: $0.key, count: $0.value) }
        return ranked
    }
}
