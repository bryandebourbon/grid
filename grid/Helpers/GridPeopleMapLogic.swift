import Foundation
import CoreLocation
import MapKit

enum GridPeopleMapLogic {
    struct Pin: Identifiable, Equatable {
        let deviceID: String
        let name: String
        let latitude: Double
        let longitude: Double
        let isCurrentUser: Bool

        var id: String { deviceID }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    static func isPlottable(_ profile: UserProfile) -> Bool {
        guard LocalLLMIdentity.isLLM(profile.deviceID) == false else { return false }
        guard let latitude = profile.latitude, let longitude = profile.longitude else { return false }
        return latitude != 0 || longitude != 0
    }

    static func pins(from nodes: [[GridNode]], currentDeviceID: String?) -> [Pin] {
        pins(fromProfiles: nodes.flatMap { $0 }.compactMap(\.userProfile), currentDeviceID: currentDeviceID)
    }

    static func pins(fromProfiles profiles: [UserProfile], currentDeviceID: String?) -> [Pin] {
        var seen = Set<String>()
        var pins: [Pin] = []
        for profile in profiles {
            guard isPlottable(profile) else { continue }
            let deviceID = PersonIdentity.id(forDeviceID: profile.deviceID)
            guard deviceID.isEmpty == false, seen.insert(deviceID).inserted else { continue }
            let isCurrentUser = deviceID == currentDeviceID
            pins.append(
                Pin(
                    deviceID: deviceID,
                    name: isCurrentUser ? "Me" : profile.displayName,
                    latitude: profile.latitude ?? 0,
                    longitude: profile.longitude ?? 0,
                    isCurrentUser: isCurrentUser
                )
            )
        }
        return pins
    }

    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    static func region(around center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    }

    static func region(
        for pins: [Pin]
    ) -> MKCoordinateRegion? {
        if pins.isEmpty {
            return nil
        }
        let latitudes = pins.map(\.latitude)
        let longitudes = pins.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latitudeDelta = max((maxLat - minLat) * 1.8, 0.012)
        let longitudeDelta = max((maxLon - minLon) * 1.8, 0.012)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
