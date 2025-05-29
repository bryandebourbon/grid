import Foundation
import CloudKit

struct Report: Identifiable {
    let id: String // Unique report ID
    let reporterUserID: String // User who is making the report
    let reportedUserID: String // User being reported
    let reportedDeviceID: String // Device ID of the reported user
    let reportReason: ReportReason
    let reportDescription: String? // Optional additional details
    let timestamp: Date
    var recordID: CKRecord.ID?
    
    enum ReportReason: String, CaseIterable {
        case inappropriateContent = "inappropriate_content"
        case harassment = "harassment"
        case spam = "spam"
        case fake = "fake_profile"
        case offensive = "offensive_behavior"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .inappropriateContent:
                return "Inappropriate Content"
            case .harassment:
                return "Harassment or Bullying"
            case .spam:
                return "Spam"
            case .fake:
                return "Fake Profile"
            case .offensive:
                return "Offensive Behavior"
            case .other:
                return "Other"
            }
        }
    }
    
    init(reporterUserID: String, reportedUserID: String, reportedDeviceID: String, 
         reportReason: ReportReason, reportDescription: String? = nil, 
         timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.reporterUserID = reporterUserID
        self.reportedUserID = reportedUserID
        self.reportedDeviceID = reportedDeviceID
        self.reportReason = reportReason
        self.reportDescription = reportDescription
        self.timestamp = timestamp
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let reporterUserID = record["reporterUserID"] as? String,
              let reportedUserID = record["reportedUserID"] as? String,
              let reportedDeviceID = record["reportedDeviceID"] as? String,
              let reportReasonRaw = record["reportReason"] as? String,
              let reportReason = ReportReason(rawValue: reportReasonRaw),
              let timestamp = record["timestamp"] as? Date else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.reporterUserID = reporterUserID
        self.reportedUserID = reportedUserID
        self.reportedDeviceID = reportedDeviceID
        self.reportReason = reportReason
        self.reportDescription = record["reportDescription"] as? String
        self.timestamp = timestamp
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Reports", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["reporterUserID"] = reporterUserID
        record["reportedUserID"] = reportedUserID
        record["reportedDeviceID"] = reportedDeviceID
        record["reportReason"] = reportReason.rawValue
        record["reportDescription"] = reportDescription
        record["timestamp"] = timestamp
        return record
    }
} 