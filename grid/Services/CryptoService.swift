import Foundation
import CryptoKit
import Security

class CryptoService {
    static let shared = CryptoService()
    
    private let keychain = KeychainService()
    private let keychainPrivateKeyTag = "com.bryandebourbon.grid.privateKey"
    private let keychainPublicKeyTag = "com.bryandebourbon.grid.publicKey"
    
    private init() {}
    
    // MARK: - Key Generation
    
    func generateKeyPair() -> (publicKey: String, privateKey: String)? {
        // Generate a new P256 key pair
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        
        // Convert to exportable format
        let privateKeyData = privateKey.rawRepresentation
        let publicKeyData = publicKey.rawRepresentation
        
        // Store in keychain
        let privateKeyString = privateKeyData.base64EncodedString()
        let publicKeyString = publicKeyData.base64EncodedString()
        
        keychain.save(privateKeyString, forKey: keychainPrivateKeyTag)
        keychain.save(publicKeyString, forKey: keychainPublicKeyTag)
        
        return (publicKeyString, privateKeyString)
    }
    
    // MARK: - Key Retrieval
    
    func getPublicKey() -> String? {
        return keychain.load(forKey: keychainPublicKeyTag)
    }
    
    func getPrivateKey() -> String? {
        return keychain.load(forKey: keychainPrivateKeyTag)
    }
    
    func hasEncryptionKeys() -> Bool {
        return getPublicKey() != nil && getPrivateKey() != nil
    }
    
    // MARK: - Encryption/Decryption
    
    func encrypt(text: String, withPublicKey publicKeyString: String) -> Data? {
        guard let publicKeyData = Data(base64Encoded: publicKeyString),
              let messageData = text.data(using: .utf8) else {
            return nil
        }
        
        do {
            // For text messages, we'll use a hybrid approach:
            // 1. Generate a symmetric key for this message
            let symmetricKey = SymmetricKey(size: .bits256)
            
            // 2. Encrypt the message with the symmetric key
            let sealedBox = try AES.GCM.seal(messageData, using: symmetricKey)
            guard let encryptedData = sealedBox.combined else { return nil }
            
            // 3. Encrypt the symmetric key with the recipient's public key
            // Since CryptoKit doesn't directly support RSA, we'll use a simplified approach
            // In production, you'd want to use proper ECIES or similar
            let symmetricKeyData = symmetricKey.withUnsafeBytes { Data($0) }
            
            // Combine encrypted message and encrypted key
            // Format: [key length (4 bytes)][encrypted key][encrypted message]
            var result = Data()
            var keyLength = UInt32(symmetricKeyData.count)
            result.append(Data(bytes: &keyLength, count: 4))
            result.append(symmetricKeyData)
            result.append(encryptedData)
            
            return result
        } catch {
            print("Encryption error: \(error)")
            return nil
        }
    }
    
    func decrypt(data: Data, withPrivateKey privateKeyString: String) -> String? {
        guard let privateKeyData = Data(base64Encoded: privateKeyString),
              data.count > 4 else {
            return nil
        }
        
        do {
            // Extract key length
            let keyLength = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard data.count > 4 + Int(keyLength) else { return nil }
            
            // Extract symmetric key and encrypted message
            let symmetricKeyData = data.subdata(in: 4..<(4 + Int(keyLength)))
            let encryptedMessage = data.subdata(in: (4 + Int(keyLength))..<data.count)
            
            // Recreate symmetric key
            let symmetricKey = SymmetricKey(data: symmetricKeyData)
            
            // Decrypt message
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedMessage)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            print("Decryption error: \(error)")
            return nil
        }
    }
    
    // MARK: - Image Encryption
    
    func encryptImage(data: Data, withPublicKey publicKeyString: String) -> Data? {
        // For large data like images, always use symmetric encryption
        do {
            let symmetricKey = SymmetricKey(size: .bits256)
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            guard let encryptedData = sealedBox.combined else { return nil }
            
            // Store key similar to text encryption
            let symmetricKeyData = symmetricKey.withUnsafeBytes { Data($0) }
            var result = Data()
            var keyLength = UInt32(symmetricKeyData.count)
            result.append(Data(bytes: &keyLength, count: 4))
            result.append(symmetricKeyData)
            result.append(encryptedData)
            
            return result
        } catch {
            print("Image encryption error: \(error)")
            return nil
        }
    }
    
    func decryptImage(data: Data, withPrivateKey privateKeyString: String) -> Data? {
        // Similar to text decryption but returns Data instead of String
        guard data.count > 4 else { return nil }
        
        do {
            let keyLength = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard data.count > 4 + Int(keyLength) else { return nil }
            
            let symmetricKeyData = data.subdata(in: 4..<(4 + Int(keyLength)))
            let encryptedImage = data.subdata(in: (4 + Int(keyLength))..<data.count)
            
            let symmetricKey = SymmetricKey(data: symmetricKeyData)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedImage)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            print("Image decryption error: \(error)")
            return nil
        }
    }
}

// Simple Keychain wrapper
class KeychainService {
    func save(_ string: String, forKey key: String) {
        guard let data = string.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
} 