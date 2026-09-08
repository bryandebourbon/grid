import Testing
import Foundation
import CloudKit
import CoreLocation
@testable import grid

// MARK: - Grid column zoom logic

struct GridCellLayoutTests {
    @Test func portraitIsSixteenTenthsTall() {
        #expect(GridCellLayout.portraitHeightToWidth == 1.6)
        #expect(GridCellLayout.gutter == 8)
        #expect(GridCellLayout.cornerRadius == 14)
        #expect(GridCellLayout.widthOverHeight(square: false) == 1 / 1.6)
        #expect(GridCellLayout.widthOverHeight(square: true) == 1)
    }

    @Test func bioBubbleUsesStatusTextAndMePlaceholder() {
        #expect(BioStatusBubbleLogic.fontSize(forGridColumns: 3) == 13)
        #expect(BioStatusBubbleLogic.fontSize(forGridColumns: 4) == 11)
        #expect(BioStatusBubbleLogic.fontSize(forGridColumns: 5) == 9)
        #expect(BioStatusBubbleLogic.fontSize(forGridColumns: 2) == 15)
        #expect(BioStatusBubbleLogic.content(bio: "Hangover", isMe: false)?.text == "Hangover")
        #expect(BioStatusBubbleLogic.content(bio: "  ", isMe: false) == nil)
        #expect(BioStatusBubbleLogic.content(bio: nil, isMe: true) == nil)
        #expect(BioStatusBubbleLogic.content(bio: "  ", isMe: true) == nil)
        #expect(BioStatusBubbleLogic.content(bio: "Out", isMe: true)?.isPlaceholder == false)
    }

    @Test func photoShapeCyclesCardSquareCircle() {
        #expect(GridPhotoShape.card.next == .square)
        #expect(GridPhotoShape.square.next == .circle)
        #expect(GridPhotoShape.circle.next == .card)
        #expect(GridPhotoShape.card.usesSquareProportion == false)
        #expect(GridPhotoShape.square.usesSquareProportion)
        #expect(GridPhotoShape.circle.usesCircleClip)
    }
}

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

    @Test func pinchReflowsStoredFiveByFiveWithoutDroppingCells() {
        let grid = GridPlacementLogic.makeEmptyGrid()
        let rows = GridColumnZoomLogic.rows(from: grid, columns: 3)
        #expect(rows.flatMap { $0 }.count == 25)
        #expect(rows.count == 9)
        #expect(rows.first?.count == 3)
        #expect(rows.last?.count == 1)
    }

    @Test func selfStaysOffTheGridUntilLocationIsGranted() {
        #expect(!LocationOnboardingLogic.shouldShowNearbyPeople(status: .notDetermined))
        #expect(LocationOnboardingLogic.shouldShowNearbyPeople(status: .authorizedWhenInUse))
    }

    @Test func leftoverDebugPeerIsHidden() {
        let peer = UserProfile(
            userID: "grid.test-peer.debug",
            deviceID: "grid.test-peer.debug-DEVICE",
            deviceName: "TP",
            bio: "Simulator test peer"
        )
        let person = UserProfile(userID: "u", deviceID: "me", deviceName: "Me")
        let harnessMe = GridUITestHarness.me
        #expect(GridPresenceLogic.isLeftoverDebugPeer(peer))
        #expect(!GridPresenceLogic.shouldShowPeer(peer))
        #expect(GridPresenceLogic.isLeftoverDebugPeer(harnessMe))
        #expect(GridPresenceLogic.isLeftoverDebugPeer(GridUITestHarness.alice))
        #expect(!GridPresenceLogic.shouldShowPeer(harnessMe))
        #expect(!GridPresenceLogic.isLeftoverDebugPeer(person))
        #expect(GridPresenceLogic.shouldShowPeer(person))
        #expect(InitialsAvatarLogic.initials(from: "Test Peer") == "TP")
        #expect(InitialsAvatarLogic.initials(from: "Bryan") == "BR")
        #expect(InitialsAvatarLogic.initials(from: "Josh B") == "JB")
    }

    @Test func occupiedRowsHidesEmptySlots() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 3)
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Me")
        GridPlacementLogic.place(profile: me, in: &grid, at: 0, col: 0)
        let rows = GridColumnZoomLogic.occupiedRows(from: grid, columns: 3)
        #expect(rows.flatMap { $0 }.count == 1)
        #expect(rows.flatMap { $0 }.first?.userProfile?.deviceID == "me")
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

    @Test func lastSelfMessageIsTheLatestNoteToSelf() {
        let older = message(id: "old", from: "me", to: "me", text: "first", at: Date(timeIntervalSince1970: 100))
        let newer = message(id: "new", from: "me", to: "me", text: "later", at: Date(timeIntervalSince1970: 200))
        let chat = message(id: "chat", from: "me", to: "bob", text: "hi", at: Date(timeIntervalSince1970: 300))
        #expect(MessageConversationLogic.lastSelfMessage(for: "me", in: [older, newer, chat])?.id == "new")
        #expect(MessageConversationLogic.lastSelfMessage(for: "bob", in: [older, newer, chat]) == nil)
    }

    @Test func conversationListOmitsSelfThread() {
        let t0 = Date(timeIntervalSince1970: 100)
        let messages = [
            message(id: "n", from: "me", to: "me", text: "note", at: t0),
        ]

        let list = MessageConversationLogic.conversationList(
            currentDeviceID: "me",
            messages: messages,
            displayNameLookup: { _ in "Should Not Use" }
        )

        #expect(list.isEmpty)
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

    @Test func conversationListUnreadCountUsesReceiptsNotThreadSize() {
        let messages = [
            message(id: "1", from: "bob", to: "me", text: "a", at: Date(timeIntervalSince1970: 100)),
            message(id: "2", from: "bob", to: "me", text: "b", at: Date(timeIntervalSince1970: 200)),
            message(id: "3", from: "me", to: "bob", text: "c", at: Date(timeIntervalSince1970: 300)),
        ]
        let list = MessageConversationLogic.conversationList(
            currentDeviceID: "me",
            messages: messages,
            readReceipts: ["1", "2"],
            displayNameLookup: { _ in "Bob" }
        )
        #expect(list.count == 1)
        #expect(list[0].messageCount == 3)
        #expect(list[0].unreadCount == 0)
    }

    @Test func previewLineHidesEncryptedPlaceholdersAndDescribesPhotos() {
        let encrypted = message(
            id: "e",
            from: "bob",
            to: "me",
            text: MessageBannerLogic.encryptedTextPlaceholder,
            at: Date()
        )
        #expect(
            MessageConversationLogic.previewLine(
                message: encrypted,
                currentDeviceID: "me",
                partnerName: "Bob",
                decryptedText: nil,
                nameForDevice: { _ in "Bob" }
            ) == "Message"
        )

        var photo = message(id: "p", from: "bob", to: "me", text: MessageBannerLogic.encryptedImagePlaceholder, at: Date())
        photo.encryptedImageData = "img"
        #expect(
            MessageConversationLogic.previewLine(
                message: photo,
                currentDeviceID: "me",
                partnerName: "Elliot",
                decryptedText: nil,
                nameForDevice: { _ in "Elliot" }
            ) == "A photo was sent"
        )

        photo.reactions = [MessageReaction(emoji: "❤️", reactorDeviceID: "bob")]
        #expect(
            MessageConversationLogic.previewLine(
                message: photo,
                currentDeviceID: "me",
                partnerName: "Elliot",
                decryptedText: nil,
                nameForDevice: { _ in "Elliot" }
            ) == "Elliot loved a photo"
        )
    }

    @Test func starredPeopleArePinnedAndOmittedFromTheList() {
        let alice = UserProfile(userID: "u-alice", deviceID: "alice", deviceName: "Alice")
        let bob = UserProfile(userID: "u-bob", deviceID: "bob", deviceName: "Bob")
        let home = MessageConversationLogic.messagesHome(
            currentDeviceID: "me",
            currentUserID: "u-me",
            messages: [
                message(id: "1", from: "alice", to: "me", text: "hi", at: Date(timeIntervalSince1970: 100)),
                message(id: "2", from: "bob", to: "me", text: "yo", at: Date(timeIntervalSince1970: 200)),
            ],
            readReceipts: ["1"],
            starredUserIDs: ["u-alice"],
            profiles: [alice, bob],
            displayNameLookup: { id in id == "alice" ? "Alice" : "Bob" }
        )

        #expect(home.pinned.map(\.deviceID) == ["alice"])
        #expect(home.pinned.first?.unreadCount == 0)
        #expect(home.conversations.map(\.deviceID) == ["bob"])
    }

    @Test func starredPersonWithNoMessagesStillGetsAPin() {
        let holly = UserProfile(userID: "u-holly", deviceID: "holly", deviceName: "Holly")
        let home = MessageConversationLogic.messagesHome(
            currentDeviceID: "me",
            currentUserID: "u-me",
            messages: [],
            starredUserIDs: ["u-holly"],
            profiles: [holly],
            displayNameLookup: { _ in "Holly" }
        )
        #expect(home.pinned.map(\.displayName) == ["Holly"])
        #expect(home.conversations.isEmpty)
    }

    @Test func listTimestampUsesYesterday() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(MessageConversationLogic.listTimestamp(yesterday, now: now) == "Yesterday")
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

    @Test func favoritesOnlyKeepsStarredPeers() {
        let profiles = [
            profile(userID: "star", deviceID: "s1"),
            profile(userID: "other", deviceID: "o1"),
        ]
        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            blockedUserIDs: [],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [],
            starredUserIDs: ["star"],
            favoritesOnly: true
        )
        #expect(filtered.map(\.userID) == ["star"])
    }

    @Test func allTabIgnoresStarredSet() {
        let profiles = [
            profile(userID: "star", deviceID: "s1"),
            profile(userID: "other", deviceID: "o1"),
        ]
        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            blockedUserIDs: [],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [],
            starredUserIDs: ["star"],
            favoritesOnly: false
        )
        #expect(filtered.map(\.userID) == ["star", "other"])
    }
}

