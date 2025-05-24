import Foundation
import CloudKit

struct UserProfile: Codable {
    var recordID: CKRecord.ID? // CloudKit record ID
    var userID: String // From Sign in with Apple
    var username: String
    // Add other profile fields as needed, e.g.:
    // var bio: String?
    // var profileImage: CKAsset?

    // Coding keys to handle CKRecord.ID manually if needed for Codable
    enum CodingKeys: String, CodingKey {
        case recordNameForCodable = "recordID" // Use a different name to avoid conflict if direct CKRecord.ID was attempted
        case userID
        case username
        // Add other keys
    }

    init(userID: String, username: String) {
        self.userID = userID
        self.username = username
        self.recordID = nil // Or initialize appropriately if needed
    }
    
    // Custom init for Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recordName = try container.decodeIfPresent(String.self, forKey: .recordNameForCodable)
        if let recordName = recordName {
            self.recordID = CKRecord.ID(recordName: recordName)
        } else {
            self.recordID = nil
        }
        self.userID = try container.decode(String.self, forKey: .userID)
        self.username = try container.decode(String.self, forKey: .username)
        // Decode other properties
    }

    // Custom encode for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.recordID?.recordName, forKey: .recordNameForCodable)
        try container.encode(self.userID, forKey: .userID)
        try container.encode(self.username, forKey: .username)
        // Encode other properties
    }

    // Initializer from a CKRecord (when fetching from CloudKit)
    init?(record: CKRecord) {
        guard let userID = record["userID"] as? String,
              let username = record["username"] as? String else {
            return nil
        }
        self.recordID = record.recordID
        self.userID = userID
        self.username = username
    }

    // Helper to create a CKRecord from this profile (for saving to CloudKit)
    func toCKRecord() -> CKRecord {
        let record: CKRecord
        if let existingRecordID = recordID {
            record = CKRecord(recordType: "UserProfiles", recordID: existingRecordID)
        } else {
            // If creating a new record, you might want to use the userID from Apple Sign In as the record name
            // to ensure uniqueness and easy lookup, but be mindful of privacy implications if this ID is guessable.
            // Alternatively, let CloudKit generate a unique ID.
            record = CKRecord(recordType: "UserProfiles") 
        }
        record["userID"] = userID
        record["username"] = username
        // Set other fields for the CKRecord
        return record
    }
} 