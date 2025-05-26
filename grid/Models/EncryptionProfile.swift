import Foundation
import CloudKit

struct EncryptionProfile: Identifiable {
    let id: String // deviceID
    let publicKey: String // Base64 encoded public key
    let isEncryptionEnabled: Bool
    let keyCreatedDate: Date
    var recordID: CKRecord.ID?
    
    init(deviceID: String, publicKey: String, isEncryptionEnabled: Bool = true, keyCreatedDate: Date = Date()) {
        self.id = deviceID
        self.publicKey = publicKey
        self.isEncryptionEnabled = isEncryptionEnabled
        self.keyCreatedDate = keyCreatedDate
        // Use a prefixed recordName to avoid conflicts with UserProfiles records
        self.recordID = CKRecord.ID(recordName: "encryption_\(deviceID)")
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let publicKey = record["publicKey"] as? String,
              let isEncryptionEnabledInt = record["isEncryptionEnabled"] as? Int64,
              let keyCreatedDate = record["keyCreatedDate"] as? Date else {
            return nil
        }
        
        // Extract deviceID from the prefixed recordName
        let recordName = record.recordID.recordName
        self.id = recordName.hasPrefix("encryption_") ? String(recordName.dropFirst(11)) : recordName
        self.publicKey = publicKey
        self.isEncryptionEnabled = isEncryptionEnabledInt == 1  // Convert Int64 to Bool
        self.keyCreatedDate = keyCreatedDate
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "EncryptionProfiles", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["deviceID"] = id
        record["publicKey"] = publicKey
        record["isEncryptionEnabled"] = isEncryptionEnabled ? Int64(1) : Int64(0)  // Convert Bool to Int64
        record["keyCreatedDate"] = keyCreatedDate
        return record
    }
} 