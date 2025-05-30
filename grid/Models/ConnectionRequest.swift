import Foundation
import CloudKit

struct ConnectionRequest: Identifiable {
    let id: String // Format: "senderUserID_recipientUserID"
    let senderUserID: String
    let recipientUserID: String
    let senderDeviceID: String
    let recipientDeviceID: String
    let status: ConnectionStatus
    let timestamp: Date
    var recordID: CKRecord.ID?
    
    enum ConnectionStatus: String, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case blocked = "blocked" // If someone blocks after connection
    }
    
    init(senderUserID: String, recipientUserID: String, senderDeviceID: String, recipientDeviceID: String, status: ConnectionStatus = .pending, timestamp: Date = Date()) {
        self.id = "\(senderUserID)_\(recipientUserID)"
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.status = status
        self.timestamp = timestamp
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let senderUserID = record["senderUserID"] as? String,
              let recipientUserID = record["recipientUserID"] as? String,
              let senderDeviceID = record["senderDeviceID"] as? String,
              let recipientDeviceID = record["recipientDeviceID"] as? String,
              let statusRaw = record["status"] as? String,
              let status = ConnectionStatus(rawValue: statusRaw),
              let timestamp = record["timestamp"] as? Date else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.status = status
        self.timestamp = timestamp
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "ConnectionRequests", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["senderUserID"] = senderUserID
        record["recipientUserID"] = recipientUserID
        record["senderDeviceID"] = senderDeviceID
        record["recipientDeviceID"] = recipientDeviceID
        record["status"] = status.rawValue
        record["timestamp"] = timestamp
        return record
    }
    
    // Helper methods
    func isIncoming(for userID: String) -> Bool {
        return recipientUserID == userID
    }
    
    func isOutgoing(for userID: String) -> Bool {
        return senderUserID == userID
    }
    
    func otherUserID(for currentUserID: String) -> String {
        return currentUserID == senderUserID ? recipientUserID : senderUserID
    }
    
    func otherDeviceID(for currentDeviceID: String) -> String {
        return currentDeviceID == senderDeviceID ? recipientDeviceID : senderDeviceID
    }
} 