struct NearbyInterestRankingTests {

    private func profile(_ id: String, interests: [Interest]) -> UserProfile {
        UserProfile(userID: id, deviceID: id, deviceName: id, interests: interests)
    }

    @Test func ranksByHowManyPeopleShareAnInterest() {
        let ranked = NearbyInterestRanking.ranked(
            from: [
                profile("a", interests: [.coffee, .music]),
                profile("b", interests: [.coffee]),
                profile("me", interests: [.hiking]),
            ],
            excludingDeviceID: "me",
            limit: 5
        )
        #expect(ranked.map(\.interest) == [.coffee, .music])
        #expect(ranked.first?.count == 2)
    }

    @Test func skipsLocalLLM() {
        var llm = LocalLLMIdentity.profile
        llm.interests = [.technology]
        let ranked = NearbyInterestRanking.ranked(from: [llm], limit: 5)
        #expect(ranked.isEmpty)
    }
}

struct InterestVenueQueryTests {
    @Test func lgbtqSearchesGayBars() {
        #expect(InterestVenueQuery.searchTerm(for: .gay) == "gay bars")
        #expect(InterestVenueQuery.rowTitle(for: .gay) == "Gay bars nearby")
        #expect(InterestVenueQuery.searchTerm(for: .lgbtq) == "gay bars")
        #expect(InterestVenueQuery.rowTitle(for: .lgbtq) == "Gay bars nearby")
        #expect(InterestVenueQuery.searchTerm(for: .comedy, kind: .events) == InterestVenueQuery.searchTerm(for: .comedy, kind: .places))
        #expect(InterestVenueQuery.rowTitle(for: .comedy, kind: .events) == "Comedy events nearby")
        #expect(InterestVenueQuery.searchTerm(for: .comedy, kind: .venues) == "Comedy venues")
        #expect(InterestVenueQuery.rowTitle(for: .comedy, kind: .venues) == "Comedy venues nearby")
    }
}

