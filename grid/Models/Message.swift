import Foundation
import CloudKit

struct Message: Identifiable, Codable {
    var id: String // Unique identifier for the message (e.g., UUID().uuidString)
    var recordID: CKRecord.ID? // CloudKit record ID
    let senderDeviceID: String // Device ID of the sender
    let recipientDeviceID: String // Device ID of the recipient (can be the same as senderDeviceID for self-messaging)
    let senderUserID: String // Apple User ID of the sender (for account-level tracking)
    let recipientUserID: String // Apple User ID of the recipient
    let text: String
    let timestamp: Date
    var isRead: Bool = false // To track if the message has been read by the recipient

    enum CodingKeys: String, CodingKey {
        case id
        case senderDeviceID
        case recipientDeviceID
        case senderUserID
        case recipientUserID
        case text
        case timestamp
        case isRead
        // recordID is not directly encoded/decoded as it's managed by CloudKit interactions
    }

    // Initializer for creating a new message locally
    init(id: String = UUID().uuidString, 
         senderDeviceID: String, 
         recipientDeviceID: String, 
         senderUserID: String, 
         recipientUserID: String, 
         text: String, 
         timestamp: Date = Date(), 
         isRead: Bool = false) {
        self.id = id
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        // recordID will be set when saved to or fetched from CloudKit
    }

    // Initializer from a CKRecord
    init?(record: CKRecord) {
        guard let senderDeviceID = record["senderDeviceID"] as? String,
              let recipientDeviceID = record["recipientDeviceID"] as? String,
              let senderUserID = record["senderUserID"] as? String,
              let recipientUserID = record["recipientUserID"] as? String,
              let text = record["text"] as? String,
              let timestamp = record["timestamp"] as? Date else {
            print("Message init from CKRecord failed: Missing required fields.")
            return nil
        }
        
        self.id = record.recordID.recordName // Use CKRecord's name as the Message's primary ID
        self.recordID = record.recordID
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.text = text
        self.timestamp = timestamp
        self.isRead = record["isRead"] as? Bool ?? false
    }

    // Helper to create/update a CKRecord from this message
    func toCKRecord() -> CKRecord {
        let messageRecordID = self.recordID ?? CKRecord.ID(recordName: self.id) // Use existing id for recordName
        let record = CKRecord(recordType: "Messages", recordID: messageRecordID)
        
        record["senderDeviceID"] = self.senderDeviceID
        record["recipientDeviceID"] = self.recipientDeviceID
        record["senderUserID"] = self.senderUserID
        record["recipientUserID"] = self.recipientUserID
        record["text"] = self.text
        record["timestamp"] = self.timestamp
        record["isRead"] = self.isRead
        
        return record
    }
} 