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

enum InterestNearbyKind: String, CaseIterable {
    case places
    case events
    case venues
}

enum InterestVenueQuery {
    static func searchTerm(for interest: Interest, kind: InterestNearbyKind) -> String {
        switch kind {
        case .places, .events:
            return placeSearchTerm(for: interest)
        case .venues:
            return "\(interest.rawValue) venues"
        }
    }

    static func rowTitle(for interest: Interest, kind: InterestNearbyKind) -> String {
        switch kind {
        case .places:
            return placeRowTitle(for: interest)
        case .events:
            return "\(interest.rawValue) events nearby"
        case .venues:
            return "\(interest.rawValue) venues nearby"
        }
    }

    static func searchTerm(for interest: Interest) -> String {
        searchTerm(for: interest, kind: .places)
    }

    static func rowTitle(for interest: Interest) -> String {
        rowTitle(for: interest, kind: .places)
    }

    private static let placeTerms: [Interest: String] = [
        .coffee: "coffee shop",
        .foodie: "restaurant",
        .cooking: "restaurant",
        .wine: "wine bar",
        .fitness: "gym",
        .yoga: "yoga studio",
        .running: "running trail",
        .cycling: "bike shop",
        .hiking: "park",
        .outdoors: "park",
        .swimming: "swimming pool",
        .music: "live music",
        .concerts: "live music",
        .nightlife: "bars nightlife",
        .gay: "gay bars",
        .lgbtq: "gay bars",
        .movies: "movie theater",
        .theater: "theater",
        .comedy: "theater",
        .art: "art gallery",
        .design: "art gallery",
        .photography: "photo walk",
        .books: "bookstore",
        .education: "bookstore",
        .pets: "dog park",
        .gardening: "garden",
        .sports: "sports bar",
        .travel: "tourist attraction",
        .technology: "coworking space",
        .programming: "coworking space",
        .startups: "coworking space",
        .gaming: "game store",
        .fashion: "clothing store",
        .meditation: "meditation",
        .spirituality: "meditation",
        .volunteering: "volunteer",
        .business: "coworking",
        .investing: "coworking",
        .networking: "coworking",
        .languages: "library",
        .writing: "library",
        .dancing: "dance studio"
    ]

    private static func placeSearchTerm(for interest: Interest) -> String {
        placeTerms[interest] ?? interest.rawValue.lowercased()
    }

    private static let placeTitles: [Interest: String] = [
        .gay: "Gay bars nearby",
        .lgbtq: "Gay bars nearby",
        .coffee: "Coffee shops nearby",
        .foodie: "Restaurants nearby",
        .cooking: "Restaurants nearby",
        .wine: "Wine bars nearby",
        .fitness: "Gyms nearby",
        .nightlife: "Bars nearby",
        .music: "Live music nearby",
        .concerts: "Live music nearby"
    ]

    private static func placeRowTitle(for interest: Interest) -> String {
        placeTitles[interest] ?? "\(interest.rawValue) nearby"
    }
}

struct InterestVenue: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let interest: Interest
    var distanceMeters: Double?
    var latitude: Double?
    var longitude: Double?

    var distanceLabel: String {
        guard let distanceMeters else { return "Nearby" }
        if distanceMeters < 1609 {
            return String(format: "%.1f mi", distanceMeters / 1609.34)
        }
        return String(format: "%.0f mi", distanceMeters / 1609.34)
    }

    func withRowKind(_ kind: InterestNearbyKind) -> InterestVenue {
        InterestVenue(
            id: "\(kind.rawValue)-\(id)",
            name: name,
            subtitle: subtitle,
            interest: interest,
            distanceMeters: distanceMeters,
            latitude: latitude,
            longitude: longitude
        )
    }
}