struct GridPeopleTabPagingTests {

    @Test func swipeLeftFromAllStaysOnAllWithoutOtherTabs() {
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: -120, velocity: -200, width: 390, current: .all) == .all)
    }

    @Test func swipeRightFromFavoritesOpensAll() {
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: 120, velocity: 200, width: 390, current: .favorites) == .all)
    }

    @Test func shortSwipeStaysOnCurrentTab() {
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: -20, velocity: 0, width: 390, current: .all) == .all)
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: 20, velocity: 0, width: 390, current: .favorites) == .favorites)
    }

    @Test func pageOffsetMovesByFullWidth() {
        #expect(GridPeopleTabPaging.pageOffset(tab: .all, width: 390, drag: 0) == 0)
        #expect(GridPeopleTabPaging.pageOffset(tab: .favorites, width: 390, drag: 0) == -390)
    }

    @Test func orderedTabsIncludeCustomGroups() {
        let group = PeopleGroup(name: "Gym")
        let tabs = GridPeopleTabPaging.orderedTabs(customGroups: [group])
        #expect(tabs == [.all, .custom(group.id)])
    }

    @Test func swipeMovesThroughCustomGroups() {
        let group = PeopleGroup(name: "Gym")
        let tabs = GridPeopleTabPaging.orderedTabs(customGroups: [group])
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: -80, current: .all, tabs: tabs) == .custom(group.id))
        #expect(GridPeopleTabPaging.tabAfterSwipe(translation: 80, current: .custom(group.id), tabs: tabs) == .all)
    }

    @Test func orderedTabsAppendInterestPages() {
        let tabs = GridPeopleTabPaging.orderedTabs(customGroups: [], interestPages: [.coffee])
        #expect(tabs == [.all, .interest(Interest.coffee.rawValue)])
    }

    @Test func swipePastLastTabOpensInterestSearch() {
        let tabs: [GridPeopleTab] = [.all]
        #expect(GridPeopleTabPaging.shouldOpenInterestSearch(translation: -80, current: .all, tabs: tabs))
        #expect(GridPeopleTabPaging.shouldOpenInterestSearch(translation: 80, current: .all, tabs: tabs) == false)
    }

    @Test func swipePastInterestPageOpensSearch() {
        let tabs = GridPeopleTabPaging.orderedTabs(customGroups: [], interestPages: [.coffee])
        #expect(GridPeopleTabPaging.shouldOpenInterestSearch(
            translation: -80,
            current: .interest(Interest.coffee.rawValue),
            tabs: tabs
        ))
        #expect(GridPeopleTabPaging.shouldOpenInterestSearch(
            translation: -80,
            current: .interest(Interest.coffee.rawValue),
            tabs: GridPeopleTabPaging.orderedTabs(
                customGroups: [],
                interestPages: [.coffee, .music, .hiking]
            ),
            canAddInterestPage: false
        ) == false)
        #expect(GridPeopleTabPaging.tabAfterSwipe(
            translation: -80,
            current: .interest(Interest.coffee.rawValue),
            tabs: tabs
        ) == .interest(Interest.coffee.rawValue))
    }

    @Test func swipePastLastTabAtCapPromptsRemoveInterest() {
        let tabs = GridPeopleTabPaging.orderedTabs(
            customGroups: [],
            interestPages: [.coffee, .music, .hiking]
        )
        #expect(GridPeopleTabPaging.shouldPromptRemoveInterestToAdd(
            translation: -80,
            current: .interest(Interest.hiking.rawValue),
            tabs: tabs,
            canAddInterestPage: false
        ))
        #expect(GridPeopleTabPaging.shouldPromptRemoveInterestToAdd(
            translation: -80,
            current: .interest(Interest.hiking.rawValue),
            tabs: tabs,
            canAddInterestPage: true
        ) == false)
        #expect(GridPeopleTabPaging.shouldPromptRemoveInterestToAdd(
            translation: 80,
            current: .interest(Interest.hiking.rawValue),
            tabs: tabs,
            canAddInterestPage: false
        ) == false)
    }
}

struct InterestPageStoreTests {
    @Test func insertingSkipsDuplicatesCaseInsensitively() {
        let first = InterestPageStore.inserting(.coffee, into: [])
        #expect(first == [.coffee])
        let again = InterestPageStore.inserting(Interest(rawValue: "coffee"), into: first)
        #expect(again == [.coffee])
        let extra = InterestPageStore.inserting(.music, into: first)
        #expect(extra == [.coffee, .music])
        #expect(InterestPageStore.removing(.coffee, from: extra) == [.music])
        #expect(InterestPageStore.contains(.music, in: extra))
    }

    @Test func insertingStopsAtThreePages() {
        let three = InterestPageStore.inserting(
            .hiking,
            into: InterestPageStore.inserting(.music, into: InterestPageStore.inserting(.coffee, into: []))
        )
        #expect(three == [.coffee, .music, .hiking])
        #expect(InterestPageStore.canAdd(to: three) == false)
        #expect(InterestPageStore.inserting(.yoga, into: three) == three)
        #expect(InterestPageStore.inserting(.coffee, into: three) == three)
    }

    @Test func saveAndLoadRoundTripsPages() {
        let defaults = UserDefaults(suiteName: "grid.interestPageStore.tests")!
        defaults.removePersistentDomain(forName: "grid.interestPageStore.tests")
        InterestPageStore.save([.coffee, .music], userID: "u1", defaults: defaults)
        #expect(InterestPageStore.load(userID: "u1", defaults: defaults) == [.coffee, .music])
    }
}

