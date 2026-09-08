import Foundation

/// One person on Grid is one CloudKit `UserProfiles` record.
/// `deviceID` is that record name and the only key for cells, chats, and banners.
enum PersonIdentity {
    static func id(forDeviceID deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cellID(profile: UserProfile?, x: Int, y: Int) -> String {
        if let deviceID = profile?.deviceID {
            let id = Self.id(forDeviceID: deviceID)
            if id.isEmpty == false { return id }
        }
        return emptySlotID(x: x, y: y)
    }

    static func emptySlotID(x: Int, y: Int) -> String {
        "empty-\(x)-\(y)"
    }
}
