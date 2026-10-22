import CoreLocation
import CoreGraphics

/// One browse radius, driven by how far the grid has been scrolled.
enum BrowseRadiusLogic {
    /// A city block. Scrolling the grid grows this out to the heatmap maximum.
    static let minMeters: CLLocationDistance = 10
    static let maxMeters: CLLocationDistance = InterestPlaceHeatmapLogic.maxRadiusMeters
    /// Downward scroll that carries the radius from the minimum to the maximum.
    static let scrollSpan: CGFloat = 720

    static func meters(forScrollOffset offset: CGFloat) -> CLLocationDistance {
        let traveled = min(max(offset, 0), scrollSpan)
        let progress = Double(traveled / scrollSpan)
        return minMeters + (maxMeters - minMeters) * progress
    }

    /// People with no real fix stay available. A known fix must fall inside the radius.
    static func isWithin(
        _ profile: UserProfile,
        origin: CLLocation?,
        radiusMeters: CLLocationDistance
    ) -> Bool {
        guard let origin, let place = profile.location else { return true }
        if place.coordinate.latitude == 0, place.coordinate.longitude == 0 { return true }
        return origin.distance(from: place) <= radiusMeters
    }
}
