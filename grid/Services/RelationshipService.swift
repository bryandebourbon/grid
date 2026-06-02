import Foundation
import CloudKit

/// Persistence for star/block relationships stored in the `UserRelationships`
/// public record type. This service is pure I/O: it never touches UI state.
/// Callers own the in-memory sets and any grid refresh.
class RelationshipService {

    /// Snapshot of a user's relationship graph, keyed by userID.
    struct RelationshipData {
        var starred: Set<String>    // targetUserIDs the user has starred
        var blocked: Set<String>    // targetUserIDs the user has blocked
        var blockedBy: Set<String>  // userIDs who have blocked the user
    }

    private let publicDB: CKDatabase

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    /// Load both outgoing (star/block) and incoming (blocked-by) relationships.
    /// Completion is delivered on the main queue.
    func loadRelationships(forUserID userID: String, completion: @escaping (RelationshipData) -> Void) {
        let group = DispatchGroup()
        var starred: Set<String> = []
        var blocked: Set<String> = []
        var blockedBy: Set<String> = []

        group.enter()
        let mineQuery = CKQuery(
            recordType: "UserRelationships",
            predicate: NSPredicate(format: "userID == %@", userID)
        )
        publicDB.perform(mineQuery, inZoneWith: nil) { records, error in
            if let error = error {
                print("RelationshipService: error loading own relationships: \(error.localizedDescription)")
            }
            for record in records ?? [] {
                guard let relationship = UserRelationship(record: record) else { continue }
                switch relationship.actionType {
                case .star: starred.insert(relationship.targetUserID)
                case .block: blocked.insert(relationship.targetUserID)
                case .report: break
                }
            }
            group.leave()
        }

        group.enter()
        let blockedByQuery = CKQuery(
            recordType: "UserRelationships",
            predicate: NSPredicate(format: "targetUserID == %@ AND actionType == %@", userID, "block")
        )
        publicDB.perform(blockedByQuery, inZoneWith: nil) { records, error in
            if let error = error {
                print("RelationshipService: error loading incoming blocks: \(error.localizedDescription)")
            }
            for record in records ?? [] {
                guard let relationship = UserRelationship(record: record) else { continue }
                blockedBy.insert(relationship.userID)
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(RelationshipData(starred: starred, blocked: blocked, blockedBy: blockedBy))
        }
    }

    /// Save a star/block relationship. Completion is delivered on the main queue.
    func saveRelationship(
        userID: String,
        targetUserID: String,
        actionType: UserRelationship.ActionType,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let record = UserRelationship(userID: userID, targetUserID: targetUserID, actionType: actionType).toCKRecord()
        publicDB.save(record) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("RelationshipService: error saving \(actionType.rawValue): \(error.localizedDescription)")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }

    /// Delete a star/block relationship. Completion is delivered on the main queue.
    func deleteRelationship(
        userID: String,
        targetUserID: String,
        actionType: UserRelationship.ActionType,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let recordID = CKRecord.ID(recordName: "\(userID)_\(targetUserID)_\(actionType.rawValue)")
        publicDB.delete(withRecordID: recordID) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("RelationshipService: error deleting \(actionType.rawValue): \(error.localizedDescription)")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }
}
