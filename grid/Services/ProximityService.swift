import Combine
import SwiftUI
import CloudKit
import CoreLocation

class ProximityService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var activeNearbyProfiles: [UserProfile] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownLocation: CLLocation? // Store last known location
    private var latestActivityProfile: UserProfile?
    private var activitySaveCompletions: [(Result<UserProfile, Error>) -> Void] = []
    private var isSavingActivity = false
    
    private var isFetchingAllUsers = false
    private var queuedFetchAllUsers = false
    private var queuedFetchLocation: CLLocation?
    private var queuedExtraRecordNames: [String] = []
    private var fetchAllUsersCompletions: [() -> Void] = []
    
    init() {
        // No automatic timer - only refresh on demand
    }
    
    // Fetch ALL users and sort by distance - simple and straightforward
    func fetchAllUsers(
        currentUserLocation: CLLocation? = nil,
        extraRecordNames: [String] = [],
        completion: (() -> Void)? = nil
    ) {
        print("ProximityService: fetchAllUsers called with location: \(currentUserLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0))")
        
        if let location = currentUserLocation {
            lastKnownLocation = location
            queuedFetchLocation = location
        }
        queuedExtraRecordNames.append(contentsOf: extraRecordNames)
        if let completion {
            fetchAllUsersCompletions.append(completion)
        }
        guard isFetchingAllUsers == false else {
            queuedFetchAllUsers = true
            return
        }
        startFetchAllUsers()
    }

    private func startFetchAllUsers() {
        isFetchingAllUsers = true
        queuedFetchAllUsers = false
        let locationToUse = queuedFetchLocation ?? lastKnownLocation
        let extraRecordNames = UserProfileQueryLogic.missingRecordNames(
            fetched: [],
            known: queuedExtraRecordNames
        )
        queuedExtraRecordNames = []
        let completions = fetchAllUsersCompletions
        fetchAllUsersCompletions = []
        let predicates = UserProfileQueryLogic.fetchPredicates()
        var predicateIndex = 0
        var gathered: [CKRecord] = []
        var seenNames = Set<String>()
        var stubIDs: [String] = []

        func append(_ record: CKRecord) {
            let name = record.recordID.recordName
            guard seenNames.insert(name).inserted else { return }
            gathered.append(record)
        }

        func publish() {
            var fetched = gathered.compactMap { UserProfile(record: $0) }
            let knownIDs = fetched.map(\.deviceID) + gathered.map(\.recordID.recordName)
            let missing = UserProfileQueryLogic.missingRecordNames(fetched: knownIDs, known: stubIDs)
            fetched.append(contentsOf: missing.map(UserProfileQueryLogic.stubProfile(deviceID:)))
            fetched = UserProfileQueryLogic.uniqueProfiles(fetched)
            let leftover = fetched.filter(GridPresenceLogic.isLeftoverDebugPeer)
            let allProfiles = fetched.filter(GridPresenceLogic.shouldShowPeer)
            print("ProximityService: Successfully parsed \(allProfiles.count) UserProfile objects from \(gathered.count) CloudKit records")
            self.deleteLeftoverDebugPeers(leftover)
            self.activeNearbyProfiles = NearbyProfileSortLogic.sorted(allProfiles, from: locationToUse)
            print("ProximityService: Final activeNearbyProfiles count: \(self.activeNearbyProfiles.count)")
        }

        func finish(error: Error?) {
            DispatchQueue.main.async {
                if let error, gathered.isEmpty {
                    if error.localizedDescription.contains("Did not find record type") {
                        print("CloudKit schema not initialized yet - UserProfiles record type doesn't exist. This is normal for new apps.")
                        self.activeNearbyProfiles = []
                    } else {
                        print("ProximityService: Error fetching users: \(error.localizedDescription)")
                    }
                } else {
                    if let error {
                        print("ProximityService: Error fetching users: \(error.localizedDescription)")
                    }
                    publish()
                }
                completions.forEach { $0() }
                self.isFetchingAllUsers = false
                if self.queuedFetchAllUsers {
                    self.startFetchAllUsers()
                }
            }
        }

        func fillGaps(named names: [String]) {
            let knownIDs = Array(seenNames) + gathered.compactMap { $0["deviceID"] as? String }
            let missing = UserProfileQueryLogic.missingRecordNames(fetched: knownIDs, known: names)
            stubIDs = missing
            guard missing.isEmpty == false else {
                finish(error: nil)
                return
            }
            print("ProximityService: fetching \(missing.count) UserProfiles by record ID")
            let operation = CKFetchRecordsOperation(recordIDs: missing.map { CKRecord.ID(recordName: $0) })
            operation.qualityOfService = .userInitiated
            operation.fetchRecordsCompletionBlock = { recordsByID, error in
                if let ckError = error as? CKError, ckError.code == .partialFailure {
                    print("ProximityService: some UserProfiles were missing by record ID")
                } else if let error {
                    print("ProximityService: record ID fetch failed (\(error.localizedDescription))")
                }
                recordsByID?.values.forEach { append($0) }
                finish(error: nil)
            }
            self.publicDB.add(operation)
        }

        func fetchEncryptionDeviceIDs(then continueWith: @escaping ([String]) -> Void) {
            if extraRecordNames.isEmpty == false {
                continueWith(extraRecordNames)
                return
            }
            var ids: [String] = []
            let query = CKQuery(
                recordType: "EncryptionProfiles",
                predicate: NSPredicate(format: "isEncryptionEnabled == 1")
            )
            let operation = CKQueryOperation(query: query)
            operation.qualityOfService = .userInitiated
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordMatchedBlock = { _, result in
                guard case .success(let record) = result else { return }
                let name = record.recordID.recordName
                if name.hasPrefix("encryption_") {
                    ids.append(String(name.dropFirst("encryption_".count)))
                } else if let deviceID = record["deviceID"] as? String {
                    ids.append(deviceID)
                }
            }
            operation.queryResultBlock = { result in
                if case .failure(let error) = result {
                    print("ProximityService: encryption profile query failed (\(error.localizedDescription))")
                }
                continueWith(ids)
            }
            self.publicDB.add(operation)
        }

        func run(cursor: CKQueryOperation.Cursor?) {
            guard predicateIndex < predicates.count else {
                fetchEncryptionDeviceIDs { names in
                    fillGaps(named: names)
                }
                return
            }
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: "UserProfiles", predicate: predicates[predicateIndex])
                operation = CKQueryOperation(query: query)
            }
            operation.qualityOfService = .userInitiated
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let nextCursor):
                    if let nextCursor {
                        run(cursor: nextCursor)
                    } else if gathered.isEmpty, predicateIndex + 1 < predicates.count {
                        predicateIndex += 1
                        run(cursor: nil)
                    } else {
                        fetchEncryptionDeviceIDs { names in
                            fillGaps(named: names)
                        }
                    }
                case .failure(let error):
                    if cursor == nil, predicateIndex + 1 < predicates.count {
                        print("ProximityService: query predicate \(predicateIndex) failed (\(error.localizedDescription)); trying fallback")
                        predicateIndex += 1
                        run(cursor: nil)
                    } else {
                        fetchEncryptionDeviceIDs { names in
                            fillGaps(named: names)
                        }
                    }
                }
            }
            self.publicDB.add(operation)
        }

        run(cursor: nil)
    }
    
    // Keep for backward compatibility - now just calls fetchAllUsers
    func fetchActiveNearbyUsers(currentUserLocation: CLLocation? = nil) {
        fetchAllUsers(currentUserLocation: currentUserLocation)
    }
    
    // Update current user's active status and location in CloudKit
    func updateUserActivity(_ profile: UserProfile, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        if GridPresenceLogic.isLeftoverDebugPeer(profile) {
            completion(.failure(NSError(
                domain: "ProximityService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to publish a test fixture profile"]
            )))
            return
        }
        print("DEBUG: Saving profile to CloudKit - lat: \(profile.latitude ?? 0), lon: \(profile.longitude ?? 0), discoverable: \(profile.isDiscoverable)")
        DispatchQueue.main.async {
            self.latestActivityProfile = profile
            self.activitySaveCompletions.append(completion)
            self.pumpActivitySave()
        }
    }

    private func pumpActivitySave() {
        guard isSavingActivity == false, let profile = latestActivityProfile else { return }
        latestActivityProfile = nil
        let completions = activitySaveCompletions
        activitySaveCompletions = []
        isSavingActivity = true
        performActivitySave(profile) { [weak self] result in
            guard let self else { return }
            self.isSavingActivity = false
            completions.forEach { $0(result) }
            self.pumpActivitySave()
        }
    }

    private func performActivitySave(
        _ profile: UserProfile,
        completion: @escaping (Result<UserProfile, Error>) -> Void
    ) {
        let recordID = CKRecord.ID(recordName: profile.deviceID)
        publicDB.fetch(withRecordID: recordID) { [weak self] existing, error in
            guard let self else { return }

            let record: CKRecord
            if let existing {
                record = existing
                profile.applyPublicFields(to: record)
            } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                record = profile.toPublicCKRecord()
            } else if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            } else {
                record = profile.toPublicCKRecord()
            }

            self.savePublicProfile(record, completion: completion)
        }
    }

    private func savePublicProfile(
        _ record: CKRecord,
        completion: @escaping (Result<UserProfile, Error>) -> Void
    ) {
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, _, error in
            DispatchQueue.main.async {
                if let error {
                    print("Error updating user activity: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let savedRecord = savedRecords?.first,
                      let updatedProfile = UserProfile(record: savedRecord) else {
                    print("Failed to process updated profile record")
                    completion(.failure(NSError(
                        domain: "ProximityService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to process updated profile."]
                    )))
                    return
                }

                print("Updated user activity for device: \(updatedProfile.deviceName) discoverable=\(updatedProfile.isDiscoverable)")
                print("DEBUG: Saved profile lat: \(updatedProfile.latitude ?? 0), lon: \(updatedProfile.longitude ?? 0)")
                completion(.success(updatedProfile))
            }
        }
        publicDB.add(modifyOperation)
    }
    
    // Mark user as inactive when app goes to background
    func markUserAsInactive(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: deviceID)
        
        publicDB.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let record = record else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ProximityService", code: -2, userInfo: [NSLocalizedDescriptionKey: "User record not found"])))
                }
                return
            }
            
            // Update the record to mark as inactive
            record["isCurrentlyActive"] = false
            // Keep lastActiveTimestamp as is - shows when they were last active
            
            self.publicDB.save(record) { savedRecord, saveError in
                DispatchQueue.main.async {
                    if let saveError = saveError {
                        completion(.failure(saveError))
                    } else {
                        print("Marked user as inactive: \(deviceID)")
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    // Simplified - allow messaging anyone you can see
    func canMessage(from currentUser: UserProfile, to targetUser: UserProfile) -> (allowed: Bool, reason: String) {
        // Simple rule: if you can see them, you can message them
        return (true, "Ready to message")
    }
    
    // Get formatted distance string in kilometers (.01km to 99km)
    func formatDistance(_ distance: Double) -> String {
        DistanceFormatLogic.format(meters: distance)
    }

    private func deleteLeftoverDebugPeers(_ profiles: [UserProfile]) {
        let ids = profiles.map { $0.recordID ?? CKRecord.ID(recordName: $0.deviceID) }
        guard ids.isEmpty == false else { return }
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
        operation.isAtomic = false
        operation.modifyRecordsCompletionBlock = { _, deleted, error in
            if let error {
                print("ProximityService: could not delete leftover test peers: \(error.localizedDescription)")
            } else {
                print("ProximityService: deleted \(deleted?.count ?? 0) leftover test peer records")
            }
        }
        publicDB.add(operation)
    }
} 