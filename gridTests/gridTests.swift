//
//  gridTests.swift
//  gridTests
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import Testing
import Foundation
import CryptoKit
import CloudKit
@testable import grid

/// Exercises the keychain-free ECIES envelope primitives directly, using
/// explicitly generated Curve25519 keys. This validates the actual encryption
/// without depending on the keychain (which is unavailable in the unsigned
/// test host) and mirrors how `encrypt`/`decrypt` operate.
struct CryptoServiceTests {

    /// A fresh Curve25519 key pair as base64 strings, matching CryptoService's format.
    private func makeKeyPair() -> (publicKey: String, privateKey: String) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (priv.publicKey.rawRepresentation.base64EncodedString(),
                priv.rawRepresentation.base64EncodedString())
    }

    @Test func textRoundTripSucceeds() throws {
        let crypto = CryptoService.shared
        let keys = makeKeyPair()

        let plaintext = "Meet me at the corner cafe at 7pm 🔐"
        let envelope = try #require(crypto.sealEnvelope(Data(plaintext.utf8), recipientPublicKeysBase64: [keys.publicKey]))

        let decrypted = crypto.openEnvelope(envelope, privateKeyBase64: keys.privateKey)
        #expect(decrypted.map { String(decoding: $0, as: UTF8.self) } == plaintext)
    }

    @Test func bothSenderAndRecipientCanDecrypt() throws {
        // A message wrapped to two recipients must be readable by either key —
        // this is what lets the sender read their own sent history.
        let crypto = CryptoService.shared
        let recipient = makeKeyPair()
        let sender = makeKeyPair()

        let plaintext = "shared secret"
        let envelope = try #require(crypto.sealEnvelope(
            Data(plaintext.utf8),
            recipientPublicKeysBase64: [recipient.publicKey, sender.publicKey]
        ))

        #expect(crypto.openEnvelope(envelope, privateKeyBase64: recipient.privateKey).map { String(decoding: $0, as: UTF8.self) } == plaintext)
        #expect(crypto.openEnvelope(envelope, privateKeyBase64: sender.privateKey).map { String(decoding: $0, as: UTF8.self) } == plaintext)
    }

    @Test func ciphertextDoesNotContainPlaintext() throws {
        // Regression guard: the previous implementation embedded the symmetric
        // key, so the message was effectively recoverable. The envelope must
        // not contain the readable message bytes.
        let crypto = CryptoService.shared
        let keys = makeKeyPair()

        let marker = "SECRET-MARKER-STRING-12345"
        let envelope = try #require(crypto.sealEnvelope(Data(marker.utf8), recipientPublicKeysBase64: [keys.publicKey]))

        let asString = String(decoding: envelope, as: UTF8.self)
        #expect(!asString.contains(marker))
    }

    @Test func decryptWithWrongKeyFails() throws {
        let crypto = CryptoService.shared
        let recipient = makeKeyPair()

        let envelope = try #require(crypto.sealEnvelope(Data("private".utf8), recipientPublicKeysBase64: [recipient.publicKey]))

        // A different key pair must not be able to decrypt.
        let attacker = makeKeyPair()
        #expect(crypto.openEnvelope(envelope, privateKeyBase64: attacker.privateKey) == nil)
    }

    @Test func imageRoundTripSucceeds() throws {
        let crypto = CryptoService.shared
        let keys = makeKeyPair()

        let original = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
        let envelope = try #require(crypto.sealEnvelope(original, recipientPublicKeysBase64: [keys.publicKey]))

        #expect(crypto.openEnvelope(envelope, privateKeyBase64: keys.privateKey) == original)
    }

    @Test func tamperedEnvelopeFailsToDecrypt() throws {
        let crypto = CryptoService.shared
        let keys = makeKeyPair()

        var envelope = try #require(crypto.sealEnvelope(Data("integrity".utf8), recipientPublicKeysBase64: [keys.publicKey]))
        // Flip a byte near the end (inside the AES-GCM ciphertext/tag region).
        envelope[envelope.count - 1] ^= 0xFF

        #expect(crypto.openEnvelope(envelope, privateKeyBase64: keys.privateKey) == nil)
    }
}

@MainActor
struct ContentModerationTests {

    @Test func emptyTextIsRejected() {
        let service = ContentModerationService()
        #expect(service.isTextAppropriate("   ").isAppropriate == false)
    }

    @Test func normalTextIsAllowed() {
        let service = ContentModerationService()
        #expect(service.isTextAppropriate("Hey, want to grab coffee later?").isAppropriate)
    }

    @Test func bioWithEmailIsRejected() {
        let service = ContentModerationService()
        let result = service.isBioAppropriate("Reach me at john.doe@example.com")
        #expect(result.isAppropriate == false)
    }

    @Test func spammyMessageIsRejected() {
        let service = ContentModerationService()
        #expect(service.isMessageAppropriate("BUY NOW limited time offer").isAppropriate == false)
    }

