//
//  gridTests.swift
//  gridTests
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import Testing
import Foundation
import CryptoKit
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
