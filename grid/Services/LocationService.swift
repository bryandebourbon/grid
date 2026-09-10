import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private var locationUpdateTimer: Timer?
    private var isWalkUpdating = false
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    deinit {
        stopLocationUpdates()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100 // Update every 100 meters (was 10 meters)
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("Location access denied. User needs to enable in Settings.")
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        @unknown default:
            break
        }
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Location permission not granted")
            return
        }
        
        // Instead, just request location once
        locationManager.requestLocation()
        print("Requested location once")
    }
    
    func stopLocationUpdates() {
        isWalkUpdating = false
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        print("Stopped location updates")
    }

    func startWalkUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Location permission not granted")
            return
        }
        guard isWalkUpdating == false else { return }
        isWalkUpdating = true
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 40
        locationManager.startUpdatingLocation()
        print("Started walk location updates")
    }

    func stopWalkUpdates() {
        guard isWalkUpdating else { return }
        isWalkUpdating = false
        locationManager.stopUpdatingLocation()
        print("Stopped walk location updates")
    }
    
    // NEW: Request location just once when needed
    func requestLocationOnce() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Location permission not granted")
            return
        }
        locationManager.requestLocation()
        print("Requesting location once")
    }
    
    // Calculate distance between two locations in meters
    func distance(from location1: CLLocation, to location2: CLLocation) -> Double {
        return location1.distance(from: location2)
    }
    
    // Calculate distance between current location and another location
    func distanceFromCurrent(to location: CLLocation) -> Double? {
        guard let currentLocation = currentLocation else { return nil }
        return distance(from: currentLocation, to: location)
    }
    
    // Check if a location is within a certain radius (in meters)
    func isWithinRadius(_ radius: Double, of location: CLLocation) -> Bool {
        guard let distance = distanceFromCurrent(to: location) else { return false }
        return distance <= radius
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
            print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            if self.isWalkUpdating {
                manager.startUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        if let clError = error as? CLError, clError.code == .locationUnknown {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyAuthorization(manager.authorizationStatus)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        applyAuthorization(status)
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            print("Location authorization status changed: \(status.rawValue)")
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startLocationUpdates()
            case .denied, .restricted:
                self.isWalkUpdating = false
                self.stopLocationUpdates()
            default:
                break
            }
        }
    }
} 