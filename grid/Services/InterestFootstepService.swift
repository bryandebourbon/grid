import Foundation
import CloudKit
import CoreLocation

/// Public CloudKit table of per-interest walking pings the community reads in map mode.
class InterestFootstepService {
    private let publicDB: CKDatabase
    private var lastWrites: [String: InterestFootstepLogic.LastWrite] = [:]

    init(database: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = database
    }

    @discardableResult
    func recordVisit(
        profile: UserProfile,
        location: CLLocation,
        viewingInterest: String? = nil,
        now: Date = Date(),
        completion: (() -> Void)? = nil
    ) -> [InterestFootstepLogic.Sample] {
        guard InterestFootstepLogic.shouldContribute(
            profile: profile,
            location: location,
            viewingInterest: viewingInterest
        ) else {
            DispatchQueue.main.async { completion?() }
            return []
        }

        let interests = InterestFootstepLogic.recordableInterests(from: profile, viewing: viewingInterest)
        var samples: [InterestFootstepLogic.Sample] = []
        for interest in interests {
            let sample = InterestFootstepLogic.sample(
                interest: interest.rawValue,
                location: location,
                deviceID: profile.deviceID,
                userID: profile.userID,
                timestamp: now
            )
            samples.append(sample)
            lastWrites[interest.rawValue.lowercased()] = InterestFootstepLogic.LastWrite(
                cellKey: sample.cellKey,
                timestamp: now
            )
        }

        InterestFootstepStore.append(samples, now: now)
        InterestFootstepStore.enqueuePending(samples, now: now)
        flushPending {
            DispatchQueue.main.async { completion?() }
        }
        return samples
    }

    func fetch(
        interest: String,
        now: Date = Date(),
        completion: @escaping ([InterestFootstepLogic.Sample]) -> Void
    ) {
        let trimmed = interest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        flushPending { [weak self] in
            self?.queryPublicTrail(interest: trimmed, now: now) { remote in
                let local = InterestFootstepStore.load(interest: trimmed, now: now)
                let merged = InterestFootstepLogic.merging(local + remote, now: now)
                InterestFootstepStore.save(merged, interest: trimmed, now: now)
                DispatchQueue.main.async {
                    completion(merged)
                }
            }
        }
    }

    private func flushPending(completion: @escaping () -> Void) {
        let pending = InterestFootstepStore.loadPending()
        guard pending.isEmpty == false else {
            completion()
            return
        }
        let group = DispatchGroup()
        var savedIDs = Set<String>()
        for sample in pending {
            group.enter()
            insert(sample) { result in
                if case .success = result {
                    savedIDs.insert(sample.id)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if savedIDs.isEmpty == false {
                InterestFootstepStore.removePending(ids: savedIDs)
            }
            completion()
        }
    }

    private func queryPublicTrail(
        interest: String,
        now: Date,
        completion: @escaping ([InterestFootstepLogic.Sample]) -> Void
    ) {
        let byInterest = CKQuery(
            recordType: InterestFootstep.recordType,
            predicate: NSPredicate(format: "interest == %@", interest)
        )
        byInterest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        perform(byInterest, interest: interest, now: now) { [weak self] samples, error in
            guard let self else {
                completion(samples)
                return
            }
            if error == nil {
                completion(samples)
                return
            }
            let unsorted = CKQuery(
                recordType: InterestFootstep.recordType,
                predicate: NSPredicate(format: "interest == %@", interest)
            )
            self.perform(unsorted, interest: interest, now: now) { samples, error in
                if error == nil {
                    completion(samples)
                    return
                }
                self.queryRecentTrail(interest: interest, now: now, completion: completion)
            }
        }
    }

    private func perform(
        _ query: CKQuery,
        interest: String,
        now: Date,
        completion: @escaping ([InterestFootstepLogic.Sample], Error?) -> Void
    ) {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        func runNext() {
            let operation = cursor.map { CKQueryOperation(cursor: $0) } ?? CKQueryOperation(query: query)
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.qualityOfService = .userInitiated
            operation.recordFetchedBlock = { records.append($0) }
            operation.queryCompletionBlock = { nextCursor, error in
                if let error {
                    if AccountDeletionLogic.isSkippableSchemaError(error) {
                        print("InterestFootstepService: schema not ready yet")
                    } else {
                        print("InterestFootstepService: fetch error \(error.localizedDescription)")
                    }
                    completion([], error)
                    return
                }
                cursor = nextCursor
                if nextCursor != nil, records.count < InterestFootstepLogic.maxStoredPings {
                    runNext()
                    return
                }
                let samples = records.compactMap { InterestFootstep(record: $0)?.sample }
                    .filter {
                        $0.interest.compare(interest, options: .caseInsensitive) == .orderedSame
                            && now.timeIntervalSince($0.timestamp) <= InterestFootstepLogic.maxAge
                    }
                completion(samples, nil)
            }
            publicDB.add(operation)
        }

        runNext()
    }

    /// If `interest` is not queryable yet, pull recent public pings and filter on device.
    private func queryRecentTrail(
        interest: String,
        now: Date,
        completion: @escaping ([InterestFootstepLogic.Sample]) -> Void
    ) {
        let since = now.addingTimeInterval(-InterestFootstepLogic.maxAge)
        let query = CKQuery(
            recordType: InterestFootstep.recordType,
            predicate: NSPredicate(format: "timestamp > %@", since as NSDate)
        )
        perform(query, interest: interest, now: now) { samples, _ in
            completion(samples)
        }
    }

    private func insert(
        _ sample: InterestFootstepLogic.Sample,
        completion: @escaping (Result<InterestFootstep, Error>) -> Void
    ) {
        let recordID = CKRecord.ID(recordName: sample.id)
        let footstep = InterestFootstep(
            interest: sample.interest,
            latitude: sample.latitude,
            longitude: sample.longitude,
            visitCount: sample.visitCount,
            timestamp: sample.timestamp,
            deviceID: sample.deviceID,
            userID: sample.userID,
            cellKey: sample.cellKey,
            recordID: recordID
        )
        publicDB.save(footstep.toCKRecord()) { saved, error in
            DispatchQueue.main.async {
                if let error {
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        completion(.success(footstep))
                        return
                    }
                    print("InterestFootstepService: save error \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                if let saved, let savedFootstep = InterestFootstep(record: saved) {
                    print("InterestFootstepService: saved \(savedFootstep.recordID.recordName)")
                    completion(.success(savedFootstep))
                } else {
                    print("InterestFootstepService: saved \(footstep.recordID.recordName)")
                    completion(.success(footstep))
                }
            }
        }
    }
}
