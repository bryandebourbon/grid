import Foundation
import CoreLocation
import CloudKit
import Combine

class ProximityService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var activeNearbyProfiles: [UserProfile] = []
    
    // Configuration
    private let maxProximityRadius: Double = 8047 // 5 miles in meters (1 mile = 1609.34 meters)
    private let activeUserTimeLimit: TimeInterval = 300 // 5 minutes to be considered "active"
    
    private var activeUsersRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownLocation: CLLocation? // Store last known location
    
    init() {
        startActiveUsersMonitoring()
    }
    
    deinit {
        stopActiveUsersMonitoring()
    }
    
    // Start monitoring for active nearby users
    private func startActiveUsersMonitoring() {
        // Refresh active users every 30 seconds
        activeUsersRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Use last known location if available
            self.fetchActiveNearbyUsers(currentUserLocation: self.lastKnownLocation)
        }
        
        // Initial fetch
        fetchActiveNearbyUsers(currentUserLocation: lastKnownLocation)
    }
    
    private func stopActiveUsersMonitoring() {
        activeUsersRefreshTimer?.invalidate()
        activeUsersRefreshTimer = nil
    }
    
    // Fetch users who are currently active and nearby
    func fetchActiveNearbyUsers(currentUserLocation: CLLocation? = nil) {
        // Store the location if provided
        if let location = currentUserLocation {
            lastKnownLocation = location
        }
        
        // Use the provided location or the last known location
        let locationToUse = currentUserLocation ?? lastKnownLocation
        
        // Query for recently active users (within last 5 minutes)
        let fiveMinutesAgo = Date().addingTimeInterval(-activeUserTimeLimit)
        let predicate = NSPredicate(format: "lastActiveTimestamp > %@", fiveMinutesAgo as NSDate)
        let query = CKQuery(recordType: "UserProfiles", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "lastActiveTimestamp", ascending: false)]
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    // Handle the "record type not found" error gracefully
                    if error.localizedDescription.contains("Did not find record type") {
                        print("CloudKit schema not initialized yet - UserProfiles record type doesn't exist. This is normal for new apps.")
                        self.activeNearbyProfiles = []
                        return
                    }
                    print("Error fetching active users: \(error.localizedDescription)")
                    return
                }
                
                let allActiveProfiles = records?.compactMap { UserProfile(record: $0) } ?? []
                print("Fetched \(allActiveProfiles.count) recently active users")
                
                // Filter by proximity if we have current location
                if let currentLocation = locationToUse {
                    let nearbyProfiles = allActiveProfiles.filter { profile in
                        guard let profileLocation = profile.location else { return false }
                        let distance = currentLocation.distance(from: profileLocation)
                        return distance <= self.maxProximityRadius
                    }
                    
                    // Sort by distance (closest first)
                    let sortedProfiles = nearbyProfiles.sorted { profile1, profile2 in
                        guard let dist1 = profile1.location?.distance(from: currentLocation),
                              let dist2 = profile2.location?.distance(from: currentLocation) else {
                            return false
                        }
                        return dist1 < dist2
                    }
                    
                    self.activeNearbyProfiles = sortedProfiles
                    print("Found \(sortedProfiles.count) active users within \(self.maxProximityRadius / 1000.0)km")
                } else {
                    // No location available, just show all active users
                    self.activeNearbyProfiles = allActiveProfiles
                    print("No location available, showing all \(allActiveProfiles.count) active users")
                    
                    // Debug: Check if profiles have location data
                    for profile in allActiveProfiles {
                        if let location = profile.location {
                            print("Profile \(profile.deviceName) has location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                        } else {
                            print("Profile \(profile.deviceName) has NO location data")
                        }
                    }
                }
            }
        }
    }
    
    // Update current user's active status and location in CloudKit
    func updateUserActivity(_ profile: UserProfile, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        print("DEBUG: Saving profile to CloudKit - lat: \(profile.latitude ?? 0), lon: \(profile.longitude ?? 0)")
        
        let record = profile.toPublicCKRecord()
        
        // Debug: Check what's in the CloudKit record
        print("DEBUG: CloudKit record latitude: \(record["latitude"] ?? "nil")")
        print("DEBUG: CloudKit record longitude: \(record["longitude"] ?? "nil")")
        
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error updating user activity: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let savedRecord = savedRecords?.first,
                      let updatedProfile = UserProfile(record: savedRecord) else {
                    print("Failed to process updated profile record")
                    completion(.failure(NSError(domain: "ProximityService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process updated profile."])))
                    return
                }
                
                print("Updated user activity for device: \(updatedProfile.deviceName)")
                print("DEBUG: Saved profile lat: \(updatedProfile.latitude ?? 0), lon: \(updatedProfile.longitude ?? 0)")
                completion(.success(updatedProfile))
            }
        }
        
        publicDB.add(modifyOperation)
    }
    
    // Mark user as inactive when app goes to background
    func markUserAsInactive(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: deviceID)
        
        publicDB.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let record = record else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ProximityService", code: -2, userInfo: [NSLocalizedDescriptionKey: "User record not found"])))
                }
                return
            }
            
            // Update the record to mark as inactive
            record["isCurrentlyActive"] = false
            // Keep lastActiveTimestamp as is - shows when they were last active
            
            self.publicDB.save(record) { savedRecord, saveError in
                DispatchQueue.main.async {
                    if let saveError = saveError {
                        completion(.failure(saveError))
                    } else {
                        print("Marked user as inactive: \(deviceID)")
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    // Check if messaging is allowed between two users (based on proximity)
    func canMessage(from currentUser: UserProfile, to targetUser: UserProfile) -> (allowed: Bool, reason: String) {
        // Check if target user is recently active
        guard targetUser.isRecentlyActive() else {
            return (false, "User is not currently active")
        }
        
        // Check proximity
        guard let distance = currentUser.distance(from: targetUser) else {
            return (false, "Location not available")
        }
        
        if distance <= maxProximityRadius {
            let distanceKm = distance / 1000.0
            return (true, "Within range (\(formatDistance(distance)))")
        } else {
            let distanceKm = distance / 1000.0
            return (false, "Too far away (\(formatDistance(distance)))")
        }
    }
    
    // Get formatted distance string in kilometers (.01km to 99km)
    func formatDistance(_ distance: Double) -> String {
        let kilometers = distance / 1000.0 // Convert meters to kilometers
        
        if kilometers < 0.01 {
            return ".01km"  // No leading zero, minimum distance
        } else if kilometers >= 99.0 {
            return "99km"   // Maximum distance, clean format
        } else if kilometers < 1.0 {
            // Format: .05km, .23km, .87km (no leading zero)
            let formatted = String(format: "%.2fkm", kilometers)
            return formatted.replacingOccurrences(of: "0.", with: ".")
        } else {
            return String(format: "%.0fkm", kilometers)  // 1km, 5km, 25km, 99km
        }
    }
} 