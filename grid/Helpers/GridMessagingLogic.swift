import Foundation

/// Client-side messaging gate before proximity rules (block is checked first).
enum GridMessagingLogic {

    static func canMessage(isBlocked: Bool, proximityAllowed: Bool, proximityReason: String) -> (allowed: Bool, reason: String) {
        if isBlocked {
            return (false, "You have blocked this user")
        }
        return (proximityAllowed, proximityReason)
    }
}
