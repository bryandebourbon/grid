import Testing
import Foundation
import CryptoKit
@testable import grid

/// In-memory stand-in for the public CloudKit database.
/// Fetch-by-record-ID is immediate. Queries only see records that have been indexed,
/// which is the lag that emptied the chat on real phones.
final class FakePublicMessageDB {
    private var records: [String: Message] = [:]
    var indexedIDs: Set<String> = []

    func save(_ message: Message) {
        records[message.id] = message
    }

    func fetchByID(_ id: String) -> Message? {
        records[id]
    }

    func queryReceived(by deviceID: String) -> [Message] {
        records.values.filter { message in
            message.recipientDeviceID == deviceID && indexedIDs.contains(message.id)
        }
    }

    func indexAll() {
        indexedIDs = Set(records.keys)
    }
}

/// One side of an A↔B conversation: pending push IDs + local inbox.
struct SimulatedPhone {
    let deviceID: String
    var messages: [Message] = []
    var pendingRecordIDs: [String] = []

    mutating func handlePush(recordID: String, db: FakePublicMessageDB) {
        if pendingRecordIDs.contains(recordID) == false {
            pendingRecordIDs.append(recordID)
        }
        guard let fetched = db.fetchByID(recordID) else { return }
        pendingRecordIDs.removeAll { $0 == recordID }
        messages = MessageInboxLogic.merge(local: messages, incoming: [fetched])
    }

    /// Background fetch was killed: remember the ID, do not fetch yet.
    mutating func rememberPush(recordID: String) {
        if pendingRecordIDs.contains(recordID) == false {
            pendingRecordIDs.append(recordID)
        }
    }

    mutating func retryPending(db: FakePublicMessageDB) {
        let pending = pendingRecordIDs
        for recordID in pending {
            handlePush(recordID: recordID, db: db)
        }
    }

    mutating func refreshFromQuery(db: FakePublicMessageDB) {
        messages = MessageInboxLogic.merge(
            local: messages,
            incoming: db.queryReceived(by: deviceID)
        )
    }

    func thread(with otherDeviceID: String) -> [Message] {
        MessageConversationLogic.messages(
            inConversationWith: otherDeviceID,
            currentDeviceID: deviceID,
            from: messages
        )
    }
}

struct TwoPeerMessageReliabilityTests {