struct PeopleGroupStoreTests {
    @Test func saveAndLoadRoundTripsMembers() {
        let defaults = UserDefaults(suiteName: "grid.peopleGroupStore.tests")!
        defaults.removePersistentDomain(forName: "grid.peopleGroupStore.tests")
        let group = PeopleGroup(name: "Gym", memberUserIDs: ["u1"])
        PeopleGroupStore.save([group], userID: "me", defaults: defaults)
        let loaded = PeopleGroupStore.load(userID: "me", defaults: defaults)
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Gym")
        #expect(loaded.first?.memberUserIDs == ["u1"])
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

struct CustomInterestStoreTests {
    @Test func addPersistsNameAndEmoji() {
        let defaults = UserDefaults(suiteName: "grid.customInterest.tests")!
        defaults.removePersistentDomain(forName: "grid.customInterest.tests")
        let added = CustomInterestStore.add(name: "Dodgeball", emoji: "🏐", defaults: defaults)
        #expect(added?.rawValue == "Dodgeball")
        #expect(CustomInterestStore.emoji(for: "Dodgeball", defaults: defaults) == "🏐")
        #expect(CustomInterestStore.add(name: "Fitness", emoji: "🔥", defaults: defaults) == .fitness)
    }
}

struct SharedInterestMergeLogicTests {
    @Test func recordNameIsStableAndSafe() {
        #expect(SharedInterestIdentity.recordName(for: "Dodgeball") == "interest.dodgeball")
        #expect(SharedInterestIdentity.recordName(for: "  Dodge Ball ") == "interest.dodge-ball")
        #expect(SharedInterestIdentity.recordName(for: "Dodgeball") == SharedInterestIdentity.recordName(for: "dodgeball"))
    }

    @Test func harvestsCustomInterestsAndSkipsBuiltIns() {
        let alice = UserProfile(
            userID: "u-a",
            deviceID: "a",
            deviceName: "Alice",
            interests: [.coffee, Interest(rawValue: "Dodgeball")]
        )
        let harvested = SharedInterestMergeLogic.harvested(from: [alice])
        #expect(harvested.map(\.name) == ["Dodgeball"])
    }

    @Test func mergePrefersRealEmojiAndIgnoresBuiltIns() {
        let existing = [CustomInterestRecord(name: "Dodgeball", emoji: "✨")]
        let merged = SharedInterestMergeLogic.merging(
            [
                CustomInterestRecord(name: "dodgeball", emoji: "🏐"),
                CustomInterestRecord(name: "Coffee", emoji: "☕"),
            ],
            into: existing
        )
        #expect(merged == [CustomInterestRecord(name: "Dodgeball", emoji: "🏐")])
    }
}

// MARK: - Message read logic

struct ProfileCreationLogicTests {
    @Test func promptsForICloudWhenThereIsNoAccount() {
        let message = ProfileCreationLogic.userFacingCloudKitError(accountStatus: .noAccount, saveError: nil)
        #expect(message.contains("iCloud"))
    }

    @Test func mapsNotAuthenticatedSaveError() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.notAuthenticated.rawValue)
        let message = ProfileCreationLogic.userFacingCloudKitError(accountStatus: .available, saveError: error)
        #expect(message.contains("iCloud"))
    }
}

struct DeviceIdentityLogicTests {
    @Test func peerTokenPrefersLaunchNameThenSimulatorUDID() {
        let defaults = UserDefaults(suiteName: "grid.deviceIdentity.tests")!
        defaults.removePersistentDomain(forName: "grid.deviceIdentity.tests")
        defaults.set("Alice!", forKey: DeviceIdentityLogic.peerNameDefaultsKey)
        #expect(DeviceIdentityLogic.peerToken(defaults: defaults, environment: ["SIMULATOR_UDID": "AAAAAAAA-BBBB"]) == "Alice")
        defaults.removeObject(forKey: DeviceIdentityLogic.peerNameDefaultsKey)
        #expect(DeviceIdentityLogic.peerToken(defaults: defaults, environment: ["SIMULATOR_UDID": "AAAAAAAA-BBBB"]) == "AAAAAAAA")
        #expect(DeviceIdentityLogic.peerToken(defaults: defaults, environment: [:]) == nil)
    }

    @Test func resolvedIDPersistsPerPeer() {
        let defaults = UserDefaults(suiteName: "grid.deviceIdentity.persist")!
        defaults.removePersistentDomain(forName: "grid.deviceIdentity.persist")
        defaults.set("Alice", forKey: DeviceIdentityLogic.peerNameDefaultsKey)
        let first = DeviceIdentityLogic.resolvedDeviceID(forAppleUserID: "001.user", defaults: defaults, environment: [:])
        let second = DeviceIdentityLogic.resolvedDeviceID(forAppleUserID: "001.user", defaults: defaults, environment: [:])
        #expect(first == second)
        #expect(first.contains("Alice"))
    }
}

struct MessageBannerLogicTests {

    private func message(
        text: String = "hello",
        encrypted: Bool = false,
        image: Bool = false
    ) -> Message {
        var message = Message(
            id: "m1",
            senderDeviceID: "bob",
            recipientDeviceID: "me",
            senderUserID: "u-bob",
            recipientUserID: "u-me",
            text: text,
            status: .received
        )
        message.isEncrypted = encrypted
        if image {
            message.encryptedImageData = "abc"
        }
        return message
    }

    @Test func titleUsesSenderName() {
        #expect(MessageBannerLogic.title(senderName: "Alex") == "Alex")
        #expect(MessageBannerLogic.title(senderName: "  ") == MessageBannerLogic.fallbackTitle)
        #expect(MessageBannerLogic.title(senderName: nil) == MessageBannerLogic.fallbackTitle)
        #expect(MessageBannerLogic.title(senderName: "iPhone") == MessageBannerLogic.fallbackTitle)
    }

    @Test func previewUsesDecryptedText() {
        let preview = MessageBannerLogic.previewText(
            message: message(text: "[Encrypted Message]", encrypted: true),
            decryptedText: "want to get coffee?"
        )
        #expect(preview == "want to get coffee?")
    }

    @Test func previewHidesEncryptionPlaceholder() {
        let preview = MessageBannerLogic.previewText(
            message: message(text: "[Encrypted Message]", encrypted: true),
            decryptedText: nil
        )
        #expect(preview == MessageBannerLogic.genericBody)
    }

