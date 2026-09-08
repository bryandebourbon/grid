import Foundation
import CloudKit

/// Shared interest catalog in the public `SharedInterests` record type.
class SharedInterestService {
    static let recordType = "SharedInterests"

    private let publicDB: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    func fetchAll(completion: @escaping ([CustomInterestRecord]) -> Void) {
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(format: "isPublic == 1")
        )
        publicDB.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("SharedInterestService: error loading catalog: \(error.localizedDescription)")
                    completion([])
                    return
                }
                completion((records ?? []).compactMap(Self.record(from:)))
            }
        }
    }

    func publish(_ item: CustomInterestRecord, createdByUserID: String?) {
        let recordID = CKRecord.ID(recordName: SharedInterestIdentity.recordName(for: item.name))
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["name"] = item.name
        record["emoji"] = item.emoji
        record["isPublic"] = 1
        if let createdByUserID, !createdByUserID.isEmpty {
            record["createdByUserID"] = createdByUserID
        }
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
        operation.modifyRecordsCompletionBlock = { _, _, error in
            if let error {
                let nsError = error as NSError
                if nsError.code == CKError.serverRecordChanged.rawValue
                    || nsError.code == CKError.partialFailure.rawValue {
                    return
                }
                print("SharedInterestService: error publishing \(item.name): \(error.localizedDescription)")
            }
        }
        publicDB.add(operation)
    }

    private static func record(from ckRecord: CKRecord) -> CustomInterestRecord? {
        guard let name = ckRecord["name"] as? String else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let emoji = (ckRecord["emoji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomInterestRecord(name: trimmed, emoji: (emoji?.isEmpty == false ? emoji! : "✨"))
    }
}
