import Foundation
import CloudKit

struct Story: Identifiable {
    let id: String // Unique story ID (also used as CloudKit record name)
    let userID: String // Apple user ID who posted the story
    let deviceID: String // Device that posted the story
    let imageAsset: CKAsset? // The story photo/video content
    let caption: String? // Optional text caption for the story
    let timestamp: Date // When the story was posted
    let expirationDate: Date // When it expires (timestamp + 24 hours)
    let isActive: Bool // Whether the story is still active
    var recordID: CKRecord.ID?
    
    // Computed property to check if story has expired
    var hasExpired: Bool {
        return Date() > expirationDate
    }
    
    // Computed property to check if story is still valid
    var isValid: Bool {
        return isActive && !hasExpired
    }
    
    // Time remaining before expiration
    var timeRemaining: TimeInterval {
        return expirationDate.timeIntervalSinceNow
    }
    
    // Initializer for creating a new story
    init(userID: String, 
         deviceID: String, 
         imageAsset: CKAsset?, 
         caption: String? = nil, 
         timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.userID = userID
        self.deviceID = deviceID
        self.imageAsset = imageAsset
        self.caption = caption
        self.timestamp = timestamp
        self.expirationDate = timestamp.addingTimeInterval(24 * 60 * 60) // 24 hours
        self.isActive = true
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let userID = record["userID"] as? String,
              let deviceID = record["deviceID"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let expirationDate = record["expirationDate"] as? Date,
              let isActiveInt = record["isActive"] as? Int64 else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.userID = userID
        self.deviceID = deviceID
        self.imageAsset = record["imageAsset"] as? CKAsset
        self.caption = record["caption"] as? String
        self.timestamp = timestamp
        self.expirationDate = expirationDate
        self.isActive = isActiveInt == 1
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Stories", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["userID"] = userID
        record["deviceID"] = deviceID
        record["imageAsset"] = imageAsset
        record["caption"] = caption
        record["timestamp"] = timestamp
        record["expirationDate"] = expirationDate
        record["isActive"] = isActive ? Int64(1) : Int64(0)
        return record
    }
    
    // Create an expired version of this story
    func expired() -> Story {
        var expiredStory = self
        expiredStory.recordID = self.recordID
        return Story(
            id: self.id,
            userID: self.userID,
            deviceID: self.deviceID,
            imageAsset: self.imageAsset,
            caption: self.caption,
            timestamp: self.timestamp,
            expirationDate: self.expirationDate,
            isActive: false,
            recordID: self.recordID
        )
    }
    
    // Private initializer for expired stories
    private init(id: String, userID: String, deviceID: String, imageAsset: CKAsset?, caption: String?, timestamp: Date, expirationDate: Date, isActive: Bool, recordID: CKRecord.ID?) {
        self.id = id
        self.userID = userID
        self.deviceID = deviceID
        self.imageAsset = imageAsset
        self.caption = caption
        self.timestamp = timestamp
        self.expirationDate = expirationDate
        self.isActive = isActive
        self.recordID = recordID
    }
}

// MARK: - StoryView Model

struct StoryView: Identifiable {
    let id: String // Unique view ID
    let storyID: String // Reference to the story record name
    let viewerUserID: String // Apple user ID who viewed it
    let viewerDeviceID: String // Device that viewed the story
    let timestamp: Date // When the story was viewed
    var recordID: CKRecord.ID?
    
    // Initializer for creating a new story view
    init(storyID: String, viewerUserID: String, viewerDeviceID: String, timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.storyID = storyID
        self.viewerUserID = viewerUserID
        self.viewerDeviceID = viewerDeviceID
        self.timestamp = timestamp
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initializer from CKRecord
    init?(record: CKRecord) {
        guard let storyID = record["storyID"] as? String,
              let viewerUserID = record["viewerUserID"] as? String,
              let viewerDeviceID = record["viewerDeviceID"] as? String,
              let timestamp = record["timestamp"] as? Date else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.storyID = storyID
        self.viewerUserID = viewerUserID
        self.viewerDeviceID = viewerDeviceID
        self.timestamp = timestamp
        self.recordID = record.recordID
    }
    
    // Convert to CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "StoryViews", recordID: recordID ?? CKRecord.ID(recordName: id))
        record["storyID"] = storyID
        record["viewerUserID"] = viewerUserID
        record["viewerDeviceID"] = viewerDeviceID
        record["timestamp"] = timestamp
        return record
    }
} 