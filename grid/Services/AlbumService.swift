import Foundation
import CloudKit

/// CloudKit album create/fetch/pin operations (kept out of `GridViewModel`).
final class AlbumService {
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
            print("AlbumService: fetch failed for \(ownerDeviceID): \(error.localizedDescription)")
            return nil
        }
    }

    func createAlbum(for profile: UserProfile) async -> AlbumResult {
        let album = Album(ownerUserID: profile.userID, ownerDeviceID: profile.deviceID)
        do {
            let savedRecord = try await publicDB.save(album.toCKRecord())
            guard let savedAlbum = Album(record: savedRecord) else {
                return .failure("Failed to create album from saved record")
            }
            return .success(savedAlbum)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func saveAlbum(_ album: Album) async -> AlbumResult {
        do {
            let saved = try await saveWithModifyRecords(album.toCKRecord())
            guard let savedAlbum = Album(record: saved) else {
                return .failure("Failed to parse saved album")
            }
            return .success(savedAlbum)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func pinStory(_ story: Story, to album: inout Album) -> PinResult {
        guard let imageAsset = story.imageAsset else {
            return .failure("Story has no image asset")
        }
        if !album.hasSpace { return .albumFull() }
        if album.isPhotoPinned(storyID: story.id) { return .alreadyPinned() }

        let metadata = PhotoMetadata(
            storyID: story.id,
            originalStoryDate: story.timestamp,
            caption: story.caption
        )
        guard album.addPhoto(asset: imageAsset, metadata: metadata) else {
            return .failure("Failed to add photo to album")
        }
        return .success()
    }

    func unpinStory(_ story: Story, from album: inout Album) -> PinResult {
        guard album.removePhoto(storyID: story.id) else {
            return .failure("Story not found in album")
        }
        return .success()
    }

    private func saveWithModifyRecords(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            var savedRecord: CKRecord?
            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result { savedRecord = record }
            }
            operation.modifyRecordsCompletionBlock = { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AlbumService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No record returned"]
                    ))
                }
            }
            publicDB.add(operation)
        }
    }
}
