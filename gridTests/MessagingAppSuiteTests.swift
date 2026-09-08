import Testing
import Foundation
@testable import grid

/// Checks a messenger would fail if it shipped: wrong thread, swapped partner,
/// recycled grid identity, device names in the header, leaked notifications.
struct MessagingAppSuiteTests {

    private let me = "me-DEVICE"
    private let alice = "alice-DEVICE"
    private let bob = "bob-DEVICE"
    private let carol = "carol-DEVICE"

    private func message(
        id: String,
        from sender: String,
        to recipient: String,
        text: String,
        at timestamp: Date = Date(timeIntervalSince1970: 100),
        status: MessageStatus = .received
    ) -> Message {
        Message(
            id: id,
            senderDeviceID: sender,
            recipientDeviceID: recipient,
            senderUserID: "u-\(sender)",
            recipientUserID: "u-\(recipient)",
            text: text,
            timestamp: timestamp,
            status: status
        )
    }

    private func profile(deviceID: String, name: String) -> UserProfile {
        UserProfile(userID: "user-\(deviceID)", deviceID: deviceID, deviceName: name)
    }

    private func grid(with peers: [(String, String)]) -> [[GridNode]] {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 3)
        GridPlacementLogic.place(profile: profile(deviceID: me, name: "Me"), in: &grid, at: 0, col: 0)
        for (index, peer) in peers.enumerated() {
            GridPlacementLogic.place(
                profile: profile(deviceID: peer.0, name: peer.1),
                in: &grid,
                at: 0,
                col: 1 + index
            )
        }
        return grid
    }

    // MARK: - Person identity

    @Test func tappingACellOpensThatCellsPersonNotSomeoneElse() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 2)
        GridPlacementLogic.place(profile: profile(deviceID: alice, name: "Alice"), in: &grid, at: 0, col: 0)
        GridPlacementLogic.place(profile: profile(deviceID: bob, name: "Bob"), in: &grid, at: 0, col: 1)
        #expect(GridCellTapLogic.chatPartnerDeviceID(for: grid[0][0]) == alice)
        #expect(GridCellTapLogic.chatPartnerDeviceID(for: grid[0][1]) == bob)
        #expect(GridCellTapLogic.chatPartnerDeviceID(for: grid[0][0]) == grid[0][0].id)
        #expect(GridCellTapLogic.chatPartnerDeviceID(for: grid[0][1]) == grid[0][1].id)
        #expect(GridCellTapLogic.chatPartnerDeviceID(for: grid[0][0]) != GridCellTapLogic.chatPartnerDeviceID(for: grid[0][1]))
    }

    @Test func occupiedCellUsesThePersonsDeviceID() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 2)
        #expect(grid[0][1].id == PersonIdentity.emptySlotID(x: 0, y: 1))
        GridPlacementLogic.place(profile: profile(deviceID: alice, name: "Alice"), in: &grid, at: 0, col: 1)
        #expect(grid[0][1].id == alice)
        #expect(grid[0][1].id == PersonIdentity.id(forDeviceID: alice))
    }

    @Test func twoPeopleNeverShareACellIdentity() {
        let grid = grid(with: [(alice, "Alice"), (bob, "Bob")])
        let ids = grid.flatMap { $0 }.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(alice))
        #expect(ids.contains(bob))
        #expect(ids.contains(me))
    }

    @Test func samePersonKeepsTheSameIDAfterTheyMoveSlots() {
        var first = GridPlacementLogic.makeEmptyGrid(size: 3)
        GridPlacementLogic.place(profile: profile(deviceID: alice, name: "Alice"), in: &first, at: 0, col: 1)
        var second = GridPlacementLogic.makeEmptyGrid(size: 3)
        GridPlacementLogic.place(profile: profile(deviceID: alice, name: "Alice"), in: &second, at: 1, col: 2)
        #expect(first[0][1].id == second[1][2].id)
        #expect(first[0][1].id == alice)
        #expect(second[0][1].id == PersonIdentity.emptySlotID(x: 0, y: 1))
    }

    @Test func replacingASlotChangesIdentityToTheNewPerson() {
        var grid = GridPlacementLogic.makeEmptyGrid(size: 2)
        GridPlacementLogic.place(profile: profile(deviceID: alice, name: "Alice"), in: &grid, at: 0, col: 1)
        GridPlacementLogic.place(profile: profile(deviceID: bob, name: "Bob"), in: &grid, at: 0, col: 1)
        #expect(grid[0][1].id == bob)
        #expect(grid[0][1].id != alice)
    }

    // MARK: - Thread isolation

    @Test func openingAliceNeverShowsBobsMessages() {
        let all = [
            message(id: "a1", from: alice, to: me, text: "from alice"),
            message(id: "a2", from: me, to: alice, text: "to alice"),
            message(id: "b1", from: bob, to: me, text: "from bob"),
            message(id: "b2", from: me, to: bob, text: "to bob"),
            message(id: "c1", from: carol, to: me, text: "from carol"),
        ]
        let aliceThread = MessageConversationLogic.messages(
            inConversationWith: alice,
            currentDeviceID: me,
            from: all
        )
        #expect(aliceThread.map(\.id) == ["a1", "a2"])
        #expect(aliceThread.allSatisfy { message in
            (message.senderDeviceID == alice || message.recipientDeviceID == alice)
                && (message.senderDeviceID == me || message.recipientDeviceID == me)
        })
    }

    @Test func notesStayOutOfPeerThreads() {
        let all = [
            message(id: "note", from: me, to: me, text: "grocery list"),
            message(id: "a1", from: alice, to: me, text: "hi"),
        ]
        let notes = MessageConversationLogic.messages(inConversationWith: me, currentDeviceID: me, from: all)
        let aliceThread = MessageConversationLogic.messages(inConversationWith: alice, currentDeviceID: me, from: all)
        #expect(notes.map(\.id) == ["note"])
        #expect(aliceThread.map(\.id) == ["a1"])
    }

    /// Build 13 report: "I can see the messages you sent me if I click *my* icon, but not yours."
    @Test func partnersIncomingNeverShowsUnderMyNotes() {
        let fromPartner = message(id: "from-bryan", from: alice, to: me, text: "Youre not getting this")
        let all = [
            fromPartner,
            message(id: "note", from: me, to: me, text: "my note"),
            message(id: "to-partner", from: me, to: alice, text: "reply"),
        ]
        let notes = MessageConversationLogic.messages(inConversationWith: me, currentDeviceID: me, from: all)
        let partner = MessageConversationLogic.messages(inConversationWith: alice, currentDeviceID: me, from: all)
        #expect(notes.map(\.id) == ["note"])
        #expect(!notes.contains(where: { $0.id == "from-bryan" }))
        #expect(partner.map(\.id) == ["from-bryan", "to-partner"])
    }

    /// Build 13 report: badge of 2 on a person, chat has no new messages.
    @Test func unreadBadgeOnlyCountsMessagesInThatPersonsThread() {
        let all = [
            message(id: "a1", from: alice, to: me, text: "one"),
            message(id: "a2", from: alice, to: me, text: "two"),
            message(id: "b1", from: bob, to: me, text: "other person"),
        ]
        let unread = MessageReadLogic.unreadCount(
            from: alice,
            currentDeviceID: me,
            messages: all,
            readReceipts: []
        )
        let aliceThreadIDs = Set(
            MessageConversationLogic.messages(
                inConversationWith: alice,
                currentDeviceID: me,
                from: all
            ).map(\.id)
        )
        #expect(unread == 2)
        #expect(aliceThreadIDs.isSuperset(of: ["a1", "a2"]))
        #expect(!aliceThreadIDs.contains("b1"))
    }

    @Test func conversationListHasOneRowPerPersonID() {
        let list = MessageConversationLogic.conversationList(
            currentDeviceID: me,
            messages: [
                message(id: "a1", from: alice, to: me, text: "a"),
                message(id: "a2", from: me, to: alice, text: "a2", at: Date(timeIntervalSince1970: 200)),
                message(id: "b1", from: bob, to: me, text: "b", at: Date(timeIntervalSince1970: 300)),
            ],
            displayNameLookup: { id in
                id == alice ? "Alice" : "Bob"
            }
        )
        #expect(list.map(\.deviceID) == [bob, alice])
        #expect(list.map(\.displayName) == ["Bob", "Alice"])
        #expect(list[1].messageCount == 2)
    }

    @Test func twoPeopleWithTheSameNameStillHaveSeparateThreads() {
        let all = [
            message(id: "1", from: "1713-DEVICE", to: me, text: "first 1713"),
            message(id: "2", from: "0041-DEVICE", to: me, text: "first 0041"),
        ]
        let first = MessageConversationLogic.messages(
            inConversationWith: "1713-DEVICE",
            currentDeviceID: me,
            from: all
        )
        let second = MessageConversationLogic.messages(
            inConversationWith: "0041-DEVICE",
            currentDeviceID: me,
            from: all
        )
        #expect(first.map(\.id) == ["1"])
        #expect(second.map(\.id) == ["2"])
    }

    // MARK: - Chat partner switching

    @Test func tappingAThenBOpensB() {
        var session = ChatOverlaySession()
        session.open(with: alice)
        session.open(with: bob)
        #expect(session.activePartnerDeviceID == bob)
        #expect(session.recipientDeviceID == bob)
    }

    @Test func hideClearsTheVisiblePartnerWithoutForgettingTheLastID() {
        var session = ChatOverlaySession()
        session.open(with: alice)
        session.hide()
        #expect(session.isPresented == false)
        #expect(session.activePartnerDeviceID == nil)
        session.open(with: bob)
        #expect(session.activePartnerDeviceID == bob)
    }

    // MARK: - Names

    @Test func chatTitleUsesThePersonsNameNotIPhone() {
        let nodes = grid(with: [(alice, "Alice"), (bob, "iPhone")])
        #expect(ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: alice,
            currentDeviceID: me,
            gridNodes: nodes
        ) == "Alice")
        #expect(ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: bob,
            currentDeviceID: me,
            gridNodes: nodes
        ) == ProfileDisplayNameLogic.fallbackTitle)
        #expect(ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: me,
            currentDeviceID: me,
            gridNodes: nodes
        ) == "You")
    }

    /// Build 13 screenshot header: "iPhone (001063.2...)".
    @Test func chatTitleNeverUsesDeviceNamePlusTruncatedUserID() {
        var nodes = GridPlacementLogic.makeEmptyGrid(size: 2)
        let bryan = UserProfile(
            userID: "001063.28ebae77f6d04f83adac5a0d9d70a1ae.1943",
            deviceID: "1943-DEVICE",
            deviceName: "iPhone"
        )
        GridPlacementLogic.place(profile: bryan, in: &nodes, at: 0, col: 1)
        let title = ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: "1943-DEVICE",
            currentDeviceID: me,
            gridNodes: nodes
        )
        #expect(title != "iPhone (001063.2...)")
        #expect(title.contains("001063") == false)
        #expect(title != "iPhone")
        #expect(bryan.displayName != "iPhone (001063.2...)")
        #expect(title == ProfileDisplayNameLogic.fallbackTitle)
    }

    @Test func deviceLikeNamesAreRejected() {
        #expect(ProfileDisplayNameLogic.isMissingPersonName("iPhone"))
        #expect(ProfileDisplayNameLogic.isMissingPersonName("Bryan’s iPhone"))
        #expect(ProfileDisplayNameLogic.isMissingPersonName("iPhone 16 Pro"))
        #expect(ProfileDisplayNameLogic.isMissingPersonName("Unknown Device"))
        #expect(ProfileDisplayNameLogic.isMissingPersonName(""))
        #expect(ProfileDisplayNameLogic.isUsablePersonName("Sam"))
        #expect(ProfileDisplayNameLogic.isUsablePersonName("iPhone") == false)
        #expect(ProfileDisplayNameLogic.formattedAppleName(givenName: "Sam", familyName: "Lee") == "Sam Lee")
        #expect(ProfileDisplayNameLogic.formattedAppleName(givenName: nil, familyName: nil) == nil)
    }

    @Test func bannerTitleNeverUsesIPhone() {
        #expect(MessageBannerLogic.title(senderName: "Maya") == "Maya")
        #expect(MessageBannerLogic.title(senderName: "iPhone") == MessageBannerLogic.fallbackTitle)
        #expect(MessageBannerLogic.title(senderName: "Maya’s iPhone") == MessageBannerLogic.fallbackTitle)
    }

    @Test func senderCacheSkipsDeviceNames() {
        let defaults = UserDefaults(suiteName: "grid.messaging.suite.names")!
        defaults.removePersistentDomain(forName: "grid.messaging.suite.names")
        SenderNameCache.store("iPhone", for: alice, defaults: defaults)
        SenderNameCache.store("Alice", for: alice, defaults: defaults)
        #expect(SenderNameCache.name(for: alice, defaults: defaults) == "Alice")
    }

    // MARK: - Notifications

    @Test func bannerSkipsWhenThatChatIsOpen() {
        #expect(MessageBannerLogic.shouldAnnounce(
            senderDeviceID: alice,
            currentDeviceID: me,
            viewingDeviceID: alice
        ) == false)
        #expect(MessageBannerLogic.shouldAnnounce(
            senderDeviceID: alice,
            currentDeviceID: me,
            viewingDeviceID: bob
        ))
        #expect(MessageBannerLogic.shouldAnnounce(
            senderDeviceID: me,
            currentDeviceID: me,
            viewingDeviceID: nil
        ) == false)
    }

    @Test func bannerPreviewHidesCiphertextAndLabelsPhotos() {
        var photo = message(id: "p", from: alice, to: me, text: MessageBannerLogic.encryptedImagePlaceholder)
        photo.encryptedImageData = "abc"
        #expect(MessageBannerLogic.previewText(message: photo, decryptedText: nil) == MessageBannerLogic.photoBody)

        let encrypted = message(id: "e", from: alice, to: me, text: MessageBannerLogic.encryptedTextPlaceholder)
        #expect(MessageBannerLogic.previewText(message: encrypted, decryptedText: nil) == MessageBannerLogic.genericBody)
        #expect(MessageBannerLogic.previewText(message: encrypted, decryptedText: "coffee?") == "coffee?")
    }

    // MARK: - Inbox / delivery

    @Test func staleQueryDoesNotDropAPushedMessageFromAnotherThread() {
        let alicePush = message(id: "a-push", from: alice, to: me, text: "new from alice")
        let bobOld = message(id: "b-old", from: bob, to: me, text: "old from bob", at: Date(timeIntervalSince1970: 50))
        let merged = MessageInboxLogic.merge(local: [bobOld, alicePush], incoming: [bobOld])
        let aliceThread = MessageConversationLogic.messages(
            inConversationWith: alice,
            currentDeviceID: me,
            from: merged
        )
        let bobThread = MessageConversationLogic.messages(
            inConversationWith: bob,
            currentDeviceID: me,
            from: merged
        )
        #expect(aliceThread.map(\.id) == ["a-push"])
        #expect(bobThread.map(\.id) == ["b-old"])
    }

    @Test func duplicateRecordIDDoesNotCreateTwoBubbles() {
        let first = message(id: "same", from: alice, to: me, text: "hi")
        let again = message(id: "same", from: alice, to: me, text: "hi")
        let merged = MessageInboxLogic.merge(local: [first], incoming: [again])
        #expect(merged.filter { $0.id == "same" }.count == 1)
    }

    @Test func unreadCountIsPerPersonID() {
        let messages = [
            message(id: "a1", from: alice, to: me, text: "a1"),
            message(id: "a2", from: alice, to: me, text: "a2"),
            message(id: "b1", from: bob, to: me, text: "b1"),
            message(id: "mine", from: me, to: alice, text: "reply", status: .sent),
        ]
        #expect(MessageReadLogic.unreadCount(from: alice, currentDeviceID: me, messages: messages, readReceipts: ["a1"]) == 1)
        #expect(MessageReadLogic.unreadCount(from: bob, currentDeviceID: me, messages: messages, readReceipts: []) == 1)
        #expect(MessageReadLogic.unreadCount(from: alice, currentDeviceID: me, messages: messages, readReceipts: ["a1", "a2"]) == 0)
    }

    @Test func blockedPersonCannotBeMessaged() {
        let blocked = GridMessagingLogic.canMessage(
            isBlocked: true,
            proximityAllowed: true,
            proximityReason: "Ready to message"
        )
        #expect(blocked.allowed == false)
    }
}