    @Test func previewUsesPhotoLabel() {
        let preview = MessageBannerLogic.previewText(
            message: message(text: "[Encrypted Image]", encrypted: true, image: true),
            decryptedText: nil
        )
        #expect(preview == MessageBannerLogic.photoBody)
    }

    @Test func previewTruncatesLongText() {
        let long = String(repeating: "a", count: 200)
        let preview = MessageBannerLogic.previewText(message: message(text: long), decryptedText: long)
        #expect(preview.count == MessageBannerLogic.maxPreviewLength)
        #expect(preview.hasSuffix("…"))
    }

    @Test func doesNotAnnounceOwnOrOpenChat() {
        #expect(MessageBannerLogic.shouldAnnounce(senderDeviceID: "bob", currentDeviceID: "me", viewingDeviceID: nil))
        #expect(!MessageBannerLogic.shouldAnnounce(senderDeviceID: "me", currentDeviceID: "me", viewingDeviceID: nil))
        #expect(!MessageBannerLogic.shouldAnnounce(senderDeviceID: "bob", currentDeviceID: "me", viewingDeviceID: "bob"))
        #expect(!MessageBannerLogic.shouldAnnounce(senderDeviceID: LocalLLMIdentity.deviceID, currentDeviceID: "me", viewingDeviceID: nil))
    }

    @Test func senderNameCacheRoundTrip() {
        let defaults = UserDefaults(suiteName: "grid.senderName.tests")!
        defaults.removePersistentDomain(forName: "grid.senderName.tests")
        SenderNameCache.store("Sam Phone", for: "sam", defaults: defaults)
        #expect(SenderNameCache.name(for: "sam", defaults: defaults) == "Sam Phone")
    }
}

struct MessageReactionLogicTests {
    private func message(reactions: [MessageReaction] = [], updatedAt: Date? = nil) -> Message {
        var item = Message(
            id: "m1",
            senderDeviceID: "alice",
            recipientDeviceID: "me",
            senderUserID: "u-a",
            recipientUserID: "u-me",
            text: "hi",
            status: .received
        )
        item.reactions = reactions
        item.reactionsUpdatedAt = updatedAt
        return item
    }

    @Test func toggleAddsThenRemovesTheSameEmoji() {
        let added = MessageReactionLogic.toggle(emoji: "❤️", reactorDeviceID: "me", in: [])
        #expect(added == [MessageReaction(emoji: "❤️", reactorDeviceID: "me")])
        let removed = MessageReactionLogic.toggle(emoji: "❤️", reactorDeviceID: "me", in: added)
        #expect(removed.isEmpty)
    }

    @Test func toggleReplacesAPersonsPreviousEmoji() {
        let heart = [MessageReaction(emoji: "❤️", reactorDeviceID: "me")]
        let thumbs = MessageReactionLogic.toggle(emoji: "👍", reactorDeviceID: "me", in: heart)
        #expect(thumbs == [MessageReaction(emoji: "👍", reactorDeviceID: "me")])
    }

    @Test func toggleIgnoresUnknownEmoji() {
        #expect(MessageReactionLogic.toggle(emoji: "🍕", reactorDeviceID: "me", in: []).isEmpty)
    }

    @Test func groupedCountsAndMarksMine() {
        let reactions = [
            MessageReaction(emoji: "❤️", reactorDeviceID: "me"),
            MessageReaction(emoji: "❤️", reactorDeviceID: "bob"),
            MessageReaction(emoji: "👍", reactorDeviceID: "bob"),
        ]
        let groups = MessageReactionLogic.grouped(reactions, currentDeviceID: "me")
        #expect(groups.map(\.emoji) == ["❤️", "👍"])
        #expect(groups[0].count == 2)
        #expect(groups[0].includesMe)
        #expect(groups[1].count == 1)
        #expect(!groups[1].includesMe)
    }

    @Test func newerLocalReactionsSurviveStaleFetch() {
        let local = message(
            reactions: [MessageReaction(emoji: "😂", reactorDeviceID: "me")],
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let stale = message(reactions: [], updatedAt: Date(timeIntervalSince1970: 50))
        #expect(MessageReactionLogic.pick(local: local, incoming: stale) == local.reactions)
        let merged = MessageInboxLogic.merge(local: [local], incoming: [stale])
        #expect(merged[0].reactions == local.reactions)
    }
}

struct MessageInboxLogicTests {

    private func message(
        id: String,
        text: String,
        status: MessageStatus,
        at timestamp: Date = Date(timeIntervalSince1970: 100)
    ) -> Message {
        Message(
            id: id,
            senderDeviceID: "bob",
            recipientDeviceID: "me",
            senderUserID: "u-bob",
            recipientUserID: "u-me",
            text: text,
            timestamp: timestamp,
            status: status
        )
    }

    @Test func mergeKeepsLocalMessageMissingFromStaleQuery() {
        let pushed = message(id: "push-1", text: "just arrived", status: .received)
        let older = message(id: "old-1", text: "earlier", status: .received, at: Date(timeIntervalSince1970: 50))
        let merged = MessageInboxLogic.merge(local: [older, pushed], incoming: [older])
        #expect(merged.map(\.id) == ["old-1", "push-1"])
    }

    @Test func mergeAddsNewlyFetchedRecord() {
        let older = message(id: "old-1", text: "earlier", status: .received, at: Date(timeIntervalSince1970: 50))
        let incoming = message(id: "push-1", text: "just arrived", status: .received)
        let merged = MessageInboxLogic.merge(local: [older], incoming: [incoming])
        #expect(Set(merged.map(\.id)) == ["old-1", "push-1"])
    }

    @Test func mergeDoesNotClobberOptimisticSend() {
        let sending = message(id: "temp", text: "hello", status: .sending)
        let stale = message(id: "temp", text: "hello", status: .sending)
        let merged = MessageInboxLogic.merge(local: [sending], incoming: [stale])
        #expect(merged[0].status == .sending)
    }

