import Foundation
import CloudKit

struct UserProfile: Codable {
    var recordID: CKRecord.ID?      // CloudKit record ID (derived from userID)
    var userID: String              // From Sign in with Apple (this is the primary ID and recordName)
    var profileImage: CKAsset?      // For the profile photo (optional)

    enum CodingKeys: String, CodingKey {
        case userID
        // CKAsset (profileImage) is not directly Codable. 
        // It's handled by CKRecord. If UserProfile were part of another Codable type,
        // this would need custom handling or that type would store only userID.
    }

    // Initializer for creating a new profile
    init(userID: String, profileImage: CKAsset? = nil) {
        self.userID = userID
        self.recordID = CKRecord.ID(recordName: userID) 
        self.profileImage = profileImage
    }
    
    // Custom init for Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = try container.decode(String.self, forKey: .userID)
        self.recordID = CKRecord.ID(recordName: self.userID)
        self.profileImage = nil // CKAsset not decoded via Codable
    }

    // Custom encode for Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.userID, forKey: .userID)
        // profileImage (CKAsset) is not encoded.
    }

    // Initializer from a CKRecord
    init?(record: CKRecord) {
        // userID is the recordName of the CKRecord.ID
        let recordName = record.recordID.recordName
        guard !recordName.isEmpty else { // Basic validation for recordName as userID
            print("UserProfile init from CKRecord failed: recordName (userID) is empty.")
            return nil
        }
        self.userID = recordName
        self.recordID = record.recordID
        self.profileImage = record["profileImage"] as? CKAsset
    }

    // Helper to create/update a CKRecord from this profile
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "UserProfiles", recordID: CKRecord.ID(recordName: self.userID))
        // userID is the recordName, so not explicitly stored as a field again.
        // record["userID"] = self.userID // Redundant
        
        if let imageAsset = self.profileImage {
            record["profileImage"] = imageAsset
        } else {
            record["profileImage"] = nil // Or record.removeObject(forKey: "profileImage")
        }
        return record
    }
} 