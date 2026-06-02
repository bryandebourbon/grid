import Foundation
import CryptoKit
import Security
import os

/// Provides real ECIES-style encryption for Grid messages.
///
/// Design notes:
/// - Each device owns a long-term Curve25519 key-agreement key pair. The public
///   key is published (via `EncryptionProfile`) so others can encrypt to it.
/// - A message is encrypted once with a fresh random AES-256-GCM content key.
///   That content key is then wrapped (via ephemeral ECDH + HKDF + AES-GCM) to
///   *both* the recipient's public key and the sender's own public key, so that
///   both parties can read the conversation — without ever storing the key in
///   the clear (the previous implementation prepended the symmetric key as
///   plaintext, which provided no confidentiality at all).
final class CryptoService {
    static let shared = CryptoService()

    private let keychain = KeychainService()

    // v2 tags: switched from P256.Signing keys (unusable for key agreement) to
    // Curve25519 key-agreement keys. Old v1 keys are ignored so a fresh, valid
    // key pair is generated and re-published on next launch.
    private let keychainPrivateKeyTag = "com.bryandebourbon.grid.privateKey.v2"
    private let keychainPublicKeyTag = "com.bryandebourbon.grid.publicKey.v2"

    // Stable HKDF context. Must remain identical across all clients/versions so
    // derived key-encryption keys match. Changing these breaks decryption of
    // previously sent messages.
    private let hkdfSalt = Data("com.bryandebourbon.grid.ecies.salt.v1".utf8)
    private let hkdfInfo = Data("grid-message-key-wrap".utf8)

    /// Curve25519 raw public/private keys are always 32 bytes.
    private let rawKeyLength = 32
    /// Envelope format version, stored as the first byte of every payload.
    private let envelopeVersion: UInt8 = 1

    private let log = Logger(subsystem: "com.bryandebourbon.grid", category: "CryptoService")

    private init() {}

    // MARK: - Key Generation

    @discardableResult
    func generateKeyPair() -> (publicKey: String, privateKey: String)? {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        let privateKeyString = privateKey.rawRepresentation.base64EncodedString()
        let publicKeyString = publicKey.rawRepresentation.base64EncodedString()

        guard keychain.save(privateKeyString, forKey: keychainPrivateKeyTag),
              keychain.save(publicKeyString, forKey: keychainPublicKeyTag) else {
            log.error("Failed to persist generated key pair to keychain")
            return nil
        }

        return (publicKeyString, privateKeyString)
    }

    // MARK: - Key Retrieval

    func getPublicKey() -> String? {
        keychain.load(forKey: keychainPublicKeyTag)
    }

    func getPrivateKey() -> String? {
        keychain.load(forKey: keychainPrivateKeyTag)
    }

    func hasEncryptionKeys() -> Bool {
        getPublicKey() != nil && getPrivateKey() != nil
    }

    // MARK: - Public API (signatures preserved for existing call sites)

    func encrypt(text: String, withPublicKey publicKeyString: String) -> Data? {
        guard let messageData = text.data(using: .utf8) else { return nil }
        return seal(messageData, recipientPublicKeyBase64: publicKeyString)
    }

    func decrypt(data: Data, withPrivateKey privateKeyString: String) -> String? {
        guard let plaintext = openEnvelope(data, privateKeyBase64: privateKeyString) else { return nil }
        return String(data: plaintext, encoding: .utf8)
    }

    func encryptImage(data: Data, withPublicKey publicKeyString: String) -> Data? {
        seal(data, recipientPublicKeyBase64: publicKeyString)
    }

    func decryptImage(data: Data, withPrivateKey privateKeyString: String) -> Data? {
        openEnvelope(data, privateKeyBase64: privateKeyString)
    }

    // MARK: - Core ECIES envelope

    /// Encrypts `plaintext` so that both the recipient and the local sender can
    /// later decrypt it.
    private func seal(_ plaintext: Data, recipientPublicKeyBase64: String) -> Data? {
        // Collect the public keys that should be able to read this message:
        // the recipient, plus the sender (so they can read their own history).
        var recipients = [recipientPublicKeyBase64]
        if let ownPublicBase64 = getPublicKey(), ownPublicBase64 != recipientPublicKeyBase64 {
            recipients.append(ownPublicBase64)
        }
        return sealEnvelope(plaintext, recipientPublicKeysBase64: recipients)
    }

