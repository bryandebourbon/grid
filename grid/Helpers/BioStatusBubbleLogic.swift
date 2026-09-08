import Foundation

enum BioStatusBubbleLogic {
    static let placeholder = "What's going on?"

    static func content(bio: String?, isMe: Bool) -> (text: String, isPlaceholder: Bool)? {
        let trimmed = bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return (trimmed, false) }
        if isMe { return (placeholder, true) }
        return nil
    }
}