    @Test func overlongBioIsRejected() {
        let service = ContentModerationService()
        let longBio = String(repeating: "a", count: 600)
        #expect(service.isBioAppropriate(longBio).isAppropriate == false)
    }
}

/// Exercises the pure `Album` model logic (pin cap, dedupe, removal, and
/// CKRecord round-tripping) without touching CloudKit.
struct AlbumTests {

    /// A throwaway local CKAsset backed by a temp file (no network needed).
    private func makeAsset() throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0x01, 0x02, 0x03]).write(to: url)
        return CKAsset(fileURL: url)
    }

    private func makeMetadata(storyID: String) -> PhotoMetadata {
        PhotoMetadata(storyID: storyID, originalStoryDate: Date(), caption: nil)
    }

    @Test func newAlbumIsEmptyWithSpace() {
        let album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        #expect(album.photosCount == 0)
        #expect(album.hasSpace)
    }

    @Test func addPhotoPinsStory() throws {
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        let added = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s1"))
        #expect(added)
        #expect(album.photosCount == 1)
        #expect(album.isPhotoPinned(storyID: "s1"))
    }

    @Test func cannotPinSameStoryTwice() throws {
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        _ = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s1"))
        let again = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s1"))
        #expect(again == false)
        #expect(album.photosCount == 1)
    }

    @Test func enforcesMaxOfThree() throws {
        #expect(Album.maxPhotos == 3)
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        for i in 0..<Album.maxPhotos {
            #expect(album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s\(i)")))
        }
        #expect(album.photosCount == 3)
        #expect(album.hasSpace == false)

        // A fourth pin must be rejected and leave the album unchanged.
        let overflow = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "extra"))
        #expect(overflow == false)
        #expect(album.photosCount == 3)
    }

    @Test func removePhotoKeepsAssetsAndMetadataInSync() throws {
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        _ = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s1"))
        _ = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s2"))

        let removed = album.removePhoto(storyID: "s1")
        #expect(removed)
        #expect(album.photosCount == 1)
        #expect(album.pinnedPhotos.count == album.photoMetadata.count)
        #expect(album.isPhotoPinned(storyID: "s1") == false)
        #expect(album.isPhotoPinned(storyID: "s2"))
    }

    @Test func removingMissingStoryReturnsFalse() {
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1")
        #expect(album.removePhoto(storyID: "nope") == false)
    }

    @Test func recordRoundTripPreservesMetadata() throws {
        var album = Album(ownerUserID: "u1", ownerDeviceID: "d1", title: "My Album")
        _ = album.addPhoto(asset: try makeAsset(), metadata: makeMetadata(storyID: "s1"))

        let restored = try #require(Album(record: album.toCKRecord()))
        #expect(restored.ownerDeviceID == "d1")
        #expect(restored.title == "My Album")
        #expect(restored.photoMetadata.count == 1)
        #expect(restored.photoMetadata.first?.storyID == "s1")
    }
}

// MARK: - Grid column zoom logic

struct GridColumnZoomLogicTests {

    /// Mirrors production formula so expectations are not magic numbers.
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
            showingStarredOnly: false,
            starredUserIDs: [],
            blockedUserIDs: ["blocked"],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [],
            isDemoMode: false
        )
        #expect(filtered.map(\.userID) == ["ok"])
    }

    @Test func applyDisplayFiltersRemovesUsersWhoBlockedMe() {
        let profiles = [profile(userID: "hostile", deviceID: "h1")]
        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            showingStarredOnly: false,
            starredUserIDs: [],
            blockedUserIDs: [],
            usersWhoBlockedMe: ["hostile"],
            selectedInterestFilter: [],
            isDemoMode: false
        )
        #expect(filtered.isEmpty)
    }

    @Test func applyDisplayFiltersStarredBlockAndInterestsCombined() {
        let profiles = [
            profile(userID: "star", deviceID: "s1", interests: [.music]),
            profile(userID: "blocked", deviceID: "b1"),
            profile(userID: "match", deviceID: "m1", interests: [.foodie]),
            profile(userID: "nomatch", deviceID: "n1", interests: [.running]),
        ]

        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            showingStarredOnly: true,
            starredUserIDs: ["star", "match"],
            blockedUserIDs: ["blocked"],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [.foodie],
            isDemoMode: false
        )

        #expect(filtered.map(\.userID) == ["match"])
    }

    @Test func demoModeSkipsStarAndBlockFilters() {
        let profiles = [
            profile(userID: "blocked", deviceID: "b1"),
            profile(userID: "other", deviceID: "o1"),
        ]

        let filtered = GridProfileFilterLogic.applyDisplayFilters(
            to: profiles,
            showingStarredOnly: true,
            starredUserIDs: [],
            blockedUserIDs: ["blocked"],
            usersWhoBlockedMe: [],
            selectedInterestFilter: [],
            isDemoMode: true
        )

        #expect(filtered.count == 2)
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
