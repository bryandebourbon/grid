import Foundation

/// Local read IDs so opening a chat stays read if CloudKit receipts lag or fail.
enum ReadReceiptStore {
    private static let lock = NSLock()
    private static let fileName = "read-receipts.json"

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("grid", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(fileName)
    }

    static func load(from url: URL = fileURL) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    static func save(_ ids: Set<String>, to url: URL = fileURL) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(Array(ids).sorted()) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
