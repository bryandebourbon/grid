import Foundation

/// Deterministic grid used by UI tests. Enable with launch argument `gridUITestHarness`.
enum GridUITestHarness {
    static let argument = "gridUITestHarness"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
            || ProcessInfo.processInfo.environment["GRID_UI_TEST"] == "1"
    }

    static let me = UserProfile(
        userID: "grid.uitest.me",
        deviceID: "uitest-me-DEVICE",
        deviceName: "UI Test Me"
    )

    static let alice = UserProfile(
        userID: "grid.uitest.alice",
        deviceID: "uitest-alice-DEVICE",
        deviceName: "Alice UI"
    )

    static let bob = UserProfile(
        userID: "grid.uitest.bob",
        deviceID: "uitest-bob-DEVICE",
        deviceName: "Bob UI"
    )

    static var nearby: [UserProfile] { [me, alice, bob] }

    static let aliceMessageText = "alice-unique-ping"
    static let bobMessageText = "bob-unique-pong"

    static func cellIdentifier(for deviceID: String) -> String {
        "grid.cell.\(deviceID)"
    }

    static let chatTitleIdentifier = "chat.title"
    static let chatCloseIdentifier = "chat.close"
    static let chatComposerIdentifier = "chat.composer"
    static let chatMessageIdentifier = "chat.message"
    static let openMeIdentifier = "uitest.open.me"
    static let peopleTabAllIdentifier = "people.tab.all"
    static let peopleTabFavoritesIdentifier = "people.tab.favorites"
    static let peopleTabProbeIdentifier = "uitest.people.tab"
    static let settingsIdentifier = "settings.gear"
    static let partnerProbeIdentifier = "uitest.chat.partner"
}
