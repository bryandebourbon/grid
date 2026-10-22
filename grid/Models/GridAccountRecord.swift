import CloudKit
import Foundation

enum GridDatabase {
    /// Development schema is created by the first save from a phone.
    /// Production stays untouched until that schema is deployed.
    static let containerID = "iCloud.com.bryandebourbon.grid"
}

struct AccountRecord {
    static let recordType = "Account"

    var id: String
    var appleUserID: String
    var createdAt: Date

    init(id: String, appleUserID: String, createdAt: Date) {
        self.id = id
        self.appleUserID = appleUserID
        self.createdAt = createdAt
    }

    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id))
        record["appleUserID"] = appleUserID
        if record["createdAt"] == nil {
            record["createdAt"] = createdAt
        }
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == Self.recordType,
              let appleUserID = record["appleUserID"] as? String,
              appleUserID.isEmpty == false else { return nil }
        self.id = record.recordID.recordName
        self.appleUserID = appleUserID
        self.createdAt = record["createdAt"] as? Date ?? Date()
    }
}

struct DeviceRecord {
    static let recordType = "Device"

    var id: String
    var accountID: String
    var name: String
    var publicKey: String?
    var latitude: Double?
    var longitude: Double?
    var lastActiveAt: Date

    static func recordName(deviceID: String) -> String { "device.\(deviceID)" }

    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: Self.recordName(deviceID: id)))
        record["accountID"] = accountID
        record["name"] = name
        record["lastActiveAt"] = lastActiveAt
        if let publicKey { record["publicKey"] = publicKey }
        if let latitude { record["latitude"] = latitude }
        if let longitude { record["longitude"] = longitude }
        return record
    }
}

struct ProfileCardRecord {
    static let recordType = "ProfileCard"

    var accountID: String
    var displayName: String
    var bio: String?
    var discoverable: Bool
    var latitude: Double?
    var longitude: Double?
    var lastActiveAt: Date
    var photo: CKAsset?

    /// Record names are unique across every type in the zone, so the card cannot reuse the account id.
    static func recordName(accountID: String) -> String { "profile.\(accountID)" }

    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: Self.recordName(accountID: accountID))
        )
        record["displayName"] = displayName
        record["discoverable"] = discoverable
        record["lastActiveAt"] = lastActiveAt
        if let bio { record["bio"] = bio }
        if let latitude { record["latitude"] = latitude }
        if let longitude { record["longitude"] = longitude }
        if let photo {
            record["photo"] = photo
        }
        return record
    }
}
