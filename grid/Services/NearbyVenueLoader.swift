import Foundation
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif

struct InterestVenueRow: Identifiable, Equatable {
    var id: String { "\(kind.rawValue)-\(interest.rawValue)" }
    let kind: InterestNearbyKind
    let interest: Interest
    let title: String
    let venues: [InterestVenue]
}

@MainActor
final class NearbyVenueLoader: ObservableObject {
    @Published var rows: [InterestVenueRow] = []
    @Published var venues: [InterestVenue] = []
    @Published var isLoading = false

    func refresh(interest: Interest?, around location: CLLocation?) async {
        guard let interest else {
            rows = []
            venues = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        #if canImport(MapKit)
        if let location, location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
            var built: [InterestVenueRow] = []
            var flat: [InterestVenue] = []
            let placeTerm = InterestVenueQuery.searchTerm(for: interest, kind: .places)
            print("[venues] maps search '\(placeTerm)' for \(interest.rawValue) at \(location.coordinate.latitude), \(location.coordinate.longitude)")
            let places = await search(term: placeTerm, interest: interest, kind: .places, around: location)
            print("[venues] maps found \(places.count) places for \(interest.rawValue)")

            if !places.isEmpty {
                built.append(
                    InterestVenueRow(
                        kind: .events,
                        interest: interest,
                        title: InterestVenueQuery.rowTitle(for: interest, kind: .events),
                        venues: places.map { $0.withRowKind(.events) }
                    )
                )
                flat.append(contentsOf: places)
            }

            let venueTerm = InterestVenueQuery.searchTerm(for: interest, kind: .venues)
            print("[venues] maps search '\(venueTerm)' for \(interest.rawValue) venues")
            let venueBatch = await search(term: venueTerm, interest: interest, kind: .venues, around: location)
            print("[venues] maps found \(venueBatch.count) venues for \(interest.rawValue)")
            if !venueBatch.isEmpty {
                built.append(
                    InterestVenueRow(
                        kind: .venues,
                        interest: interest,
                        title: InterestVenueQuery.rowTitle(for: interest, kind: .venues),
                        venues: venueBatch
                    )
                )
                flat.append(contentsOf: venueBatch)
            }
            if !flat.isEmpty {
                rows = built
                venues = Array(flat.prefix(12))
                return
            }
        } else {
            print("[venues] skipped maps search — no location")
        }
        #endif

        rows = []
        venues = []
    }

    #if canImport(MapKit)
    private func search(
        term: String,
        interest: Interest,
        kind: InterestNearbyKind,
        around location: CLLocation
    ) async -> [InterestVenue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(8).compactMap { item in
                guard let name = item.name else { return nil }
                let itemLocation = item.placemark.location
                let meters = itemLocation.map { location.distance(from: $0) }
                let coordinate = item.placemark.coordinate
                return InterestVenue(
                    id: "\(kind.rawValue)-\(interest.rawValue)-\(name)-\(coordinate.latitude)-\(coordinate.longitude)",
                    name: name,
                    subtitle: item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
                        ?? item.placemark.locality
                        ?? interest.rawValue,
                    interest: interest,
                    distanceMeters: meters,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch {
            print("[venues] maps error for '\(term)': \(error.localizedDescription)")
            return []
        }
    }
    #endif
}
