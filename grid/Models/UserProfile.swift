import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

struct UserProfile: Codable {
    var recordID: CKRecord.ID?      // CloudKit record ID (derived from deviceID)
    var userID: String              // From Sign in with Apple (shared across devices)
    var deviceID: String            // Unique identifier for each device
    var deviceName: String          // Human-readable device name
    var profileImage: CKAsset?      // For the profile photo (optional)

    enum CodingKeys: String, CodingKey {
        case userID
        case deviceID
        case deviceName
        // CKAsset (profileImage) is not directly Codable. 
        // It's handled by CKRecord. If UserProfile were part of another Codable type,
        // this would need custom handling or that type would store only userID.
    }

    // Initializer for creating a new profile
    init(userID: String, deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString, deviceName: String = UIDevice.current.name, profileImage: CKAsset? = nil) {
        self.userID = userID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.recordID = CKRecord.ID(recordName: deviceID) // Use deviceID as the unique record identifier
        self.profileImage = profileImage
    }
    
    // Custom init for Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = try container.decode(String.self, forKey: .userID)
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.recordID = CKRecord.ID(recordName: self.deviceID)
        self.profileImage = nil // CKAsset not decoded via Codable
    }

    // Custom encode for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.userID, forKey: .userID)
        try container.encode(self.deviceID, forKey: .deviceID)
        try container.encode(self.deviceName, forKey: .deviceName)
        // profileImage (CKAsset) is not encoded.
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
    }

    // Helper to create/update a CKRecord for PUBLIC database (grid visibility)
    func toPublicCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "UserProfiles", recordID: CKRecord.ID(recordName: self.deviceID))
        
        record["userID"] = self.userID
        record["deviceID"] = self.deviceID
        record["deviceName"] = self.deviceName
        
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
} 