    /// Keychain-free envelope construction. Encrypts `plaintext` once with a
    /// random content key, then wraps that key (ephemeral ECDH + HKDF + AES-GCM)
    /// to each recipient public key. Exposed at module scope for testing and
    /// reuse. Returns: `[version][slotCount]([len:2][slot])...[ciphertext]`.
    func sealEnvelope(_ plaintext: Data, recipientPublicKeysBase64 recipients: [String]) -> Data? {
        let recipientKeys = recipients.compactMap { publicKey(fromBase64: $0) }
        guard !recipientKeys.isEmpty else {
            log.error("sealEnvelope: no valid recipient public keys")
            return nil
        }

        do {
            // 1. Random content key, used to encrypt the payload exactly once.
            let contentKey = SymmetricKey(size: .bits256)
            let sealedContent = try AES.GCM.seal(plaintext, using: contentKey)
            guard let ciphertext = sealedContent.combined else { return nil }

            // 2. Wrap the content key to each recipient.
            let contentKeyData = contentKey.withUnsafeBytes { Data($0) }
            var wrappedSlots: [Data] = []
            for recipient in recipientKeys {
                guard let wrapped = wrapKey(contentKeyData, to: recipient) else { return nil }
                wrappedSlots.append(wrapped)
            }

            // 3. Assemble envelope.
            var envelope = Data()
            envelope.append(envelopeVersion)
            envelope.append(UInt8(wrappedSlots.count))
            for slot in wrappedSlots {
                var len = UInt16(slot.count).bigEndian
                withUnsafeBytes(of: &len) { envelope.append(contentsOf: $0) }
                envelope.append(slot)
            }
            envelope.append(ciphertext)
            return envelope
        } catch {
            log.error("sealEnvelope: encryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decrypts an envelope produced by `sealEnvelope` using the given private key.
    func openEnvelope(_ envelope: Data, privateKeyBase64: String) -> Data? {
        guard let privateKeyData = Data(base64Encoded: privateKeyBase64),
              let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData) else {
            return nil
        }

        var cursor = envelope.startIndex

        func read(_ count: Int) -> Data? {
            guard count >= 0, envelope.distance(from: cursor, to: envelope.endIndex) >= count else { return nil }
            let end = envelope.index(cursor, offsetBy: count)
            let slice = envelope[cursor..<end]
            cursor = end
            return Data(slice)
        }

        guard let versionByte = read(1)?.first, versionByte == envelopeVersion,
              let slotCountByte = read(1)?.first else {
            return nil
        }

        let slotCount = Int(slotCountByte)
        var wrappedSlots: [Data] = []
        for _ in 0..<slotCount {
            guard let lenData = read(2) else { return nil }
            let length = Int(UInt16(bigEndian: lenData.withUnsafeBytes { $0.load(as: UInt16.self) }))
            guard let slot = read(length) else { return nil }
            wrappedSlots.append(slot)
        }

        let ciphertext = Data(envelope[cursor..<envelope.endIndex])
        guard !ciphertext.isEmpty else { return nil }

        // Try each wrapped slot until one unwraps with our private key.
        for slot in wrappedSlots {
            guard let contentKeyData = unwrapKey(slot, with: privateKey) else { continue }
            let contentKey = SymmetricKey(data: contentKeyData)
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
                return try AES.GCM.open(sealedBox, using: contentKey)
            } catch {
                log.error("open: content decryption failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    /// Wraps `keyData` to `recipient` using an ephemeral ECDH key agreement.
    /// Returns `[ephemeralPublicKey(32)][AES-GCM combined]`.
    private func wrapKey(_ keyData: Data, to recipient: Curve25519.KeyAgreement.PublicKey) -> Data? {
        do {
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
            let kek = shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: hkdfSalt,
                sharedInfo: hkdfInfo,
                outputByteCount: 32
            )
            let sealed = try AES.GCM.seal(keyData, using: kek)
            guard let combined = sealed.combined else { return nil }
            return ephemeral.publicKey.rawRepresentation + combined
        } catch {
            log.error("wrapKey failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reverses `wrapKey` using the local private key.
    private func unwrapKey(_ slot: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) -> Data? {
        guard slot.count > rawKeyLength else { return nil }
        let ephemeralPubData = slot.prefix(rawKeyLength)
        let wrapped = Data(slot.suffix(from: slot.startIndex + rawKeyLength))
        do {
            let ephemeralPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPubData)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
            let kek = shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: hkdfSalt,
                sharedInfo: hkdfInfo,
                outputByteCount: 32
            )
            let sealedBox = try AES.GCM.SealedBox(combined: wrapped)
            return try AES.GCM.open(sealedBox, using: kek)
        } catch {
            // Expected when this slot was wrapped for a different key holder.
            return nil
        }
    }

    private func publicKey(fromBase64 base64: String) -> Curve25519.KeyAgreement.PublicKey? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }
}

/// Keychain wrapper that stores items as device-only, after-first-unlock, and
/// surfaces failures via the returned `OSStatus`/`Bool`.
final class KeychainService {
    private let log = Logger(subsystem: "com.bryandebourbon.grid", category: "KeychainService")

    @discardableResult
    func save(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Remove any existing item, then add the new one.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Keychain save failed for key (status: \(status))")
            return false
        }
        return true
    }

    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                log.error("Keychain load failed for key (status: \(status))")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
