import Foundation
import CloudKit

enum MessageStatus: String, Codable {
    case sending
    case sent
    case failed
    case received // For incoming messages
}

struct Message: Identifiable, Codable {
    var id: String // Unique identifier for the message (e.g., UUID().uuidString)
    var recordID: CKRecord.ID? // CloudKit record ID
    let senderDeviceID: String // Device ID of the sender
    let recipientDeviceID: String // Device ID of the recipient (can be the same as senderDeviceID for self-messaging)
    let senderUserID: String // Apple User ID of the sender (for account-level tracking)
    let recipientUserID: String // Apple User ID of the recipient
    var text: String // MODIFIED: Changed to var for encryption placeholder
    var timestamp: Date // MODIFIED: Changed to var
    var isRead: Int = 0 // To track if the message has been read by the recipient (0 = unread, 1 = read)
    var status: MessageStatus // NEW: Added status property
    var imageAsset: CKAsset? // Optional image asset for photo messages
    
    // NEW: Encryption fields
    var isEncrypted: Bool = false // Whether this message is encrypted
    var encryptedContent: String? // Base64 encoded encrypted message content (when isEncrypted = true)
    var encryptedImageData: String? // Base64 encoded encrypted image data (when isEncrypted = true)
    var encryptionKeyID: String? // ID of the encryption key used

    enum CodingKeys: String, CodingKey {
        case id
        case recordID // ADDED: recordID to CodingKeys if it needs to be persisted locally (optional)
        case senderDeviceID
        case recipientDeviceID
        case senderUserID
        case recipientUserID
        case text
        case timestamp
        case isRead
        case status // ADDED: status to CodingKeys
        case isEncrypted
        case encryptedContent
        case encryptedImageData
        case encryptionKeyID
        // recordID is not directly encoded/decoded as it's managed by CloudKit interactions
        // imageAsset (CKAsset) is also not directly Codable and handled by CKRecord.
        // This comment seems to contradict adding recordID to CodingKeys.
        // For optimistic updates, we might not need to encode/decode recordID via Codable
        // if its persistence is solely handled by direct CloudKit interaction and
        // local storage is only for optimistic states before CK sync.
        // Let's remove recordID from coding keys for now, it is CK specific.
    }
    
