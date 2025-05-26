import Foundation
import CloudKit

struct ReadReceipt: Identifiable {
    let id: String // Format: "deviceID_messageID" for uniqueness
    let deviceID: String // The device that read the message
    let messageID: String // The message that was read
    let readTimestamp: Date // When the message was read
    var recordID: CKRecord.ID?
    
    init(deviceID: String, messageID: String, readTimestamp: Date = Date()) {
        self.id = "\(deviceID)_\(messageID)"
        self.deviceID = deviceID
        self.messageID = messageID
        self.readTimestamp = readTimestamp
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let deviceID = record["deviceID"] as? String,
              let messageID = record["messageID"] as? String,
              let readTimestamp = record["readTimestamp"] as? Date else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.deviceID = deviceID
        self.messageID = messageID
        self.readTimestamp = readTimestamp
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "ReadReceipts", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["deviceID"] = deviceID
        record["messageID"] = messageID
        record["readTimestamp"] = readTimestamp
        return record
    }
} 