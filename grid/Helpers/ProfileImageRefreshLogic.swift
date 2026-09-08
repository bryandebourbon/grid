import Foundation
import CloudKit

/// Decides when a locally picked profile photo should win over a CloudKit copy.
enum ProfileImageRefreshLogic {
    static func shouldKeepLocalPhoto(localURL: URL?, savedURL: URL?) -> Bool {
        guard let localURL, FileManager.default.fileExists(atPath: localURL.path) else { return false }
        guard let savedURL else { return true }
        if savedURL.path == localURL.path { return false }
        return FileManager.default.fileExists(atPath: savedURL.path) == false
    }

    static func loadKey(for asset: CKAsset?) -> String {
        fingerprint(url: asset?.fileURL)
    }

    static func fingerprint(url: URL?) -> String {
        guard let url else { return "none" }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(mtime)"
    }
}
