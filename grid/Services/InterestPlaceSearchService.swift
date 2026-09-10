import Foundation
import MapKit
import CoreLocation

/// Searches Apple Maps for the selected interest and returns each place as a heatmap hit.
class InterestPlaceSearchService {
    func search(
        interest: String,
        around location: CLLocation,
        radiusMeters: CLLocationDistance = InterestPlaceHeatmapLogic.defaultRadiusMeters,
        completion: @escaping ([InterestPlaceHeatmapLogic.PlaceHit]) -> Void
    ) {
        guard let query = InterestPlaceHeatmapLogic.searchQuery(for: interest) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let radius = InterestPlaceHeatmapLogic.clamped(radiusMeters)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.regionPriority = .required

        MKLocalSearch(request: request).start { response, _ in
            let hits = (response?.mapItems ?? []).enumerated().compactMap { index, item -> InterestPlaceHeatmapLogic.PlaceHit? in
                let coordinate = item.placemark.coordinate
                guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }
                let place = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let hit = InterestPlaceHeatmapLogic.PlaceHit(
                    name: item.name ?? "Place",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    rank: index,
                    distanceMeters: location.distance(from: place)
                )
                return InterestPlaceHeatmapLogic.isInsideRadius(hit, radiusMeters: radius) ? hit : nil
            }
            DispatchQueue.main.async { completion(hits) }
        }
    }
}
