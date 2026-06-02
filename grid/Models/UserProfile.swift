import Foundation
import CloudKit
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

struct UserProfile: Codable {
    var recordID: CKRecord.ID?      // CloudKit record ID (derived from deviceID)
    var userID: String              // From Sign in with Apple (shared across devices)
    var deviceID: String            // Unique identifier for each device
    var deviceName: String          // Human-readable device name
    var profileImage: CKAsset?      // For the profile photo (optional)
    var bio: String?                // User's biography or about me text
    var interests: [Interest]       // NEW: User's selected interests
    
    // Location and activity tracking
    var latitude: Double?           // Current latitude
    var longitude: Double?          // Current longitude
    var lastActiveTimestamp: Date   // Last time the user was active (app open)
    var isCurrentlyActive: Bool     // Whether the user currently has the app open
    
    // Computed property for CLLocation
    var location: CLLocation? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    enum CodingKeys: String, CodingKey {
        case userID
        case deviceID
        case deviceName
        case latitude
        case longitude  
        case lastActiveTimestamp
        case isCurrentlyActive
        case bio
        case interests
    }

    // Initializer for creating a new profile
    init(userID: String, 
         deviceID: String, 
         deviceName: String, 
         profileImage: CKAsset? = nil,
         bio: String? = nil,
         interests: [Interest] = [],
         latitude: Double? = nil,
         longitude: Double? = nil,
         lastActiveTimestamp: Date = Date(),
         isCurrentlyActive: Bool = true) {
        self.userID = userID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.recordID = CKRecord.ID(recordName: deviceID) // Use deviceID as the unique record identifier
        self.profileImage = profileImage
        self.bio = bio
        self.interests = interests
        self.latitude = latitude
        self.longitude = longitude
        self.lastActiveTimestamp = lastActiveTimestamp
        self.isCurrentlyActive = isCurrentlyActive
    }
    
