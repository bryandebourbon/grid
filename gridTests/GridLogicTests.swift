import Testing
import Foundation
@testable import grid

// MARK: - Grid column zoom logic

struct GridColumnZoomLogicTests {

    private func expectedPreviewColumns(base: Int, scale: CGFloat) -> Int {
        let delta = Int((1.0 - scale) / 0.25)
        return max(2, min(5, base + delta))
    }

    @Test func doubleTapCyclesThreeTwoFive() {
        #expect(GridColumnZoomLogic.nextDoubleTapTarget(from: 3) == 2)
        #expect(GridColumnZoomLogic.nextDoubleTapTarget(from: 2) == 5)
        #expect(GridColumnZoomLogic.nextDoubleTapTarget(from: 5) == 3)
        #expect(GridColumnZoomLogic.nextDoubleTapTarget(from: 4) == 3)
    }

    @Test func previewColumnsMatchesPinchFormulaAndClamps() {
        for (base, scale) in [(3, 1.0), (3, 0.5), (3, 1.5), (5, 0.0), (2, 2.0), (3, 3.0)] as [(Int, CGFloat)] {
            #expect(GridColumnZoomLogic.previewColumns(base: base, scale: scale) == expectedPreviewColumns(base: base, scale: scale))
        }
    }

    @Test func clampNeverExceedsGridBounds() {
        #expect(GridColumnZoomLogic.clamp(1) == 2)
        #expect(GridColumnZoomLogic.clamp(99) == 5)
    }

    @Test func dragTranslationChangesColumns() {
        #expect(GridColumnZoomLogic.columnsAfterDrag(base: 3, verticalTranslation: -100) == 4)
        #expect(GridColumnZoomLogic.columnsAfterDrag(base: 3, verticalTranslation: 100) == 2)
        #expect(GridColumnZoomLogic.columnsAfterDrag(base: 2, verticalTranslation: -500) == 5)
    }

    @Test func fastSwipeIgnored() {
        #expect(GridColumnZoomLogic.shouldIgnoreDrag(velocity: 401))
        #expect(!GridColumnZoomLogic.shouldIgnoreDrag(velocity: 400))
    }
}

// MARK: - Message conversation logic

struct MessageConversationLogicTests {

    private func message(
        id: String,
        from sender: String,
        to recipient: String,
        text: String,
        at timestamp: Date
    ) -> Message {
        Message(
            id: id,
            senderDeviceID: sender,
            recipientDeviceID: recipient,
            senderUserID: "u-\(sender)",
            recipientUserID: "u-\(recipient)",
            text: text,
            timestamp: timestamp,
            status: .sent
        )
    }

    @Test func messagesFiltersAndSortsThread() {
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 200)
        let t2 = Date(timeIntervalSince1970: 300)
        let all = [
            message(id: "a", from: "me", to: "bob", text: "hi", at: t1),
            message(id: "b", from: "carol", to: "me", text: "?", at: t2),
            message(id: "c", from: "me", to: "bob", text: "later", at: t0),
            message(id: "d", from: "me", to: "dave", text: "other", at: t1),
        ]

        let thread = MessageConversationLogic.messages(
            inConversationWith: "bob",
            currentDeviceID: "me",
            from: all
        )

        #expect(thread.map(\.id) == ["c", "a"])
    }

    @Test func conversationListUsesMyNotesForSelfThread() {
        let t0 = Date(timeIntervalSince1970: 100)
        let messages = [
            message(id: "n", from: "me", to: "me", text: "note", at: t0),
        ]

        let list = MessageConversationLogic.conversationList(
            currentDeviceID: "me",
            messages: messages,
            displayNameLookup: { _ in "Should Not Use" }
        )

        #expect(list.count == 1)
        #expect(list[0].displayName == "My Notes")
        #expect(list[0].deviceID == "me")
        #expect(list[0].messageCount == 1)
    }

    @Test func conversationListSortsByMostRecentLastMessage() {
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 500)
        let messages = [
            message(id: "1", from: "me", to: "alice", text: "a", at: old),
            message(id: "2", from: "bob", to: "me", text: "b", at: recent),
            message(id: "3", from: "me", to: "carol", text: "c", at: Date(timeIntervalSince1970: 200)),
        ]

        let list = MessageConversationLogic.conversationList(
            currentDeviceID: "me",
            messages: messages,
            displayNameLookup: { id in "User \(id)" }
        )

        #expect(list.map(\.deviceID) == ["bob", "carol", "alice"])
        #expect(list[0].lastMessage?.id == "2")
        #expect(list[0].messageCount == 1)
    }
}

