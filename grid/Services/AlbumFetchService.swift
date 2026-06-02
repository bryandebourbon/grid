import Foundation
import CloudKit

/// CloudKit album lookup; keeps CK queries out of `GridViewModel`.
final class AlbumFetchService {
    private let publicDB: CKDatabase

    init(publicDB: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = publicDB
    }

    func fetchAlbum(ownerDeviceID: String) async -> Album? {
        let predicate = NSPredicate(format: "ownerDeviceID == %@", ownerDeviceID)
        let query = CKQuery(recordType: "Albums", predicate: predicate)

        do {
            let result = try await publicDB.records(matching: query)
            let records = result.matchResults.compactMap { try? $0.1.get() }
            guard let record = records.first else { return nil }
            return Album(record: record)
        } catch {
            print("AlbumFetchService: fetch failed for \(ownerDeviceID): \(error.localizedDescription)")
            return nil
        }
    }
}
