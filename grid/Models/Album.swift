import Foundation
import CloudKit

// MARK: - PhotoMetadata

struct PhotoMetadata: Codable, Identifiable {
    let id: String
    let originalStoryDate: Date
    let caption: String?
    let pinnedDate: Date
    let storyID: String // Reference back to original story
    
    init(storyID: String, originalStoryDate: Date, caption: String? = nil, pinnedDate: Date = Date()) {
        self.id = UUID().uuidString
        self.storyID = storyID
        self.originalStoryDate = originalStoryDate
        self.caption = caption
        self.pinnedDate = pinnedDate
    }
}

// MARK: - Album

struct Album: Identifiable {
    let id: String
    let ownerUserID: String
    let ownerDeviceID: String
    var title: String
    let createdDate: Date
    var pinnedPhotos: [CKAsset]
    var photoMetadata: [PhotoMetadata]
    var recordID: CKRecord.ID?
    
    // Constants
    static let maxPhotos = 3
    
    // Computed properties
    var photosCount: Int {
        return pinnedPhotos.count
    }
    
    var hasSpace: Bool {
        return photosCount < Album.maxPhotos
    }
    
    // MARK: - Initializers
    
    // Create new album
    init(ownerUserID: String, ownerDeviceID: String, title: String = "My Album") {
        self.id = UUID().uuidString
        self.ownerUserID = ownerUserID
        self.ownerDeviceID = ownerDeviceID
        self.title = title
        self.createdDate = Date()
        self.pinnedPhotos = []
        self.photoMetadata = []
        self.recordID = CKRecord.ID(recordName: self.id)
    }
    
    // Initialize from CloudKit record
    init?(record: CKRecord) {
        guard let ownerUserID = record["ownerUserID"] as? String,
              let ownerDeviceID = record["ownerDeviceID"] as? String,
              let title = record["title"] as? String,
              let createdDate = record["createdDate"] as? Date else {
            print("Album init from CKRecord failed: Missing required fields")
            return nil
        }
        
        self.id = record.recordID.recordName
        self.ownerUserID = ownerUserID
        self.ownerDeviceID = ownerDeviceID
        self.title = title
        self.createdDate = createdDate
        self.pinnedPhotos = record["pinnedPhotos"] as? [CKAsset] ?? []
        self.recordID = record.recordID
        
        // Parse photoMetadata from JSON string
        if let metadataString = record["photoMetadata"] as? String,
           let metadataData = metadataString.data(using: .utf8) {
            do {
                self.photoMetadata = try JSONDecoder().decode([PhotoMetadata].self, from: metadataData)
            } catch {
                print("Album: Failed to decode photoMetadata: \(error)")
                self.photoMetadata = []
            }
        } else {
            self.photoMetadata = []
        }
    }
    
    // MARK: - CloudKit Conversion
    
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Albums", recordID: recordID ?? CKRecord.ID(recordName: id))
        
        record["ownerUserID"] = ownerUserID
        record["ownerDeviceID"] = ownerDeviceID
        record["title"] = title
        record["createdDate"] = createdDate
        record["pinnedPhotos"] = pinnedPhotos
        
        // Encode photoMetadata as JSON string
        do {
            let metadataData = try JSONEncoder().encode(photoMetadata)
            record["photoMetadata"] = String(data: metadataData, encoding: .utf8) ?? "[]"
        } catch {
            print("Album: Failed to encode photoMetadata: \(error)")
            record["photoMetadata"] = "[]"
        }
        
        return record
    }
    
    // MARK: - Album Management
    
    mutating func addPhoto(asset: CKAsset, metadata: PhotoMetadata) -> Bool {
        guard hasSpace else {
            print("Album: Cannot add photo - album is full (\(Album.maxPhotos) max)")
            return false
        }
        
        // Check if story is already pinned
        if photoMetadata.contains(where: { $0.storyID == metadata.storyID }) {
            print("Album: Story \(metadata.storyID) is already pinned")
            return false
        }
        
        pinnedPhotos.append(asset)
        photoMetadata.append(metadata)
        
        print("Album: Added photo. Count: \(photosCount)/\(Album.maxPhotos)")
        return true
    }
    
    mutating func removePhoto(storyID: String) -> Bool {
        guard let index = photoMetadata.firstIndex(where: { $0.storyID == storyID }) else {
            print("Album: Story \(storyID) not found in album")
            return false
        }
        
        // Remove both the asset and metadata at the same index
        pinnedPhotos.remove(at: index)
        photoMetadata.remove(at: index)
        
        print("Album: Removed photo. Count: \(photosCount)/\(Album.maxPhotos)")
        return true
    }
    
    func isPhotoPinned(storyID: String) -> Bool {
        return photoMetadata.contains(where: { $0.storyID == storyID })
    }
    
    func getPhotoMetadata(storyID: String) -> PhotoMetadata? {
        return photoMetadata.first(where: { $0.storyID == storyID })
    }
    
    // MARK: - Album Info
    
    var albumDescription: String {
        let photoText = photosCount == 1 ? "photo" : "photos"
        return "\(photosCount) \(photoText)"
    }
    
    var isOwnedBy: (String) -> Bool {
        return { deviceID in
            return self.ownerDeviceID == deviceID
        }
    }
}

// MARK: - Album Extensions

extension Album: Equatable {
    static func == (lhs: Album, rhs: Album) -> Bool {
        return lhs.id == rhs.id
    }
}

extension Album: CustomStringConvertible {
    var description: String {
        return "Album(id: \(id), owner: \(ownerDeviceID), title: \(title), photos: \(photosCount))"
    }
}

// MARK: - Album Result Types

struct AlbumResult {
    let album: Album?
    let success: Bool
    let error: String?
    
    static func success(_ album: Album) -> AlbumResult {
        return AlbumResult(album: album, success: true, error: nil)
    }
    
    static func failure(_ error: String) -> AlbumResult {
        return AlbumResult(album: nil, success: false, error: error)
    }
}

struct PinResult {
    let success: Bool
    let error: String?
    let albumFull: Bool
    let alreadyPinned: Bool
    
    static func success() -> PinResult {
        return PinResult(success: true, error: nil, albumFull: false, alreadyPinned: false)
    }
    
    static func failure(_ error: String) -> PinResult {
        return PinResult(success: false, error: error, albumFull: false, alreadyPinned: false)
    }
    
    static func albumFull() -> PinResult {
        return PinResult(success: false, error: "Album is full", albumFull: true, alreadyPinned: false)
    }
    
    static func alreadyPinned() -> PinResult {
        return PinResult(success: false, error: "Story already pinned", albumFull: false, alreadyPinned: true)
    }
} 