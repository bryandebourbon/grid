import Foundation
import CoreLocation

/// Nearby Apple Maps places for an interest, drawn as one heatmap dot each.
enum InterestPlaceHeatmapLogic {
    static let defaultsKey = "grid.heatmapSearchRadiusMeters"
    static let defaultRadiusMeters: CLLocationDistance = 20_000
    static let minRadiusMeters: CLLocationDistance = 1_000
    static let maxRadiusMeters: CLLocationDistance = 50_000
    static let presetKilometers = [1, 5, 10, 20, 50]
    static let minMoveToRefresh: CLLocationDistance = 400

    struct PlaceHit: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
        let rank: Int
        let distanceMeters: Double
    }

    static func searchQuery(for interest: String) -> String? {
        let trimmed = interest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clamped(_ meters: CLLocationDistance) -> CLLocationDistance {
        min(max(meters, minRadiusMeters), maxRadiusMeters)
    }

    static func meters(fromKilometers km: Int) -> CLLocationDistance {
        clamped(CLLocationDistance(km) * 1_000)
    }

    static func kilometers(fromMeters meters: CLLocationDistance) -> Int {
        Int((clamped(meters) / 1_000).rounded())
    }

    static func load(defaults: UserDefaults = .standard) -> CLLocationDistance {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultRadiusMeters }
        return clamped(defaults.double(forKey: defaultsKey))
    }

    static func store(_ meters: CLLocationDistance, defaults: UserDefaults = .standard) {
        defaults.set(clamped(meters), forKey: defaultsKey)
    }

    static func shouldSearch(
        interest: String,
        at location: CLLocation,
        lastInterest: String?,
        lastLocation: CLLocation?
    ) -> Bool {
        guard searchQuery(for: interest) != nil else { return false }
        if lastInterest?.compare(interest, options: .caseInsensitive) != .orderedSame {
            return true
        }
        guard let lastLocation else { return true }
        return location.distance(from: lastLocation) >= minMoveToRefresh
    }

    static func isInsideRadius(_ hit: PlaceHit, radiusMeters: CLLocationDistance) -> Bool {
        hit.distanceMeters <= clamped(radiusMeters)
    }

    static func blobs(
        from hits: [PlaceHit],
        radiusMeters: CLLocationDistance = defaultRadiusMeters
    ) -> [InterestFootstepLogic.HeatBlob] {
        let nearby = hits.filter { isInsideRadius($0, radiusMeters: radiusMeters) }
        let farthest = max(nearby.map(\.distanceMeters).max() ?? 1, 1)
        let count = max(nearby.count, 1)
        return nearby.map { hit in
            let closeness = 1 - min(hit.distanceMeters / farthest, 1)
            let rankScore = 1 - (Double(hit.rank) / Double(count))
            let intensity = 0.4 + 0.6 * (0.65 * closeness + 0.35 * rankScore)
            let cell = InterestFootstepLogic.cellKey(latitude: hit.latitude, longitude: hit.longitude)
            return InterestFootstepLogic.HeatBlob(
                id: "place.\(cell).\(InterestFootstepLogic.slug(hit.name, prefix: 24))",
                latitude: hit.latitude,
                longitude: hit.longitude,
                visitCount: max(1, Int((intensity * 8).rounded())),
                timestamp: Date.distantPast,
                radius: InterestFootstepLogic.minRadius + InterestFootstepLogic.extraRadius * intensity,
                opacity: InterestFootstepLogic.minOpacity + InterestFootstepLogic.extraOpacity * intensity
            )
        }
        .sorted {
            if $0.visitCount == $1.visitCount { return $0.id < $1.id }
            return $0.visitCount > $1.visitCount
        }
    }

    static func merging(
        places: [InterestFootstepLogic.HeatBlob],
        footsteps: [InterestFootstepLogic.HeatBlob]
    ) -> [InterestFootstepLogic.HeatBlob] {
        var seen = Set<String>()
        var merged: [InterestFootstepLogic.HeatBlob] = []
        for blob in places + footsteps {
            guard seen.insert(blob.id).inserted else { continue }
            merged.append(blob)
        }
        return merged.sorted {
            if $0.visitCount == $1.visitCount { return $0.id < $1.id }
            return $0.visitCount > $1.visitCount
        }
    }
}
