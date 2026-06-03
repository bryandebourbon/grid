import Foundation

/// Resolves chat and conversation titles from grid state (no CloudKit).
enum ProfileDisplayNameLogic {

    static func chatTitle(
        recipientDeviceID: String,
        currentDeviceID: String?,
        gridNodes: [[GridNode]]
    ) -> String {
        if recipientDeviceID == currentDeviceID {
            return "My Notes"
        }
        if let profile = profile(forDeviceID: recipientDeviceID, in: gridNodes) {
            return profile.displayName
        }
        return "Device \(String(recipientDeviceID.prefix(8)))"
    }

    static func profile(forDeviceID deviceID: String, in gridNodes: [[GridNode]]) -> UserProfile? {
        for row in gridNodes {
            for node in row {
                if let profile = node.userProfile, profile.deviceID == deviceID {
                    return profile
                }
            }
        }
        return nil
    }
}
