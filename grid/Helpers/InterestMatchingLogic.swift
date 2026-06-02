import Foundation

/// Shared-interest helpers used by profile UI and grid filtering.
enum InterestMatchingLogic {

    static func sharedCount(myInterests: [Interest], theirInterests: [Interest]) -> Int {
        Set(myInterests).intersection(Set(theirInterests)).count
    }

    static func sharedInterests(myInterests: [Interest], theirInterests: [Interest]) -> [Interest] {
        Array(Set(myInterests).intersection(Set(theirInterests)))
            .sorted { $0.rawValue < $1.rawValue }
    }
}