// MARK: - Grid profile filter logic

struct GridProfileFilterLogicTests {

    private func profile(userID: String, deviceID: String, interests: [Interest] = []) -> UserProfile {
        UserProfile(userID: userID, deviceID: deviceID, deviceName: deviceID, interests: interests)
    }

    @Test func partitionSeparatesCurrentUser() {
        let profiles = [
            profile(userID: "u-me", deviceID: "me"),
            profile(userID: "u-a", deviceID: "a"),
        ]
        let result = GridProfileFilterLogic.partition(profiles: profiles, currentUserDeviceID: "me")
        #expect(result.currentUser?.deviceID == "me")
        #expect(result.others.map(\.deviceID) == ["a"])
    }

    @Test func applyDisplayFiltersRemovesBlockedUsers() {
        let profiles = [
            profile(userID: "blocked", deviceID: "b1"),
            profile(userID: "ok", deviceID: "o1"),
        ]
        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            blockedUserIDs: ["blocked"],
            usersWhoBlockedMe: [],
            selectedInterestFilter: []
        )
        #expect(filtered.map(\.userID) == ["ok"])
    }

    @Test func applyDisplayFiltersRemovesUsersWhoBlockedMe() {
        let profiles = [profile(userID: "hostile", deviceID: "h1")]
        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            blockedUserIDs: [],
            usersWhoBlockedMe: ["hostile"],
            selectedInterestFilter: []
        )
        #expect(filtered.isEmpty)
    }

    @Test func applyDisplayFiltersBlockAndInterestsCombined() {
        let profiles = [
            profile(userID: "star", deviceID: "s1", interests: [.music]),
            profile(userID: "blocked", deviceID: "b1"),
            profile(userID: "match", deviceID: "m1", interests: [.foodie]),
            profile(userID: "nomatch", deviceID: "n1", interests: [.running]),
        ]

        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            blockedUserIDs: ["blocked"],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [.foodie]
        )

        #expect(filtered.map(\.userID) == ["match"])
    }
}

// MARK: - Interest matching logic

struct InterestMatchingLogicTests {

    @Test func sharedCountAndSortedList() {
        let mine: [Interest] = [.music, .foodie, .running]
        let theirs: [Interest] = [.foodie, .music, .travel]
        #expect(InterestMatchingLogic.sharedCount(myInterests: mine, theirInterests: theirs) == 2)
        #expect(InterestMatchingLogic.sharedInterests(myInterests: mine, theirInterests: theirs) == [.foodie, .music])
    }
}

// MARK: - Message read logic

struct MessageReadLogicTests {

    @Test func unreadCountExcludesReadReceipts() {
        let messages = [
            Message(id: "1", senderDeviceID: "bob", recipientDeviceID: "me", senderUserID: "u1", recipientUserID: "u2", text: "a", status: .received),
            Message(id: "2", senderDeviceID: "bob", recipientDeviceID: "me", senderUserID: "u1", recipientUserID: "u2", text: "b", status: .received),
            Message(id: "3", senderDeviceID: "me", recipientDeviceID: "bob", senderUserID: "u2", recipientUserID: "u1", text: "c", status: .sent),
        ]
        #expect(MessageReadLogic.unreadCount(from: "bob", currentDeviceID: "me", messages: messages, readReceipts: ["1"]) == 1)
        #expect(MessageReadLogic.unreadCount(from: "bob", currentDeviceID: "me", messages: messages, readReceipts: ["1", "2"]) == 0)
        #expect(MessageReadLogic.unreadCount(from: "carol", currentDeviceID: "me", messages: messages, readReceipts: []) == 0)
    }
}