    @Test func mergeAcceptsServerConfirmationOfOptimisticSend() {
        let sending = message(id: "temp", text: "[Encrypted Message]", status: .sending)
        let saved = message(id: "temp", text: "[Encrypted Message]", status: .sent)
        let merged = MessageInboxLogic.merge(local: [sending], incoming: [saved])
        #expect(merged[0].status == .sent)
    }

    @Test func persistableDropsSendingAndLocalLLM() {
        let keep = message(id: "1", text: "hi", status: .received)
        let sending = message(id: "2", text: "soon", status: .sending)
        let llm = Message(
            id: "3",
            senderDeviceID: LocalLLMIdentity.deviceID,
            recipientDeviceID: "me",
            senderUserID: LocalLLMIdentity.userID,
            recipientUserID: "u-me",
            text: "ok",
            status: .received
        )
        #expect(MessageInboxLogic.persistable([keep, sending, llm]).map(\.id) == ["1"])
    }

    @Test func pendingStoreEnqueuesAndRemoves() {
        let defaults = UserDefaults(suiteName: "grid.pendingMessage.tests")!
        defaults.removePersistentDomain(forName: "grid.pendingMessage.tests")
        PendingMessageFetchStore.enqueue("rec-1", defaults: defaults)
        PendingMessageFetchStore.enqueue("rec-1", defaults: defaults)
        PendingMessageFetchStore.enqueue("rec-2", defaults: defaults)
        #expect(Set(PendingMessageFetchStore.all(defaults: defaults)) == ["rec-1", "rec-2"])
        PendingMessageFetchStore.remove("rec-1", defaults: defaults)
        #expect(PendingMessageFetchStore.all(defaults: defaults) == ["rec-2"])
    }
}

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
        #expect(MessageReadLogic.incomingUnreadCount(currentDeviceID: "me", messages: messages, readReceipts: ["1"]) == 1)
        #expect(MessageReadLogic.incomingUnreadCount(
            currentDeviceID: "me",
            messages: messages,
            readReceipts: ["1"],
            excludingSenderDeviceID: "bob"
        ) == 0)
    }
}

struct MessageDecryptabilityLogicTests {
    @Test func undecryptableCiphertextDoesNotCountAnywhere() {
        #expect(!MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: false,
            decryptedText: MessageDecryptabilityLogic.failedTextPlaceholder,
            hasDecryptedImage: false
        ))
        #expect(!MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: false,
            decryptedText: MessageBannerLogic.encryptedTextPlaceholder,
            hasDecryptedImage: false
        ))
        #expect(!MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: false,
            decryptedText: nil,
            hasDecryptedImage: false
        ))
        #expect(!MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: true,
            decryptedText: nil,
            hasDecryptedImage: false
        ))
        #expect(MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: false,
            decryptedText: "hey",
            hasDecryptedImage: false
        ))
        #expect(MessageDecryptabilityLogic.counts(
            isEncrypted: true,
            hasEncryptedImage: true,
            decryptedText: nil,
            hasDecryptedImage: true
        ))
        #expect(MessageDecryptabilityLogic.counts(
            isEncrypted: false,
            hasEncryptedImage: false,
            decryptedText: "plain",
            hasDecryptedImage: false
        ))

        var locked = Message(
            id: "old-account",
            senderDeviceID: "elliott",
            recipientDeviceID: "me",
            senderUserID: "u-elliott",
            recipientUserID: "u-me",
            text: MessageBannerLogic.encryptedTextPlaceholder,
            status: .received
        )
        locked.isEncrypted = true
        locked.encryptedContent = "not-valid-ciphertext"
        let open = Message(
            id: "new",
            senderDeviceID: "elliott",
            recipientDeviceID: "me",
            senderUserID: "u-elliott",
            recipientUserID: "u-me",
            text: "hey",
            status: .received
        )
        let visible = MessageDecryptabilityLogic.visible(in: [locked, open])
        #expect(visible.map(\.id) == ["new"])
        #expect(MessageReadLogic.unreadCount(
            from: "elliott",
            currentDeviceID: "me",
            messages: visible,
            readReceipts: []
        ) == 1)
        #expect(MessageConversationLogic.conversationList(
            currentDeviceID: "me",
            messages: visible,
            displayNameLookup: { _ in "Elliott" }
        ).map(\.lastMessage?.id) == ["new"])
    }
}

// MARK: - Grid placement logic

@MainActor
struct GridPopulationServiceTests {