    // Custom init for Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = try container.decode(String.self, forKey: .userID)
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.recordID = CKRecord.ID(recordName: self.deviceID)
        // CKAssets are not decoded here; they are populated from CKRecord
        self.profileImage = nil
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.interests = try container.decodeIfPresent([Interest].self, forKey: .interests) ?? []
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        self.lastActiveTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastActiveTimestamp) ?? Date()
        self.isCurrentlyActive = try container.decodeIfPresent(Bool.self, forKey: .isCurrentlyActive) ?? false
    }

    // Custom encode for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.userID, forKey: .userID)
        try container.encode(self.deviceID, forKey: .deviceID)
        try container.encode(self.deviceName, forKey: .deviceName)
        try container.encodeIfPresent(self.latitude, forKey: .latitude)
        try container.encodeIfPresent(self.longitude, forKey: .longitude)
        try container.encode(self.lastActiveTimestamp, forKey: .lastActiveTimestamp)
        try container.encode(self.isCurrentlyActive, forKey: .isCurrentlyActive)
        try container.encodeIfPresent(self.bio, forKey: .bio)
        try container.encode(self.interests, forKey: .interests)
    }

    // Initializer from a CKRecord
    init?(record: CKRecord) {
        // deviceID is the recordName of the CKRecord.ID
        let recordName = record.recordID.recordName
        guard !recordName.isEmpty else {
            print("UserProfile init from CKRecord failed: recordName (deviceID) is empty.")
            return nil
        }
        self.deviceID = recordName
        self.recordID = record.recordID
        
        // Extract other fields from the record
        guard let userID = record["userID"] as? String else {
            print("UserProfile init from CKRecord failed: userID is missing.")
            return nil
        }
        self.userID = userID
        self.deviceName = record["deviceName"] as? String ?? "Unknown Device"
        self.profileImage = record["profileImage"] as? CKAsset
        self.latitude = record["latitude"] as? Double
        self.longitude = record["longitude"] as? Double
        self.lastActiveTimestamp = record["lastActiveTimestamp"] as? Date ?? Date()
        self.isCurrentlyActive = record["isCurrentlyActive"] as? Bool ?? false
        self.bio = record["bio"] as? String
        
        // Handle interests from CloudKit - stored as array of strings
        if let interestStrings = record["interests"] as? [String] {
            self.interests = interestStrings.compactMap { Interest(rawValue: $0) }
        } else {
            self.interests = []
        }
    }

    // Helper to create/update a CKRecord for PUBLIC database (grid visibility)
    func toPublicCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "UserProfiles", recordID: CKRecord.ID(recordName: self.deviceID))
        
        record["userID"] = self.userID
        record["deviceID"] = self.deviceID
        record["deviceName"] = self.deviceName
        record["latitude"] = self.latitude
        record["longitude"] = self.longitude
        record["lastActiveTimestamp"] = self.lastActiveTimestamp
        record["isCurrentlyActive"] = self.isCurrentlyActive
        record["bio"] = self.bio
        
        // Store interests as array of strings for CloudKit compatibility
        record["interests"] = self.interests.map { $0.rawValue }
        
        if let imageAsset = self.profileImage {
            record["profileImage"] = imageAsset
        } else {
            record["profileImage"] = nil
        }
        
        return record
    }
    
    // Helper to create/update a CKRecord for PRIVATE database (personal backup)
    func toCKRecord() -> CKRecord {
        return toPublicCKRecord() // Same structure for now
    }
    
    // Display name that shows both device info and user
    var displayName: String {
        return "\(deviceName) (\(userID.prefix(8))...)"
    }
    
    // Display name for grid - shows "Me" if this is the current user's device
    func gridDisplayName(isCurrentUser: Bool) -> String {
        if isCurrentUser {
            return "Me (\(deviceName))"
        } else {
            return displayName
        }
    }
    
    // Update location
    mutating func updateLocation(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.lastActiveTimestamp = Date()
        self.isCurrentlyActive = true
    }
    
    // Mark as active (app is open)
    mutating func markAsActive() {
        self.lastActiveTimestamp = Date()
        self.isCurrentlyActive = true
    }
    
    // Mark as inactive (app closed/backgrounded)
    mutating func markAsInactive() {
        self.isCurrentlyActive = false
        // Note: don't update lastActiveTimestamp here, keep the last known active time
    }
    
    // Check if user is considered "recently active" (within last 5 minutes)
    func isRecentlyActive() -> Bool {
        let fiveMinutesAgo = Date().addingTimeInterval(-300) // 5 minutes
        return lastActiveTimestamp > fiveMinutesAgo
    }
    
    // Calculate distance from another user profile
    func distance(from otherProfile: UserProfile) -> Double? {
        guard let myLocation = self.location,
              let otherLocation = otherProfile.location else {
            return nil
        }
        return myLocation.distance(from: otherLocation)
    }
    
    // NEW: Interest-based compatibility methods
    
    // Calculate shared interests with another user
    func sharedInterests(with otherProfile: UserProfile) -> [Interest] {
        return Set(self.interests).intersection(Set(otherProfile.interests)).sorted { $0.rawValue < $1.rawValue }
    }
    
    // Calculate interest compatibility score (0.0 to 1.0)
    func interestCompatibility(with otherProfile: UserProfile) -> Double {
        let myInterests = Set(self.interests)
        let theirInterests = Set(otherProfile.interests)
        let sharedCount = myInterests.intersection(theirInterests).count
        let totalUniqueCount = myInterests.union(theirInterests).count
        
        guard totalUniqueCount > 0 else { return 0.0 }
        return Double(sharedCount) / Double(totalUniqueCount)
    }
    
    // Check if user has specific interest
    func hasInterest(_ interest: Interest) -> Bool {
        return interests.contains(interest)
    }
    
    // Get top interest categories for display
    var topInterestCategories: [String] {
        let categories = Interest.categories
        var userCategories: [String] = []
        
        for category in categories {
            let hasAnyInCategory = category.interests.contains { interests.contains($0) }
            if hasAnyInCategory {
                userCategories.append(category.name)
            }
        }
        
        return Array(userCategories.prefix(3)) // Return top 3 categories
    }
} 