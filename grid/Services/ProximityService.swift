import Combine
import SwiftUI
import CloudKit
import CoreLocation

class ProximityService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var activeNearbyProfiles: [UserProfile] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownLocation: CLLocation? // Store last known location
    
    init() {
        // No automatic timer - only refresh on demand
    }
    
    // Fetch ALL users and sort by distance - simple and straightforward
    func fetchAllUsers(currentUserLocation: CLLocation? = nil) {
        print("ProximityService: fetchAllUsers called with location: \(currentUserLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0))")
        
        // Store the location if provided
        if let location = currentUserLocation {
            lastKnownLocation = location
        }
        
        // Use the provided location or the last known location
        let locationToUse = currentUserLocation ?? lastKnownLocation
        
        // Query for ALL users using a very old timestamp (effectively gets everyone)
        // Use lastActiveTimestamp which is queryable, with a date from 30 days ago
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        let predicate = NSPredicate(format: "lastActiveTimestamp > %@", thirtyDaysAgo as NSDate)
        let query = CKQuery(recordType: "UserProfiles", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "lastActiveTimestamp", ascending: false)]
        
        print("ProximityService: Executing CloudKit query for UserProfiles with predicate: \(predicate)")
        
        publicDB.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let self = self else { return }
            
            print("ProximityService: CloudKit query completed. Records count: \(records?.count ?? -1), Error: \(error?.localizedDescription ?? "none")")
            
            DispatchQueue.main.async {
                if let error = error {
                    // Handle the "record type not found" error gracefully
                    if error.localizedDescription.contains("Did not find record type") {
                        print("CloudKit schema not initialized yet - UserProfiles record type doesn't exist. This is normal for new apps.")
                        self.activeNearbyProfiles = []
                        return
                    }
                    print("ProximityService: Error fetching users: \(error.localizedDescription)")
                    return
                }
                
                let allProfiles = records?.compactMap { UserProfile(record: $0) } ?? []
                print("ProximityService: Successfully parsed \(allProfiles.count) UserProfile objects from \(records?.count ?? 0) CloudKit records")
                
                // Sort by distance if we have current location
                if let currentLocation = locationToUse {
                    print("ProximityService: Sorting users by distance from current location")
                    let sortedProfiles = allProfiles.sorted { profile1, profile2 in
                        guard let location1 = profile1.location,
                              let location2 = profile2.location else {
                            // Put profiles without location at the end
                            return profile1.location != nil && profile2.location == nil
                        }
                        
                        let dist1 = currentLocation.distance(from: location1)
                        let dist2 = currentLocation.distance(from: location2)
                        return dist1 < dist2
                    }
                    
                    self.activeNearbyProfiles = sortedProfiles
                    print("ProximityService: Sorted \(sortedProfiles.count) users by distance")
                } else {
                    // No location available, just show all users
                    self.activeNearbyProfiles = allProfiles
                    print("ProximityService: No location available, showing all \(allProfiles.count) users")
                }
                
                print("ProximityService: Final activeNearbyProfiles count: \(self.activeNearbyProfiles.count)")
            }
        }
    }
    
    // Keep for backward compatibility - now just calls fetchAllUsers
    func fetchActiveNearbyUsers(currentUserLocation: CLLocation? = nil) {
        fetchAllUsers(currentUserLocation: currentUserLocation)
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
    
    // Simplified - allow messaging anyone you can see
    func canMessage(from currentUser: UserProfile, to targetUser: UserProfile) -> (allowed: Bool, reason: String) {
        // Simple rule: if you can see them, you can message them
        return (true, "Ready to message")
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