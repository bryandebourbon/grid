import Foundation

/// Shared-interest helpers used by tests and available to profile/grid filtering.
enum InterestMatchingLogic {

    static func sharedCount(myInterests: [Interest], theirInterests: [Interest]) -> Int {
        Set(myInterests).intersection(Set(theirInterests)).count
    }

    static func sharedInterests(myInterests: [Interest], theirInterests: [Interest]) -> [Interest] {
        Array(Set(myInterests).intersection(Set(theirInterests)))
            .sorted { $0.rawValue < $1.rawValue }
    }
}
