import Foundation
import CloudKit

/// On-disk photo bytes so chat images and albums are downloaded once.
enum PhotoDiskCache {
    enum Kind: String {
        case message
        case album
    }

    static var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("grid/photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func safeID(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func url(kind: Kind, id: String) -> URL {
        rootURL
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent("\(safeID(id)).jpg")
    }

    static func load(kind: Kind, id: String) -> Data? {
        let file = url(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? Data(contentsOf: file)
    }

    static func save(kind: Kind, id: String, data: Data) {
        let file = url(kind: kind, id: id)
        let folder = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try? data.write(to: file, options: .atomic)
    }
}

enum AlbumCacheLogic {
    static func storyIDs(in metadata: [PhotoMetadata]) -> [String] {
        metadata.map(\.storyID)
    }

    static func needsRefresh(cachedIDs: [String], incomingIDs: [String]) -> Bool {
        cachedIDs != incomingIDs
    }
}

enum AlbumCacheStore {
    private struct PersistedAlbum: Codable {
        var id: String
        var ownerUserID: String
        var ownerDeviceID: String
        var title: String
        var createdDate: Date
        var recordName: String
        var photoMetadata: [PhotoMetadata]
    }

    static func albumDirectory(deviceID: String) -> URL {
        PhotoDiskCache.rootURL
            .appendingPathComponent(PhotoDiskCache.Kind.album.rawValue, isDirectory: true)
            .appendingPathComponent(PhotoDiskCache.safeID(deviceID), isDirectory: true)
    }

    static func photoURL(deviceID: String, storyID: String) -> URL {
        albumDirectory(deviceID: deviceID)
            .appendingPathComponent("\(PhotoDiskCache.safeID(storyID)).jpg")
    }

    static func loadAll() -> [String: Album] {
        let root = PhotoDiskCache.rootURL.appendingPathComponent(PhotoDiskCache.Kind.album.rawValue, isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [:] }
        var result: [String: Album] = [:]
        for folder in folders where folder.hasDirectoryPath {
            if let album = load(deviceID: folder.lastPathComponent) {
                result[album.ownerDeviceID] = album
            }
        }
        return result
    }

    static func load(deviceID: String) -> Album? {
        let file = albumDirectory(deviceID: deviceID).appendingPathComponent("album.json")
        guard let data = try? Data(contentsOf: file),
              let persisted = try? JSONDecoder().decode(PersistedAlbum.self, from: data) else {
            return nil
        }
        var photos: [CKAsset] = []
        var metadata: [PhotoMetadata] = []
        for item in persisted.photoMetadata {
            let url = photoURL(deviceID: persisted.ownerDeviceID, storyID: item.storyID)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            photos.append(CKAsset(fileURL: url))
            metadata.append(item)
        }
        return Album(
            id: persisted.id,
            ownerUserID: persisted.ownerUserID,
            ownerDeviceID: persisted.ownerDeviceID,
            title: persisted.title,
            createdDate: persisted.createdDate,
            pinnedPhotos: photos,
            photoMetadata: metadata,
            recordID: CKRecord.ID(recordName: persisted.recordName)
        )
    }

    @discardableResult
    static func save(_ album: Album) -> Album {
        let dir = albumDirectory(deviceID: album.ownerDeviceID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var photos: [CKAsset] = []
        var metadata: [PhotoMetadata] = []
        for (index, item) in album.photoMetadata.enumerated() {
            let dest = photoURL(deviceID: album.ownerDeviceID, storyID: item.storyID)
            let source = index < album.pinnedPhotos.count ? album.pinnedPhotos[index].fileURL : nil
            if let source, FileManager.default.fileExists(atPath: source.path), source.path != dest.path {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: source, to: dest)
            }
            guard FileManager.default.fileExists(atPath: dest.path) else { continue }
            photos.append(CKAsset(fileURL: dest))
            metadata.append(item)
        }

        let keep = Set(metadata.map { "\(PhotoDiskCache.safeID($0.storyID)).jpg" } + ["album.json"])
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where !keep.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let persisted = PersistedAlbum(
            id: album.id,
            ownerUserID: album.ownerUserID,
            ownerDeviceID: album.ownerDeviceID,
            title: album.title,
            createdDate: album.createdDate,
            recordName: album.recordID?.recordName ?? album.id,
            photoMetadata: metadata
        )
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: dir.appendingPathComponent("album.json"), options: .atomic)
        }

        return Album(
            id: album.id,
            ownerUserID: album.ownerUserID,
            ownerDeviceID: album.ownerDeviceID,
            title: album.title,
            createdDate: album.createdDate,
            pinnedPhotos: photos,
            photoMetadata: metadata,
            recordID: album.recordID ?? CKRecord.ID(recordName: album.id)
        )
    }
}
