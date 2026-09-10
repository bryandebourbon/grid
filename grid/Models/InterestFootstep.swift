import Foundation
import CloudKit
import CoreLocation

struct InterestFootstep: Equatable {
    static let recordType = "InterestFootsteps"

    let interest: String
    let latitude: Double
    let longitude: Double
    let visitCount: Int
    let timestamp: Date
    let deviceID: String
    let userID: String
    let cellKey: String
    var recordID: CKRecord.ID

    var sample: InterestFootstepLogic.Sample {
        InterestFootstepLogic.Sample(
            id: recordID.recordName,
            interest: interest,
            latitude: latitude,
            longitude: longitude,
            visitCount: visitCount,
            timestamp: timestamp,
            deviceID: deviceID,
            userID: userID,
            cellKey: cellKey
        )
    }

    init(
        interest: String,
        latitude: Double,
        longitude: Double,
        visitCount: Int,
        timestamp: Date,
        deviceID: String,
        userID: String,
        cellKey: String,
        recordID: CKRecord.ID? = nil
    ) {
        self.interest = interest
        self.latitude = latitude
        self.longitude = longitude
        self.visitCount = visitCount
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.userID = userID
        self.cellKey = cellKey
        self.recordID = recordID ?? CKRecord.ID(
            recordName: InterestFootstepLogic.recordName(
                interest: interest,
                pingID: UUID().uuidString
            )
        )
    }

    init?(record: CKRecord) {
        guard let interest = (record["interest"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              interest.isEmpty == false else {
            return nil
        }
        let latitude = record["latitude"] as? Double
            ?? (record["location"] as? CLLocation)?.coordinate.latitude
        let longitude = record["longitude"] as? Double
            ?? (record["location"] as? CLLocation)?.coordinate.longitude
        guard let latitude, let longitude else { return nil }
        let visit: Int
        if let number = record["visitCount"] as? Int {
            visit = number
        } else if let number = record["visitCount"] as? Int64 {
            visit = Int(number)
        } else if let number = record["visitCount"] as? NSNumber {
            visit = number.intValue
        } else {
            visit = 1
        }
        let deviceID = (record["deviceID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userID = (record["userID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cellKey = (record["cellKey"] as? String)
            ?? InterestFootstepLogic.cellKey(latitude: latitude, longitude: longitude)
        self.init(
            interest: interest,
            latitude: latitude,
            longitude: longitude,
            visitCount: max(visit, 1),
            timestamp: record["timestamp"] as? Date ?? Date(),
            deviceID: deviceID,
            userID: userID,
            cellKey: cellKey,
            recordID: record.recordID
        )
    }

    func toCKRecord(base: CKRecord? = nil) -> CKRecord {
        let record = base ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["interest"] = interest
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["location"] = CLLocation(latitude: latitude, longitude: longitude)
        record["visitCount"] = visitCount as NSNumber
        record["timestamp"] = timestamp
        record["cellKey"] = cellKey
        return record
    }
}