    @Test func placesLocalLLMBesideCurrentUser() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        service.layoutProfiles(
            into: &grid,
            profiles: [me],
            currentUser: me,
            display: GridDisplayState(
                blockedUserIDs: [],
                usersWhoBlockedMe: [],
                selectedInterestFilter: [],
                showsLocalLLM: true
            )
        )
        #expect(grid[0][0].userProfile?.deviceID == LocalLLMIdentity.deviceID)
        #expect(grid.flatMap { $0 }.compactMap(\.userProfile).contains { $0.deviceID == "me" } == false)
    }

    @Test func omitsLocalLLMWhenDisabled() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        service.layoutProfiles(
            into: &grid,
            profiles: [me],
            currentUser: me,
            display: GridDisplayState(blockedUserIDs: [], usersWhoBlockedMe: [], selectedInterestFilter: [])
        )
        #expect(grid[0][0].userProfile == nil)
        #expect(grid.flatMap { $0 }.compactMap(\.userProfile).isEmpty)
    }

    @Test func placesCurrentUserWhenShowSelfIsEnabled() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        service.layoutProfiles(
            into: &grid,
            profiles: [me],
            currentUser: me,
            display: GridDisplayState(
                blockedUserIDs: [],
                usersWhoBlockedMe: [],
                selectedInterestFilter: [],
                showsSelfOnGrid: true
            )
        )
        #expect(grid[0][0].userProfile?.deviceID == "me")
    }

    @Test func localLLMSurvivesInterestFilter() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        service.layoutProfiles(
            into: &grid,
            profiles: [me],
            currentUser: me,
            display: GridDisplayState(
                blockedUserIDs: [],
                usersWhoBlockedMe: [],
                selectedInterestFilter: [.technology],
                showsLocalLLM: true
            )
        )
        #expect(grid[0][0].userProfile?.deviceID == LocalLLMIdentity.deviceID)
        #expect(grid.flatMap { $0 }.compactMap(\.userProfile).contains { $0.deviceID == "me" } == false)
    }

    @Test func favoritesLayoutOmitsLocalLLMAndUnstarredPeers() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        let fave = UserProfile(userID: "star", deviceID: "s1", deviceName: "Star")
        let other = UserProfile(userID: "other", deviceID: "o1", deviceName: "Other")
        service.layoutProfiles(
            into: &grid,
            profiles: [me, fave, other],
            currentUser: me,
            display: GridDisplayState(
                blockedUserIDs: [],
                usersWhoBlockedMe: [],
                selectedInterestFilter: [],
                starredUserIDs: ["star"],
                favoritesOnly: true
            )
        )
        let placed = grid.flatMap { $0 }.compactMap(\.userProfile)
        #expect(placed.map(\.deviceID) == ["s1"])
        #expect(!placed.contains { $0.deviceID == LocalLLMIdentity.deviceID })
        #expect(!placed.contains { $0.deviceID == "o1" })
    }
}

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
        #expect(grid[0][1].id == PersonIdentity.id(forDeviceID: "d"))
        #expect(grid[0][0].id == PersonIdentity.emptySlotID(x: 0, y: 0))
        #expect(grid[0][0].userProfile == nil)
    }

    @Test func replaceProfileUpdatesMatchingCellsOnly() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 2)
        let original = UserProfile(userID: "u", deviceID: "me", deviceName: "Old")
        let other = UserProfile(userID: "u2", deviceID: "bob", deviceName: "Bob")
        GridPlacementLogic.place(profile: original, in: &grid, at: 0, col: 0)
        GridPlacementLogic.place(profile: other, in: &grid, at: 0, col: 1)
        let updated = UserProfile(userID: "u", deviceID: "me", deviceName: "New")
        GridPlacementLogic.replaceProfile(updated, in: &grid)
        #expect(grid[0][0].userProfile?.deviceName == "New")
        #expect(grid[0][1].userProfile?.deviceName == "Bob")
    }
}

struct ProfileImageRefreshLogicTests {

    @Test func keepsLocalPhotoWhenSavedFileIsMissing() {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("grid-local-photo.jpg")
        try? Data("local".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("grid-missing-photo.jpg")
        #expect(ProfileImageRefreshLogic.shouldKeepLocalPhoto(localURL: local, savedURL: missing))
        #expect(!ProfileImageRefreshLogic.shouldKeepLocalPhoto(localURL: local, savedURL: local))
        #expect(!ProfileImageRefreshLogic.shouldKeepLocalPhoto(localURL: missing, savedURL: local))
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

    @Test func selfChatUsesYou() {
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "me-device",
            currentDeviceID: "me-device",
            gridNodes: []
        )
        #expect(title == "You")
    }

    @Test func usesPersonNameWhenOnGrid() {
        let grid = gridWithPeer(deviceID: "bob-device", deviceName: "Bob")
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "bob-device",
            currentDeviceID: "me-device",
            gridNodes: grid
        )
        #expect(title == "Bob")
    }

    @Test func rejectsDeviceNamesAndFallsBackToSomeone() {
        let grid = gridWithPeer(deviceID: "iphone-peer", deviceName: "iPhone")
        let titled = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "iphone-peer",
            currentDeviceID: "me-device",
            gridNodes: grid
        )
        let missing = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "abcdefgh-xyz",
            currentDeviceID: "me-device",
            gridNodes: GridPlacementLogic.makeEmptyGrid(size: 2)
        )
        #expect(titled == ProfileDisplayNameLogic.fallbackTitle)
        #expect(missing == ProfileDisplayNameLogic.fallbackTitle)
    }

    @Test func localLLMUsesPlainName() {
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: LocalLLMIdentity.deviceID,
            currentDeviceID: "me-device",
            gridNodes: []
        )
        #expect(title == "Local LLM")
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

struct AgeGateLogicTests {
    @Test func signInRequiresConfirmation() {
        #expect(AgeGateLogic.canProceedToSignIn(confirmedMinimumAge: false) == false)
        #expect(AgeGateLogic.canProceedToSignIn(confirmedMinimumAge: true) == true)
        #expect(AgeGateLogic.minimumAge == 17)
    }
}

struct ChatOverlaySessionTests {
    @Test func firstOpenDoesNotDefaultToSelf() {
        let session = ChatOverlaySession()
        #expect(session.activePartnerDeviceID == nil)
        #expect(session.isPresented == false)
    }

    @Test func openingSecondPersonReplacesTheFirst() {
        var session = ChatOverlaySession()
        session.open(with: "1713-DEVICE")
        #expect(session.activePartnerDeviceID == "1713-DEVICE")
        session.hide()
        session.open(with: "0041-DEVICE")
        #expect(session.activePartnerDeviceID == "0041-DEVICE")
        #expect(session.recipientDeviceID == "0041-DEVICE")
    }

    @Test func openingWithoutHideStillSwitchesPartner() {
        var session = ChatOverlaySession()
        session.open(with: "8ACEF559-DEVICE")
        session.open(with: "1713-DEVICE")
        #expect(session.activePartnerDeviceID == "1713-DEVICE")
    }

    @Test func overlayIdentityChangesWhenSwitchingPeople() {
        var session = ChatOverlaySession()
        session.open(with: "1713-DEVICE")
        let first = session.overlayIdentity
        session.open(with: "0041-DEVICE")
        let second = session.overlayIdentity
        #expect(first != second)
        #expect(second == "0041-DEVICE-2")
        session.hide()
        #expect(session.overlayIdentity == nil)
        #expect(session.recipientDeviceID == nil)
    }
}

