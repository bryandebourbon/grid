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
