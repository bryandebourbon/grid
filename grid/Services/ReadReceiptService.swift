import Foundation
import CloudKit

/// Persistence for message read receipts stored in the `ReadReceipts`
/// public record type. Pure I/O: it never touches UI state. Callers own the
/// in-memory set of read message IDs and any message-status updates.
class ReadReceiptService {

    private let publicDB: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    /// Load the set of message IDs this device has marked as read.
    /// Completion is delivered on the main queue.
    func loadReceipts(forDeviceID deviceID: String, completion: @escaping (Set<String>) -> Void) {
        let query = CKQuery(
            recordType: "ReadReceipts",
            predicate: NSPredicate(format: "deviceID == %@", deviceID)
        )
        publicDB.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("ReadReceiptService: error loading receipts: \(error.localizedDescription)")
                    completion([])
                    return
                }
                let ids = Set((records ?? []).compactMap { ReadReceipt(record: $0)?.messageID })
                completion(ids)
            }
        }
    }

    /// Persist the given read receipts. Fire-and-forget; errors are logged.
    func saveReceipts(_ receipts: [ReadReceipt]) {
        guard !receipts.isEmpty else { return }
        let operation = CKModifyRecordsOperation(recordsToSave: receipts.map { $0.toCKRecord() }, recordIDsToDelete: nil)
        operation.modifyRecordsCompletionBlock = { savedRecords, _, error in
            if let error = error {
                print("ReadReceiptService: error saving receipts: \(error.localizedDescription)")
            } else {
                print("ReadReceiptService: saved \(savedRecords?.count ?? 0) read receipts")
            }
        }
        publicDB.add(operation)
    }
}
