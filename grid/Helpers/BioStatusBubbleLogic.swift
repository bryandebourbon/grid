import Foundation

enum BioStatusBubbleLogic {
    static let placeholder = "What's going on?"
    static let baseFontSize: CGFloat = 13
    static let fontStep: CGFloat = 2

    /// Default grid is 3 columns. Each zoom-out step shrinks the status by 2pt; zoom-in adds it back.
    static func fontSize(forGridColumns columns: Int) -> CGFloat {
        let delta = GridColumnZoomLogic.clamp(columns) - 3
        return max(9, baseFontSize - CGFloat(delta) * fontStep)
    }

    static func content(bio: String?, isMe _: Bool) -> (text: String, isPlaceholder: Bool)? {
        let trimmed = bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return nil }
        return (trimmed, false)
    }
}
