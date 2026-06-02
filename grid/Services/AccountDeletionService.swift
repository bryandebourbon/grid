import Foundation
import CloudKit

/// Deletes all public records a user owns when they delete their account.
/// Received messages are owned by their senders and are intentionally left intact
/// (the user has no write permission on them).
class AccountDeletionService {

    private let publicDB: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    /// Delete the user's profile, sent messages, relationships, and encryption profile.
    /// Completion is delivered on the main queue with the first error encountered (if any).
    func deleteAllRecords(forUserID userID: String, deviceID: String, completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        var firstError: Error?

        let queries: [(query: CKQuery, label: String)] = [
            (CKQuery(recordType: "UserProfiles", predicate: NSPredicate(format: "userID == %@", userID)), "UserProfiles"),
            (CKQuery(recordType: "Messages", predicate: NSPredicate(format: "senderUserID == %@", userID)), "Sent Messages"),
            (CKQuery(recordType: "UserRelationships", predicate: NSPredicate(format: "userID == %@", userID)), "UserRelationships"),
            (CKQuery(recordType: "EncryptionProfiles", predicate: NSPredicate(format: "deviceID == %@", deviceID)), "EncryptionProfiles"),
        ]

        for entry in queries {
            group.enter()
            fetchAndDeleteRecords(query: entry.query, recordTypeForLog: entry.label) { error in
                if let error = error {
                    print("AccountDeletionService: error deleting \(entry.label): \(error.localizedDescription)")
                    if firstError == nil { firstError = error }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(firstError)
        }
    }

    private func fetchAndDeleteRecords(query: CKQuery, recordTypeForLog: String, completion: @escaping (Error?) -> Void) {
        var recordIDsToDelete: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor? = nil

        func fetchNextBatch() {
            let operation = cursor.map { CKQueryOperation(cursor: $0) } ?? CKQueryOperation(query: query)
            operation.resultsLimit = CKQueryOperation.maximumResults

            operation.recordFetchedBlock = { record in
                recordIDsToDelete.append(record.recordID)
            }

            operation.queryCompletionBlock = { [weak self] opCursor, error in
                if let error = error {
                    print("AccountDeletionService: error fetching \(recordTypeForLog) for deletion: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                cursor = opCursor
                if opCursor != nil {
                    fetchNextBatch()
                } else {
                    self?.deleteRecords(recordIDs: recordIDsToDelete, recordTypeForLog: recordTypeForLog, completion: completion)
                }
            }
            publicDB.add(operation)
        }

        fetchNextBatch()
    }

    private func deleteRecords(recordIDs: [CKRecord.ID], recordTypeForLog: String, completion: @escaping (Error?) -> Void) {
        guard !recordIDs.isEmpty else {
            completion(nil)
            return
        }

        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        operation.isAtomic = false // delete as many as possible even if some fail

        operation.modifyRecordsCompletionBlock = { _, deletedRecordIDs, error in
            if let error = error {
                print("AccountDeletionService: error deleting \(recordTypeForLog): \(error.localizedDescription)")
                if let ckError = error as? CKError, ckError.code == .partialFailure,
                   let partialErrors = ckError.partialErrorsByItemID {
                    for (key, partialError) in partialErrors {
                        let name = (key as? CKRecord.ID)?.recordName ?? "unknown"
                        print("AccountDeletionService: error deleting record \(name): \(partialError.localizedDescription)")
                    }
                }
                completion(error)
            } else {
                print("AccountDeletionService: deleted \(deletedRecordIDs?.count ?? 0) \(recordTypeForLog) records")
                completion(nil)
            }
        }
        publicDB.add(operation)
    }
}
