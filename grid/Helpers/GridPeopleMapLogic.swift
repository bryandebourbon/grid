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
        let isHidden: Bool

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

    static func pins(from nodes: [[GridNode]], currentDeviceID: String?, includeHidden: Bool = false) -> [Pin] {
        pins(
            fromProfiles: nodes.flatMap { $0 }.compactMap(\.userProfile),
            currentDeviceID: currentDeviceID,
            includeHidden: includeHidden
        )
    }

    static func pins(
        fromProfiles profiles: [UserProfile],
        currentDeviceID: String?,
        includeHidden: Bool = false,
        radiusMeters: CLLocationDistance? = nil,
        origin: CLLocation? = nil
    ) -> [Pin] {
        var seen = Set<String>()
        var pins: [Pin] = []
        for profile in profiles {
            guard isPlottable(profile) else { continue }
            let deviceID = PersonIdentity.id(forDeviceID: profile.deviceID)
            guard deviceID.isEmpty == false, seen.insert(deviceID).inserted else { continue }
            let isCurrentUser = deviceID == currentDeviceID
            if isCurrentUser {
                if profile.isVisibleOnMap == false { continue }
            } else if GridMasterViewerLogic.shouldShowOnMap(profile, includeHidden: includeHidden) == false {
                continue
            }
            if isCurrentUser == false,
               let radiusMeters,
               BrowseRadiusLogic.isWithin(profile, origin: origin, radiusMeters: radiusMeters) == false {
                continue
            }
            pins.append(
                Pin(
                    deviceID: deviceID,
                    name: isCurrentUser ? "Me" : profile.displayName,
                    latitude: profile.latitude ?? 0,
                    longitude: profile.longitude ?? 0,
                    isCurrentUser: isCurrentUser,
                    isHidden: profile.isVisibleOnMap == false
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

    /// Frames the browse circle so a larger radius shows a larger area of the map.
    static func region(around center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) -> MKCoordinateRegion {
        let meters = max(radiusMeters, BrowseRadiusLogic.minMeters)
        let latitudeDelta = (meters / 111_320) * 2.8
        let cosine = max(cos(center.latitude * .pi / 180), 0.2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: latitudeDelta / cosine
            )
        )
    }

    static func region(
        for pins: [Pin],
        blobs: [InterestFootstepLogic.HeatBlob] = [],
        center: CLLocationCoordinate2D? = nil
    ) -> MKCoordinateRegion? {
        let latitudes = pins.map(\.latitude) + blobs.map(\.latitude)
        let longitudes = pins.map(\.longitude) + blobs.map(\.longitude)
        guard latitudes.isEmpty == false, longitudes.isEmpty == false else {
            guard let center else { return nil }
            return region(around: center)
        }
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        let fittedCenter = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latitudeDelta = max((maxLat - minLat) * 1.8, 0.012)
        let longitudeDelta = max((maxLon - minLon) * 1.8, 0.012)
        return MKCoordinateRegion(
            center: fittedCenter,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
