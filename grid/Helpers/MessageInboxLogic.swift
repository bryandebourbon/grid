import Foundation

/// Merge rules for the on-device inbox.
///
/// The inbox file is the source of truth after the first download. Refresh only
/// asks CloudKit for records newer than the newest local timestamp. CloudKit
/// public-database *queries* are eventually consistent, so a just-saved message
/// can be missing from `CKQuery` for minutes even though the push (record-ID
/// fetch) already has it. Never replace the local inbox with a query.
enum MessageInboxLogic {
    static func merge(local: [Message], incoming: [Message]) -> [Message] {
        var byID: [String: Message] = [:]
        byID.reserveCapacity(local.count + incoming.count)
        for message in local {
            byID[message.id] = message
        }
        for message in incoming {
            if let existing = byID[message.id], shouldKeepLocal(existing, incoming: message) {
                continue
            }
            if let existing = byID[message.id] {
                var merged = message
                merged.reactions = MessageReactionLogic.pick(local: existing, incoming: message)
                merged.reactionsUpdatedAt = MessageReactionLogic.pickUpdatedAt(local: existing, incoming: message)
                byID[message.id] = merged
            } else {
                byID[message.id] = message
            }
        }
        return byID.values.sorted { $0.timestamp < $1.timestamp }
    }

    /// In-flight optimistic sends must not be clobbered by a stale duplicate.
    static func shouldKeepLocal(_ existing: Message, incoming: Message) -> Bool {
        (existing.status == .sending || existing.status == .failed)
            && incoming.status != .sent
            && incoming.status != .received
    }

    static let deltaOverlap: TimeInterval = 90

    /// `nil` means the inbox is empty and a one-time full download is needed.
    static func querySince(newestLocal: Date?) -> Date? {
        newestLocal?.addingTimeInterval(-deltaOverlap)
    }

    static func hasNewOrChanged(local: [Message], incoming: [Message]) -> Bool {
        guard incoming.isEmpty == false else { return false }
        let byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for message in incoming {
            guard let existing = byID[message.id] else { return true }
            if shouldKeepLocal(existing, incoming: message) { continue }
            if existing.status != message.status { return true }
            if existing.reactionsUpdatedAt != message.reactionsUpdatedAt { return true }
            if existing.reactions != message.reactions { return true }
        }
        return false
    }

    static func persistable(_ messages: [Message]) -> [Message] {
        messages.filter { message in
            !LocalLLMIdentity.involves(message) && message.status != .sending
        }
    }
}

enum PendingMessageFetchStore {
    static let defaultsKey = "grid.pendingMessageRecordNames"

    static func enqueue(_ recordName: String, defaults: UserDefaults = .standard) {
        let trimmed = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var names = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
        names.insert(trimmed)
        defaults.set(Array(names), forKey: defaultsKey)
    }

    static func all(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    static func remove(_ recordName: String, defaults: UserDefaults = .standard) {
        var names = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
        names.remove(recordName)
        defaults.set(Array(names), forKey: defaultsKey)
    }
}