struct MessageSubscriptionLogicTests {
    @Test func productionDesiredKeysStayWithinSchemaLimit() {
        #expect(MessageSubscriptionLogic.desiredKeys == ["senderDeviceID"])
        #expect(MessageSubscriptionLogic.desiredKeys.count <= MessageSubscriptionLogic.productionDesiredKeyLimit)
    }
}

@MainActor
struct ChatOverlayViewModelTests {
    @Test func openThenOpenAnotherSwitchesPartner() {
        let viewModel = GridViewModel()
        viewModel.openChatOverlay(with: "1713-DEVICE")
        #expect(viewModel.chatOverlaySession.activePartnerDeviceID == "1713-DEVICE")
        viewModel.hideChatOverlay()
        viewModel.openChatOverlay(with: "0041-DEVICE")
        #expect(viewModel.chatOverlaySession.activePartnerDeviceID == "0041-DEVICE")
        #expect(viewModel.currentChatRecipientDeviceID == "0041-DEVICE")
    }
}

@MainActor
struct GridUITestHarnessTests {
    @Test func fixturesPlaceAliceAndBobOnTheGrid() {
        let viewModel = GridViewModel()
        viewModel.installUITestFixtures()
        let ids = Set(viewModel.gridNodes.flatMap { $0 }.compactMap(\.userProfile?.deviceID))
        #expect(viewModel.currentUserProfile?.deviceID == GridUITestHarness.me.deviceID)
        #expect(ids.contains(GridUITestHarness.alice.deviceID))
        #expect(ids.contains(GridUITestHarness.bob.deviceID))
        #expect(GridUITestHarness.cellIdentifier(for: GridUITestHarness.alice.deviceID) == "grid.cell.uitest-alice-DEVICE")
        #expect(GridUITestHarness.chatComposerIdentifier == "chat.composer")
        #expect(GridUITestHarness.chatMessageIdentifier == "chat.message")
        #expect(GridUITestHarness.openMeIdentifier == "uitest.open.me")
        #expect(viewModel.isStarred(GridUITestHarness.alice.deviceID))
        #expect(viewModel.getMessagesForConversation(with: GridUITestHarness.alice.deviceID).map(\.text) == [GridUITestHarness.aliceMessageText])
        #expect(viewModel.getMessagesForConversation(with: GridUITestHarness.bob.deviceID).map(\.text) == [GridUITestHarness.bobMessageText])
    }
}

struct AccountDeletionCoverageTests {
    @Test func deletesStoriesAlbumsReceiptsAndFiledReports() {
        let types = Set(AccountDeletionService.deletableRecordQueries.map(\.recordType))
        #expect(types.contains("UserProfiles"))
        #expect(types.contains("Messages"))
        #expect(types.contains("UserRelationships"))
        #expect(types.contains("EncryptionProfiles"))
        #expect(types.contains("Stories"))
        #expect(types.contains("StoryViews"))
        #expect(types.contains("Albums"))
        #expect(types.contains("ReadReceipts"))
        #expect(types.contains("Reports"))
    }

    @Test func skipsUnqueryableReportsSchema() {
        let indexable = NSError(
            domain: CKError.errorDomain,
            code: CKError.invalidArguments.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Type is not marked indexable: Reports"]
        )
        let missingType = NSError(
            domain: CKError.errorDomain,
            code: CKError.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: Reports"]
        )
        let network = NSError(
            domain: CKError.errorDomain,
            code: CKError.networkUnavailable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Network unavailable"]
        )
        #expect(AccountDeletionLogic.isSkippableSchemaError(indexable))
        #expect(AccountDeletionLogic.isSkippableSchemaError(missingType))
        #expect(!AccountDeletionLogic.isSkippableSchemaError(network))
    }
}

struct LocationOnboardingLogicTests {
    @Test func welcomeUntilLocationIsGranted() {
        #expect(LocationOnboardingLogic.shouldShowWelcome(status: .notDetermined))
        #expect(LocationOnboardingLogic.shouldShowWelcome(status: .denied))
        #expect(!LocationOnboardingLogic.shouldShowWelcome(status: .authorizedWhenInUse))
        #expect(!LocationOnboardingLogic.shouldShowNearbyPeople(status: .notDetermined))
        #expect(LocationOnboardingLogic.shouldShowNearbyPeople(status: .authorizedWhenInUse))
        #expect(LocationOnboardingLogic.enableAction(for: .notDetermined) == .requestPermission)
        #expect(LocationOnboardingLogic.enableAction(for: .denied) == .openSettings)
    }
}

struct NotificationPermissionLogicTests {
    @Test func waitsForFirstRealChat() {
        #expect(!NotificationPermissionLogic.shouldRequest(alreadyRequested: true, event: .sent(isLLM: false)))
        #expect(!NotificationPermissionLogic.shouldRequest(alreadyRequested: false, event: .sent(isLLM: true)))
        #expect(NotificationPermissionLogic.shouldRequest(alreadyRequested: false, event: .sent(isLLM: false)))
        #expect(NotificationPermissionLogic.shouldRequest(
            alreadyRequested: false,
            event: .received(fromCurrentUser: false, isLLM: false)
        ))
        #expect(!NotificationPermissionLogic.shouldRequest(
            alreadyRequested: false,
            event: .received(fromCurrentUser: true, isLLM: false)
        ))
    }
}

@MainActor
struct LocationGatedGridTests {
    @Test func hidesPeersUntilLocationIsGranted() {
        let service = GridPopulationService()
        var grid = GridPlacementLogic.makeEmptyGrid()
        let me = UserProfile(userID: "u", deviceID: "me", deviceName: "Phone")
        let other = UserProfile(userID: "o", deviceID: "o1", deviceName: "Other")
        service.layoutProfiles(
            into: &grid,
            profiles: [me, other],
            currentUser: me,
            display: GridDisplayState(
                blockedUserIDs: [],
                usersWhoBlockedMe: [],
                selectedInterestFilter: [],
                showsSelfOnGrid: true,
                showsNearbyPeople: false
            )
        )
        let placed = grid.flatMap { $0 }.compactMap(\.userProfile)
        #expect(placed.map(\.deviceID) == ["me"])
    }
}