// MARK: - Grid placement logic

struct GridPlacementLogicTests {

    @Test func placesInFirstEmptySlotSkippingOrigin() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 3)
        let profile = UserProfile(userID: "u", deviceID: "d", deviceName: "n")
        guard let slot = GridPlacementLogic.firstEmptySlot(in: grid, skipping: (0, 0)) else {
            Issue.record("expected slot")
            return
        }
        #expect(slot.row == 0 && slot.col == 1)
        GridPlacementLogic.place(profile: profile, in: &grid, at: slot.row, col: slot.col)
        #expect(grid[0][1].userProfile?.deviceID == "d")
        #expect(grid[0][0].userProfile == nil)
    }
}

// MARK: - Distance format logic

struct DistanceFormatLogicTests {

    @Test func formatsSubKilometerWithoutLeadingZero() {
        #expect(DistanceFormatLogic.format(meters: 50) == ".05km")
        #expect(DistanceFormatLogic.format(meters: 230) == ".23km")
    }

    @Test func clampsVerySmallAndVeryLarge() {
        #expect(DistanceFormatLogic.format(meters: 1) == ".01km")
        #expect(DistanceFormatLogic.format(meters: 120_000) == "99km")
    }

    @Test func formatsWholeKilometers() {
        #expect(DistanceFormatLogic.format(meters: 5_000) == "5km")
        #expect(DistanceFormatLogic.format(meters: 25_000) == "25km")
    }
}

// MARK: - Grid messaging logic

// MARK: - Profile display name logic

struct ProfileDisplayNameLogicTests {

    private func gridWithPeer(deviceID: String, deviceName: String) -> [[GridNode]] {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 3)
        let profile = UserProfile(userID: "user-\(deviceID)", deviceID: deviceID, deviceName: deviceName)
        GridPlacementLogic.place(profile: profile, in: &grid, at: 0, col: 1)
        return grid
    }

    @Test func selfChatUsesMyNotes() {
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "me-device",
            currentDeviceID: "me-device",
            gridNodes: []
        )
        #expect(title == "My Notes")
    }

    @Test func usesProfileDisplayNameWhenOnGrid() {
        let grid = gridWithPeer(deviceID: "bob-device", deviceName: "Bob Phone")
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "bob-device",
            currentDeviceID: "me-device",
            gridNodes: grid
        )
        #expect(title == "Bob Phone (user-bob...)")
    }

    @Test func fallsBackToDevicePrefixWhenMissing() {
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "abcdefgh-xyz",
            currentDeviceID: "me-device",
            gridNodes: GridPlacementLogic.makeEmptyGrid(size: 2)
        )
        #expect(title == "Device abcdefgh")
    }

    @Test func findsProfileInGrid() {
        let grid = gridWithPeer(deviceID: "d1", deviceName: "Test")
        let found = ProfileDisplayNameLogic.profile(forDeviceID: "d1", in: grid)
        #expect(found?.deviceID == "d1")
        #expect(ProfileDisplayNameLogic.profile(forDeviceID: "missing", in: grid) == nil)
    }
}

struct GridMessagingLogicTests {

    @Test func blockedUserCannotMessage() {
        let result = GridMessagingLogic.canMessage(
            isBlocked: true,
            proximityAllowed: true,
            proximityReason: "Ready to message"
        )
        #expect(result.allowed == false)
        #expect(result.reason == "You have blocked this user")
    }

    @Test func proximityRulesApplyWhenNotBlocked() {
        let denied = GridMessagingLogic.canMessage(isBlocked: false, proximityAllowed: false, proximityReason: "Too far")
        #expect(denied == (false, "Too far"))

        let allowed = GridMessagingLogic.canMessage(isBlocked: false, proximityAllowed: true, proximityReason: "Ready to message")
        #expect(allowed == (true, "Ready to message"))
    }
}