    // Customizing Codable conformance if recordID is not part of it.
    // If you only want to encode/decode for local persistence (not for network):
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // recordID = try container.decodeIfPresent(CKRecord.ID.self, forKey: .recordID) // Example if it were codable
        senderDeviceID = try container.decode(String.self, forKey: .senderDeviceID)
        recipientDeviceID = try container.decode(String.self, forKey: .recipientDeviceID)
        senderUserID = try container.decode(String.self, forKey: .senderUserID)
        recipientUserID = try container.decode(String.self, forKey: .recipientUserID)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isRead = try container.decode(Int.self, forKey: .isRead)
        status = try container.decode(MessageStatus.self, forKey: .status)
        imageAsset = nil // CKAsset not decoded via Codable
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
        encryptedContent = try container.decodeIfPresent(String.self, forKey: .encryptedContent)
        encryptedImageData = try container.decodeIfPresent(String.self, forKey: .encryptedImageData)
        encryptionKeyID = try container.decodeIfPresent(String.self, forKey: .encryptionKeyID)
        // Note: CKRecord.ID is not inherently Codable. If you need to store it locally
        // using Codable, you'd typically store its recordName (String) or a custom representation.
        // For now, assuming recordID is managed outside of Codable persistence for this struct.
        // If you have a local cache that needs to store the CKRecord.ID as part of the Message
        // Codable representation, this part needs careful handling.
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        // try container.encodeIfPresent(recordID, forKey: .recordID) // If it were codable
        try container.encode(senderDeviceID, forKey: .senderDeviceID)
        try container.encode(recipientDeviceID, forKey: .recipientDeviceID)
        try container.encode(senderUserID, forKey: .senderUserID)
        try container.encode(recipientUserID, forKey: .recipientUserID)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(status, forKey: .status)
        try container.encode(isEncrypted, forKey: .isEncrypted)
        try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        try container.encodeIfPresent(encryptedImageData, forKey: .encryptedImageData)
        try container.encodeIfPresent(encryptionKeyID, forKey: .encryptionKeyID)
        // imageAsset (CKAsset) is not encoded.
    }

    // Initializer for creating a new message locally
    init(id: String = UUID().uuidString,
         recordID: CKRecord.ID? = nil, // Added to allow setting it if known
         senderDeviceID: String,
         recipientDeviceID: String,
         senderUserID: String,
         recipientUserID: String,
         text: String,
         timestamp: Date = Date(),
         isRead: Int = 0,
         status: MessageStatus = .sending, // Default to .sending for new optimistic messages
         imageAsset: CKAsset? = nil) {
        self.id = id
        self.recordID = recordID
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        self.status = status
        self.imageAsset = imageAsset
        self.isEncrypted = false
        self.encryptedContent = nil
        self.encryptedImageData = nil
        self.encryptionKeyID = nil
    }

    // Initializer from a CKRecord
    init?(record: CKRecord, currentDeviceID: String?) { // Added currentDeviceID to determine status
        guard let senderDeviceID = record["senderDeviceID"] as? String,
              let recipientDeviceID = record["recipientDeviceID"] as? String,
              let senderUserID = record["senderUserID"] as? String,
              let recipientUserID = record["recipientUserID"] as? String,
              let text = record["text"] as? String,
              let timestamp = record["timestamp"] as? Date else {
            print("Message init from CKRecord failed: Missing required fields.")
            return nil
        }
        
        self.id = record.recordID.recordName // Use CKRecord's name as the Message's primary ID
        self.recordID = record.recordID
        self.senderDeviceID = senderDeviceID
        self.recipientDeviceID = recipientDeviceID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.text = text
        self.timestamp = timestamp
        self.isRead = record["isRead"] as? Int ?? 0
        self.imageAsset = record["imageAsset"] as? CKAsset // Load image asset
        
        // Determine status based on who sent it and read status
        if let currentDevID = currentDeviceID, senderDeviceID == currentDevID {
            self.status = .sent // It's our own message, confirmed by server
        } else {
            // It's a message from someone else
            // If it's been read, show as sent (visual indicator for read)
            // If not read, show as received (visual indicator for unread)
            self.status = self.isRead == 1 ? .sent : .received
        }
        
        // Load encryption fields
        self.isEncrypted = (record["isEncrypted"] as? Int64 ?? 0) == 1
        self.encryptedContent = record["encryptedContent"] as? String
        self.encryptedImageData = record["encryptedImageData"] as? String
        self.encryptionKeyID = record["encryptionKeyID"] as? String
    }

    // Helper to create/update a CKRecord from this message
    func toCKRecord() -> CKRecord {
        let messageRecordID = self.recordID ?? CKRecord.ID(recordName: self.id) // Use existing id for recordName
        let record = CKRecord(recordType: "Messages", recordID: messageRecordID)
        
        record["senderDeviceID"] = self.senderDeviceID
        record["recipientDeviceID"] = self.recipientDeviceID
        record["senderUserID"] = self.senderUserID
        record["recipientUserID"] = self.recipientUserID
        record["text"] = self.text
        record["timestamp"] = self.timestamp
        record["isRead"] = self.isRead
        // We don't typically save the 'status' field to CloudKit as it's a client-side UI concern
        // or derived from context (e.g., if it's in CloudKit, it's 'sent' or 'received').
        
        if let asset = self.imageAsset {
            record["imageAsset"] = asset
        } else {
            record["imageAsset"] = nil // Explicitly set to nil if no image
        }
        
        // Save encryption fields - only if not using default values
        // DEBUG: Log what we're trying to save
        if self.isEncrypted {
            print("DEBUG: Attempting to save encrypted message with fields:")
            print("  - isEncrypted: 1")
            print("  - encryptedContent: \(self.encryptedContent?.prefix(20) ?? "nil")...")
            print("  - encryptionKeyID: \(self.encryptionKeyID ?? "nil")")
            
            record["isEncrypted"] = Int64(1)
            if let encryptedContent = self.encryptedContent {
                record["encryptedContent"] = encryptedContent
            }
            if let encryptedImageData = self.encryptedImageData {
                record["encryptedImageData"] = encryptedImageData
            }
            if let encryptionKeyID = self.encryptionKeyID {
                record["encryptionKeyID"] = encryptionKeyID
            }
        }
        
        return record
    }
} 