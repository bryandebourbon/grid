import Foundation
import CloudKit

/// Persistence for published device public keys stored in the
/// `EncryptionProfiles` public record type. Pure I/O: it never touches UI state.
class EncryptionProfileService {

    private let publicDB: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    /// Create or update the given encryption profile (upsert via `.changedKeys`).
    func save(_ profile: EncryptionProfile) {
        let operation = CKModifyRecordsOperation(recordsToSave: [profile.toCKRecord()], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.modifyRecordsCompletionBlock = { _, _, error in
            if let error = error {
                print("EncryptionProfileService: error saving profile \(profile.id): \(error.localizedDescription)")
            }
        }
        publicDB.add(operation)
    }

    /// Load all encryption-enabled profiles. Completion is delivered on the main queue.
    func loadEnabledProfiles(completion: @escaping ([EncryptionProfile]) -> Void) {
        let query = CKQuery(
            recordType: "EncryptionProfiles",
            predicate: NSPredicate(format: "isEncryptionEnabled == 1")
        )
        publicDB.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("EncryptionProfileService: error loading profiles: \(error.localizedDescription)")
                    completion([])
                    return
                }
                completion((records ?? []).compactMap { EncryptionProfile(record: $0) })
            }
        }
    }
}