@MainActor
struct MessagingAppGridIdentityTests {

    @Test func addingTheSameSenderTwiceDoesNotCreateASecondCell() {
        let viewModel = GridViewModel()
        viewModel.initializeGrid()
        let sender = UserProfile(userID: "u-alice", deviceID: "alice-DEVICE", deviceName: "Alice")
        viewModel.addProfileToGrid(sender)
        viewModel.addProfileToGrid(sender)
        let matches = viewModel.allGridNodes.flatMap { $0 }.compactMap(\.userProfile).filter { $0.deviceID == "alice-DEVICE" }
        #expect(matches.count == 1)
        #expect(viewModel.hasProfileOnAnyGrid(deviceID: "alice-DEVICE"))
    }

    @Test func overlayViewModelMatchesTheTappedPerson() {
        let viewModel = GridViewModel()
        viewModel.openChatOverlay(with: "1713-DEVICE")
        #expect(viewModel.chatOverlaySession.activePartnerDeviceID == "1713-DEVICE")
        #expect(viewModel.currentChatRecipientDeviceID == "1713-DEVICE")
        viewModel.openChatOverlay(with: "0041-DEVICE")
        #expect(viewModel.chatOverlaySession.activePartnerDeviceID == "0041-DEVICE")
        #expect(viewModel.currentChatRecipientDeviceID == "0041-DEVICE")
        viewModel.hideChatOverlay()
        #expect(viewModel.chatOverlaySession.activePartnerDeviceID == nil)
        #expect(viewModel.currentChatRecipientDeviceID == nil)
    }

    @Test func harnessPeopleAreKeyedByTheirDeviceIDs() {
        let viewModel = GridViewModel()
        viewModel.installUITestFixtures()
        let occupied = viewModel.gridNodes.flatMap { $0 }.filter { $0.userProfile != nil }
        for node in occupied {
            #expect(node.id == node.userProfile?.deviceID)
        }
        let ids = occupied.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(GridUITestHarness.alice.deviceID))
        #expect(ids.contains(GridUITestHarness.bob.deviceID))
    }
}
