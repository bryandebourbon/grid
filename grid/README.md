# Grid App

A location-based social networking app built with SwiftUI and CloudKit.

## Features

- Real-time location sharing
- Profile management with photos and interests
- Proximity-based messaging
- Connection request system
- Interest-based filtering
- Encryption mode for private messaging
- Content moderation and privacy controls

## CloudKit Database Schema

The app requires the following record types in your CloudKit Public Database:

### UserProfiles
- `userID` (String, Queryable, Sortable)
- `deviceID` (String, Queryable, Sortable) 
- `deviceName` (String)
- `profileImage` (Asset)
- `bio` (String)
- `interests` (List<String>)
- `latitude` (Double)
- `longitude` (Double)
- `lastActive` (Date/Time)
- `isActive` (Int64, Queryable)

### Messages
- `senderDeviceID` (String, Queryable)
- `recipientDeviceID` (String, Queryable)
- `senderUserID` (String, Queryable)
- `recipientUserID` (String, Queryable)
- `text` (String)
- `timestamp` (Date/Time, Queryable, Sortable)
- `imageAsset` (Asset)
- `isEncrypted` (Int64)
- `encryptedContent` (String)
- `encryptionKeyID` (String)

### UserRelationships
- `userID` (String, Queryable)
- `targetUserID` (String, Queryable)
- `actionType` (String, Queryable) // "star", "block", "report"
- `timestamp` (Date/Time)

### ReadReceipts
- `deviceID` (String, Queryable)
- `messageID` (String, Queryable)
- `timestamp` (Date/Time)

### EncryptionProfiles
- `deviceID` (String, Queryable) - Record Name
- `publicKey` (String)
- `isEncryptionEnabled` (Int64, Queryable)
- `timestamp` (Date/Time)

### Reports
- `reporterUserID` (String)
- `reportedUserID` (String)
- `reportedDeviceID` (String)
- `reportReason` (String)
- `reportDescription` (String)
- `timestamp` (Date/Time)

## Setup Instructions

1. Create a CloudKit container for your app
2. Add the record types above to your Public Database
3. Set appropriate permissions and indexes
4. Update your app's CloudKit container identifier
5. Enable location permissions in your app
6. Test the connection request flow

## Privacy & Content Moderation

The app includes built-in content moderation for:
- Profile bios and images
- Chat messages
- Report system for inappropriate content
- Automatic content filtering

## Encryption

All messaging is encrypted by default:
- Each device generates a long-term **Curve25519** key-agreement key pair. The
  private key is stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`);
  the public key is published via the `EncryptionProfiles` record type.
- Message content is encrypted with a random AES-256-GCM content key. That key
  is wrapped (ephemeral ECDH + HKDF-SHA256 + AES-GCM) to **both** the recipient
  and the sender, so each party can read the conversation while no one else can.
- Only encryption-capable users appear on the grid.

**Privacy note:** message *content* and images are encrypted end-to-end, but
message *metadata* (sender/recipient device IDs and timestamps) is currently
stored in the CloudKit **public** database. Moving conversation records to a
per-user private/shared CloudKit zone (via `CKShare`) is tracked as a follow-up
to also protect metadata. 