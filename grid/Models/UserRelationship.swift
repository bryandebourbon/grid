import Foundation
import CloudKit

struct UserRelationship: Identifiable {
    let id: String // Format: "userID_targetUserID_type"
    let userID: String // The user who is creating the relationship
    let targetUserID: String // The user being starred/blocked/etc (applies to all their devices)
    let actionType: ActionType
    let timestamp: Date
    var recordID: CKRecord.ID?
    
    enum ActionType: String {
        case star = "star"
        case block = "block"
        case report = "report"
        // Future: case heart = "heart"
    }
    
    init(userID: String, targetUserID: String, actionType: ActionType, timestamp: Date = Date()) {
        self.id = "\(userID)_\(targetUserID)_\(actionType.rawValue)"
        self.userID = userID
        self.targetUserID = targetUserID
        self.actionType = actionType
        self.timestamp = timestamp
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let userID = record["userID"] as? String,
              let targetUserID = record["targetUserID"] as? String,
              let actionTypeRaw = record["actionType"] as? String,
              let actionType = ActionType(rawValue: actionTypeRaw),
              let timestamp = record["timestamp"] as? Date else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.userID = userID
        self.targetUserID = targetUserID
        self.actionType = actionType
        self.timestamp = timestamp
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "UserRelationships", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["userID"] = userID
        record["targetUserID"] = targetUserID
        record["actionType"] = actionType.rawValue
        record["timestamp"] = timestamp
        return record
    }
} 