import Foundation

/// Notifications stay silent until the user actually chats.
enum NotificationPermissionLogic {
    static let requestedDefaultsKey = "grid.didRequestNotificationPermission"

    enum ChatEvent: Equatable {
        case sent(isLLM: Bool)
        case received(fromCurrentUser: Bool, isLLM: Bool)
    }

    static func shouldRequest(alreadyRequested: Bool, event: ChatEvent) -> Bool {
        guard !alreadyRequested else { return false }
        switch event {
        case .sent(let isLLM):
            return !isLLM
        case .received(let fromCurrentUser, let isLLM):
            return !fromCurrentUser && !isLLM
        }
    }
}
