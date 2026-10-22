import CryptoKit
import Foundation

/// Ids for the fresh CloudKit container. Random ids are minted once.
/// Pair ids are stable so a second write updates the same row.
enum GridIdentityLogic {
    private static let namespace = Data([
        0xA6, 0xB4, 0xC2, 0xE0, 0x7F, 0x51, 0x4C, 0x1A,
        0x9D, 0x33, 0x0E, 0x5F, 0x1A, 0x2B, 0x3C, 0x4D
    ])

    enum AccountLookup: Equatable {
        case found(String)
        case missing
        case failed
    }

    /// Development has no Account type until the first save. That query error means create it.
    static func accountLookup(from error: Error) -> AccountLookup {
        let text = error.localizedDescription.lowercased()
        if text.contains("did not find record type")
            || text.contains("unknown record type")
            || text.contains("no such record type") {
            return .missing
        }
        return .failed
    }

    static func normalizeInterestName(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = collapsed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? nil : name
    }

    /// Remote id wins so two phones with one Apple ID share one account.
    /// A failed lookup reuses the id this phone already stored, and does not mint another.
    static func accountID(stored: String?, lookup: AccountLookup) -> (id: String, isNew: Bool)? {
        switch lookup {
        case .found(let remote):
            guard remote.isEmpty == false else { return minted(stored: stored) }
            return (remote, false)
        case .missing:
            return minted(stored: stored)
        case .failed:
            guard let stored, stored.isEmpty == false else { return nil }
            return (stored, false)
        }
    }

    static func deviceID(stored: String?) -> (id: String, isNew: Bool) {
        if let stored, stored.isEmpty == false { return (stored, false) }
        return (UUID().uuidString, true)
    }

    static func conversationID(accountA: String, accountB: String) -> String? {
        let pair = [accountA, accountB].filter { $0.isEmpty == false }.sorted()
        guard pair.count == 2, pair[0] != pair[1] else { return nil }
        return stableID(name: "conversation:\(pair[0])|\(pair[1])")
    }

    static func relationshipID(actorAccountID: String, targetAccountID: String) -> String? {
        guard actorAccountID.isEmpty == false, targetAccountID.isEmpty == false else { return nil }
        guard actorAccountID != targetAccountID else { return nil }
        return stableID(name: "relationship:\(actorAccountID)|\(targetAccountID)")
    }

    static func footstepID(interestID: String, cellKey: String) -> String? {
        guard interestID.isEmpty == false, cellKey.isEmpty == false else { return nil }
        return stableID(name: "footstep:\(interestID)|\(cellKey)")
    }

    static func accountInterestID(accountID: String, interestID: String) -> String? {
        guard accountID.isEmpty == false, interestID.isEmpty == false else { return nil }
        return stableID(name: "interest-link:\(accountID)|\(interestID)")
    }

    static func albumGrantID(ownerAccountID: String, viewerAccountID: String) -> String? {
        guard ownerAccountID.isEmpty == false, viewerAccountID.isEmpty == false else { return nil }
        guard ownerAccountID != viewerAccountID else { return nil }
        return stableID(name: "album-grant:\(ownerAccountID)|\(viewerAccountID)")
    }

    static func stableID(name: String) -> String {
        let digest = Array(Insecure.SHA1.hash(data: namespace + Data(name.utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let part: (Int, Int) -> String = { start, length in
            let from = hex.index(hex.startIndex, offsetBy: start)
            let to = hex.index(from, offsetBy: length)
            return String(hex[from..<to])
        }
        return "\(part(0, 8))-\(part(8, 4))-\(part(12, 4))-\(part(16, 4))-\(part(20, 12))".uppercased()
    }

    private static func minted(stored: String?) -> (id: String, isNew: Bool) {
        if let stored, stored.isEmpty == false { return (stored, false) }
        return (UUID().uuidString, true)
    }
}
