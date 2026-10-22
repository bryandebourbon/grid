import CloudKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Writes Account, Device, and ProfileCard into the fresh container.
/// The grid still reads the legacy container until those screens move over.
final class AccountDirectory {
    static let shared = AccountDirectory()

    private let database: CKDatabase
    private let defaults: UserDefaults
    private let gate = NSLock()
    private var inFlight = false

    init(database: CKDatabase? = nil, defaults: UserDefaults = .standard) {
        if let database {
            self.database = database
        } else {
            self.database = CKContainer.default().publicCloudDatabase
        }
        self.defaults = defaults
    }

    func ensureIdentity(for profile: UserProfile) {
        let appleUserID = profile.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appleUserID.isEmpty == false else { return }
        gate.lock()
        if inFlight {
            gate.unlock()
            return
        }
        inFlight = true
        gate.unlock()
        fetchAccountID(appleUserID: appleUserID) { [weak self] lookup in
            guard let self else { return }
            guard let account = GridIdentityLogic.accountID(
                stored: self.defaults.string(forKey: Self.accountKey(appleUserID)),
                lookup: lookup
            ) else {
                self.finish()
                return
            }
            self.defaults.set(account.id, forKey: Self.accountKey(appleUserID))
            let device = GridIdentityLogic.deviceID(
                stored: self.defaults.string(forKey: Self.deviceKey(account.id))
            )
            self.defaults.set(device.id, forKey: Self.deviceKey(account.id))
            self.upsert(self.records(accountID: account.id, deviceID: device.id, profile: profile))
        }
    }

    private func records(accountID: String, deviceID: String, profile: UserProfile) -> [CKRecord] {
        let now = Date()
        let account = AccountRecord(id: accountID, appleUserID: profile.userID, createdAt: now)
        let device = DeviceRecord(
            id: deviceID,
            accountID: accountID,
            name: Self.phoneName,
            publicKey: CryptoService.shared.getPublicKey(),
            latitude: profile.latitude,
            longitude: profile.longitude,
            lastActiveAt: profile.lastActiveTimestamp
        )
        let card = ProfileCardRecord(
            accountID: accountID,
            displayName: profile.deviceName,
            bio: profile.bio,
            discoverable: profile.isDiscoverable,
            latitude: profile.latitude,
            longitude: profile.longitude,
            lastActiveAt: profile.lastActiveTimestamp,
            photo: profile.profileImage?.fileURL.map { CKAsset(fileURL: $0) }
        )
        return [account.makeRecord(), device.makeRecord(), card.makeRecord()]
    }

    private func fetchAccountID(appleUserID: String, completion: @escaping (GridIdentityLogic.AccountLookup) -> Void) {
        let query = CKQuery(
            recordType: AccountRecord.recordType,
            predicate: NSPredicate(format: "appleUserID == %@", appleUserID)
        )
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1
        var found: String?
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                found = record.recordID.recordName
            }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                if let found, found.isEmpty == false {
                    completion(.found(found))
                } else {
                    completion(.missing)
                }
            case .failure(let error):
                print("AccountDirectory: account lookup failed (\(error.localizedDescription))")
                completion(GridIdentityLogic.accountLookup(from: error))
            }
        }
        database.add(operation)
    }

    private func upsert(_ drafts: [CKRecord]) {
        let operation = CKFetchRecordsOperation(recordIDs: drafts.map(\.recordID))
        var existing: [String: CKRecord] = [:]
        operation.perRecordResultBlock = { id, result in
            if case .success(let record) = result {
                existing[id.recordName] = record
            }
        }
        operation.fetchRecordsResultBlock = { [weak self] _ in
            guard let self else { return }
            let saving = drafts.map { draft in
                guard let current = existing[draft.recordID.recordName] else { return draft }
                for key in draft.allKeys() {
                    if key == "createdAt", current[key] != nil { continue }
                    current[key] = draft[key]
                }
                return current
            }
            let save = CKModifyRecordsOperation(recordsToSave: saving, recordIDsToDelete: nil)
            save.savePolicy = .changedKeys
            save.modifyRecordsResultBlock = { [weak self] result in
                if case .failure(let error) = result {
                    print("AccountDirectory: identity save failed (\(error.localizedDescription))")
                } else {
                    print("AccountDirectory: saved Account, Device, and ProfileCard")
                }
                self?.finish()
            }
            self.database.add(save)
        }
        database.add(operation)
    }

    private func finish() {
        gate.lock()
        inFlight = false
        gate.unlock()
    }

    private static func accountKey(_ appleUserID: String) -> String {
        "grid.v2.accountID.\(appleUserID)"
    }

    private static func deviceKey(_ accountID: String) -> String {
        "grid.v2.deviceID.\(accountID)"
    }

    private static var phoneName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        "Phone"
        #endif
    }
}