    private func keyPair() -> (publicKey: String, privateKey: String) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (
            priv.publicKey.rawRepresentation.base64EncodedString(),
            priv.rawRepresentation.base64EncodedString()
        )
    }

    private func encryptedMessage(
        id: String,
        from sender: String,
        to recipient: String,
        plaintext: String,
        recipientPublicKey: String,
        senderPublicKey: String
    ) -> Message {
        let envelope = CryptoService.shared.sealEnvelope(
            Data(plaintext.utf8),
            recipientPublicKeysBase64: [recipientPublicKey, senderPublicKey]
        )!
        var message = Message(
            id: id,
            senderDeviceID: sender,
            recipientDeviceID: recipient,
            senderUserID: "u-\(sender)",
            recipientUserID: "u-\(recipient)",
            text: MessageBannerLogic.encryptedTextPlaceholder,
            status: .received
        )
        message.isEncrypted = true
        message.encryptedContent = envelope.base64EncodedString()
        return message
    }

    @Test func pushFetchShowsMessageWhileQueryIsStillStale() throws {
        let alice = keyPair()
        let bob = keyPair()
        let plaintext = "want to get coffee?"
        let recordID = "msg-coffee"
        let db = FakePublicMessageDB()

        db.save(encryptedMessage(
            id: recordID,
            from: "alice-sim",
            to: "bob-sim",
            plaintext: plaintext,
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        ))

        var phoneB = SimulatedPhone(deviceID: "bob-sim")
        phoneB.handlePush(recordID: recordID, db: db)
        phoneB.refreshFromQuery(db: db)

        let thread = phoneB.thread(with: "alice-sim")
        #expect(thread.map(\.id) == [recordID])

        let stored = thread[0]
        let encoded = try #require(stored.encryptedContent)
        let data = try #require(Data(base64Encoded: encoded))
        let decrypted = try #require(CryptoService.shared.openEnvelope(data, privateKeyBase64: bob.privateKey))
        let text = String(decoding: decrypted, as: UTF8.self)
        #expect(text == plaintext)
        #expect(MessageBannerLogic.previewText(message: stored, decryptedText: text) == plaintext)
        #expect(MessageBannerLogic.shouldAnnounce(
            senderDeviceID: "alice-sim",
            currentDeviceID: "bob-sim",
            viewingDeviceID: nil
        ))
    }

    @Test func killedBackgroundFetchIsRepairedByPendingRecordID() {
        let alice = keyPair()
        let bob = keyPair()
        let db = FakePublicMessageDB()
        let recordID = "msg-late"
        db.save(encryptedMessage(
            id: recordID,
            from: "alice-sim",
            to: "bob-sim",
            plaintext: "still here",
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        ))

        var phoneB = SimulatedPhone(deviceID: "bob-sim")
        phoneB.rememberPush(recordID: recordID)
        phoneB.refreshFromQuery(db: db)
        #expect(phoneB.thread(with: "alice-sim").isEmpty)

        phoneB.retryPending(db: db)
        #expect(phoneB.thread(with: "alice-sim").map(\.id) == [recordID])
    }

    @Test func queryCatchupDoesNotDuplicatePushedMessage() {
        let alice = keyPair()
        let bob = keyPair()
        let db = FakePublicMessageDB()
        let recordID = "msg-once"
        db.save(encryptedMessage(
            id: recordID,
            from: "alice-sim",
            to: "bob-sim",
            plaintext: "one bubble",
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        ))

        var phoneB = SimulatedPhone(deviceID: "bob-sim")
        phoneB.handlePush(recordID: recordID, db: db)
        db.indexAll()
        phoneB.refreshFromQuery(db: db)

        #expect(phoneB.thread(with: "alice-sim").map(\.id) == [recordID])
    }

    @Test func pushFetchShowsImageWhileQueryIsStillStale() {
        let alice = keyPair()
        let bob = keyPair()
        let db = FakePublicMessageDB()
        let recordID = "msg-photo"
        var photo = encryptedMessage(
            id: recordID,
            from: "alice-sim",
            to: "bob-sim",
            plaintext: MessageBannerLogic.encryptedImagePlaceholder,
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        )
        photo.encryptedImageData = "cGhvdG8="
        db.save(photo)

        var phoneB = SimulatedPhone(deviceID: "bob-sim")
        phoneB.handlePush(recordID: recordID, db: db)
        phoneB.refreshFromQuery(db: db)

        let thread = phoneB.thread(with: "alice-sim")
        #expect(thread.map(\.id) == [recordID])
        #expect(thread[0].encryptedImageData == "cGhvdG8=")
        #expect(MessageBannerLogic.previewText(message: thread[0], decryptedText: nil) == MessageBannerLogic.photoBody)
    }

    @Test func pendingImageRetrySurvivesKilledBackgroundFetch() {
        let alice = keyPair()
        let bob = keyPair()
        let db = FakePublicMessageDB()
        let recordID = "msg-photo-late"
        var photo = encryptedMessage(
            id: recordID,
            from: "alice-sim",
            to: "bob-sim",
            plaintext: MessageBannerLogic.encryptedImagePlaceholder,
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        )
        photo.encryptedImageData = "cGhvdG8="
        db.save(photo)

        var phoneB = SimulatedPhone(deviceID: "bob-sim")
        phoneB.rememberPush(recordID: recordID)
        phoneB.refreshFromQuery(db: db)
        #expect(phoneB.thread(with: "alice-sim").isEmpty)

        phoneB.retryPending(db: db)
        #expect(phoneB.thread(with: "alice-sim").map(\.id) == [recordID])
        #expect(phoneB.thread(with: "alice-sim")[0].encryptedImageData != nil)
    }

    @Test func encryptedImageRoundTripDecrypts() throws {
        let alice = keyPair()
        let bob = keyPair()
        let pixels = Data([0xFF, 0xD8, 0xFF, 0xD9, 0x01, 0x02, 0x03])
        let envelope = try #require(CryptoService.shared.sealEnvelope(
            pixels,
            recipientPublicKeysBase64: [bob.publicKey, alice.publicKey]
        ))
        let opened = try #require(CryptoService.shared.openEnvelope(envelope, privateKeyBase64: bob.privateKey))
        #expect(opened == pixels)
        var message = encryptedMessage(
            id: "img-rt",
            from: "alice-sim",
            to: "bob-sim",
            plaintext: MessageBannerLogic.encryptedImagePlaceholder,
            recipientPublicKey: bob.publicKey,
            senderPublicKey: alice.publicKey
        )
        message.encryptedImageData = envelope.base64EncodedString()
        #expect(MessageBannerLogic.previewText(message: message, decryptedText: nil) == MessageBannerLogic.photoBody)
    }

    @Test func deliverySuiteReportListsEveryStep() {
        var report = MessageDeliverySuiteReport()
        report.add(name: "text.save", ok: true, detail: "id=ABC", milliseconds: 40)
        report.add(name: "image.decrypt", ok: false, detail: "Failed to decrypt image", milliseconds: 12)
        #expect(report.allPassed == false)
        #expect(report.summary.contains("1. text.save OK 40ms"))
        #expect(report.summary.contains("2. image.decrypt FAIL 12ms"))
        #expect(report.summary.contains("[msg-test]"))
    }

    @Test func twoSimulatorsOnOneAppleIDGetDistinctDeviceIDs() {
        let userID = "001234.abcdef"
        let alice = DeviceIdentityLogic.deviceID(
            forAppleUserID: userID,
            stored: nil,
            peerToken: "AAAA1111"
        )
        let bob = DeviceIdentityLogic.deviceID(
            forAppleUserID: userID,
            stored: nil,
            peerToken: "BBBB2222"
        )
        let phone = DeviceIdentityLogic.deviceID(
            forAppleUserID: userID,
            stored: nil,
            peerToken: nil
        )
        #expect(alice != bob)
        #expect(alice != phone)
        #expect(alice == "abcdef-AAAA1111-DEVICE")
        #expect(phone == "abcdef-DEVICE")
    }
}
