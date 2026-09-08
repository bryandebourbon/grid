import Foundation

/// Durable inbox so a push-fetched message survives process death and stale CloudKit queries.
enum MessageInboxStore {
    private static let lock = NSLock()
    private static let fileName = "message-inbox.json"

    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("grid", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(fileName)
    }

    static func load(from url: URL = fileURL) -> [Message] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    static func save(_ messages: [Message], to url: URL = fileURL) {
        let persistable = MessageInboxLogic.persistable(messages)
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(persistable) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func upsert(_ message: Message, url: URL = fileURL) {
        var current = load(from: url)
        current = MessageInboxLogic.merge(local: current, incoming: [message])
        save(current, to: url)
    }
}
