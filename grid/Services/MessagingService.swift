import Foundation
import CloudKit
import Combine
import UserNotifications

// Define Notification Names if not already globally available
extension Notification.Name {
    static let didTapPushNotificationForChat = Notification.Name("didTapPushNotificationForChat")
    static let didIngestCloudKitMessage = Notification.Name("didIngestCloudKitMessage")
}

class MessagingService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var receivedMessages: [Message] = []
    private var cancellables = Set<AnyCancellable>()

    // To notify about new messages, especially for UI updates or other services
    var newMessageReceived = PassthroughSubject<Message, Never>()

    init() {
        // Listen for CloudKit push notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitNotification(_:)),
            name: .newCloudKitMessage,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleCloudKitNotification(_ notification: Notification) {
        guard let recordID = notification.object as? CKRecord.ID else { return }
        PendingMessageFetchStore.enqueue(recordID.recordName)
        MessageDeliveryTrace.log("push.local record=\(recordID.recordName.prefix(8))")
        print("MessagingService: Handling CloudKit notification for record: \(recordID.recordName)")
        fetchMessage(withRecordID: recordID, currentDeviceID: nil, announce: true, completion: nil)
    }

    /// Writes only reaction fields so a save cannot wipe an image asset.
    func updateReactions(on message: Message, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let recordID = message.recordID ?? CKRecord.ID(recordName: message.id)
        publicDB.fetch(withRecordID: recordID) { record, error in
            if let error {
                DispatchQueue.main.async { completion?(.failure(error)) }
                return
            }
            guard let record else {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(
                        domain: "MessagingService",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Message record not found."]
                    )))
                }
                return
            }
            record["reactionsJSON"] = MessageReactionLogic.encode(message.reactions)
            record["reactionsUpdatedAt"] = message.reactionsUpdatedAt
            self.publicDB.save(record) { _, saveError in
                DispatchQueue.main.async {
                    if let saveError {
                        completion?(.failure(saveError))
                    } else {
                        completion?(.success(()))
                    }
                }
            }
        }
    }

    func sendMessage(_ message: Message, completion: @escaping (Result<Message, Error>) -> Void) {
        let messageRecord = message.toCKRecord()
        let senderDeviceIDForContext = message.senderDeviceID // This is the current user sending the message
        
        publicDB.save(messageRecord) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving message to public CloudKit: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                // Pass senderDeviceIDForContext as currentDeviceID for the Message initializer
                guard let savedRecord = record, let savedMessage = Message(record: savedRecord, currentDeviceID: senderDeviceIDForContext) else {
                    print("Failed to convert saved CKRecord back to Message")
                    completion(.failure(NSError(domain: "MessagingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process saved message record."])))
                    return
                }
                print("Message sent and saved to public database with ID: \(savedMessage.id)")
                
                // After successfully sending a message, try to set up subscriptions if they don't exist yet
                // (now that we know the Messages record type exists)
                if let currentDeviceID = savedMessage.senderDeviceID as String? {
                    self.subscribeToMessageChanges(forDeviceID: currentDeviceID)
                }
                
                completion(.success(savedMessage))
            }
        }
    }

    func fetchMessages(forDeviceID deviceID: String, completion: @escaping (Result<[Message], Error>) -> Void) {
        // CloudKit has restrictions on compound predicates, so we'll make two separate queries and combine results
        let sentQuery = CKQuery(recordType: "Messages", predicate: NSPredicate(format: "senderDeviceID == %@", deviceID))
        sentQuery.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let receivedQuery = CKQuery(recordType: "Messages", predicate: NSPredicate(format: "recipientDeviceID == %@", deviceID))
        receivedQuery.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        var allMessages: [Message] = []
        let dispatchGroup = DispatchGroup()
        var fetchError: Error?
        
        // Fetch sent messages
        dispatchGroup.enter()
        publicDB.perform(sentQuery, inZoneWith: nil) { records, error in
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Record type doesn't exist yet - this is fine, it will be created when first message is sent
                print("Messages record type doesn't exist yet - will be created automatically when first message is sent")
            } else if let error = error {
                fetchError = error
            } else {
                // Pass deviceID as currentDeviceID for the Message initializer
                let sentMessages = records?.compactMap { Message(record: $0, currentDeviceID: deviceID) } ?? []
                allMessages.append(contentsOf: sentMessages)
            }
            dispatchGroup.leave()
        }
        
        // Fetch received messages
        dispatchGroup.enter()
        publicDB.perform(receivedQuery, inZoneWith: nil) { records, error in
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Record type doesn't exist yet - this is fine, it will be created when first message is sent
                print("Messages record type doesn't exist yet - will be created automatically when first message is sent")
            } else if let error = error {
                fetchError = error
            } else {
                // Pass deviceID as currentDeviceID for the Message initializer
                let receivedMessages = records?.compactMap { Message(record: $0, currentDeviceID: deviceID) } ?? []
                allMessages.append(contentsOf: receivedMessages)
            }
            dispatchGroup.leave()
        }
        
        // Wait for both queries to complete
        dispatchGroup.notify(queue: .main) {
            if let error = fetchError {
                print("Error fetching messages from public database: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            // Remove duplicates by using a dictionary keyed by message ID
            var messageDict: [String: Message] = [:]
            for message in allMessages {
                messageDict[message.id] = message
            }
            let uniqueMessages = Array(messageDict.values).sorted { $0.timestamp < $1.timestamp }
            
            print("Fetched \(uniqueMessages.count) messages from public database for deviceID: \(deviceID)")
            self.receivedMessages = uniqueMessages // Update published property
            completion(.success(uniqueMessages))
        }
    }

    func subscribeToMessageChanges(forDeviceID deviceID: String) {
        let subscriptionID = "new-messages-for-device-\(deviceID)"
        print("Attempting to create or update subscription: \(subscriptionID) to ensure latest settings are applied.")
        
        // Directly call createSubscription. CKDatabase.save(CKSubscription)
        // will update the subscription if it already exists with the same ID,
        // or create it if it doesn't. This ensures the notificationInfo is current.
        self.createSubscription(forDeviceID: deviceID, subscriptionID: subscriptionID)
    }
    
    private func createSubscription(forDeviceID deviceID: String, subscriptionID: String) {
        // Predicate for messages where the current device is the recipient
        let predicate = NSPredicate(format: "recipientDeviceID == %@", deviceID)
        let newSubscription = CKQuerySubscription(
            recordType: "Messages",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: .firesOnRecordCreation // Notify on new message creation
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldBadge = true
        // No alertBody: CloudKit cannot decrypt the message. The app posts a
        // local banner with the sender and plaintext after the record fetch.
        // Production schema only allows the original notification fields.
        // Adding keys creates notif_additional_field_N and CloudKit rejects the save.
        notificationInfo.desiredKeys = MessageSubscriptionLogic.desiredKeys
        
        newSubscription.notificationInfo = notificationInfo

        self.publicDB.save(newSubscription) { savedSubscription, saveError in
            DispatchQueue.main.async {
                if let ckError = saveError as? CKError, ckError.code == .unknownItem {
                    print("Cannot create subscription yet - Messages record type doesn't exist. Will be created automatically when first message is sent.")
                } else if let saveError = saveError {
                    print("Error saving subscription '\(subscriptionID)': \(saveError.localizedDescription)")
                } else if let sub = savedSubscription {
                    // Updated log message for clarity
                    print("Successfully saved (created or updated) subscription: \(sub.subscriptionID)")
                }
            }
        }
    }
    
    func unsubscribeFromMessageChanges(forDeviceID deviceID: String) {
        let subscriptionID = "new-messages-for-device-\(deviceID)"
        publicDB.delete(withSubscriptionID: subscriptionID) { deletedID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error deleting subscription '\(subscriptionID)': \(error.localizedDescription)")
                } else if let id = deletedID {
                    print("Successfully deleted subscription: \(id)")
                }
            }
        }
    }
    
    // Call this from your AppDelegate or SceneDelegate when a push notification is received AND TAPPED
    func handlePushNotificationTap(userInfo: [AnyHashable : Any]) {
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           notification.subscriptionID?.starts(with: "new-messages-for-device-") == true,
           let recordID = notification.recordID {
            
            print("Push notification TAP HANDLER for message. RecordID: \(recordID.recordName)")
            
            // Fetch the message. We pass nil for currentDeviceID as this service doesn't own that state.
            // The Message init will determine status as .received.
            publicDB.fetch(withRecordID: recordID) { record, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error fetching message from push tap: \(error.localizedDescription)")
                        return
                    }
                    guard let fetchedRecord = record, 
                          let senderDeviceID = fetchedRecord["senderDeviceID"] as? String else {
                        print("Failed to fetch or parse message details (senderDeviceID) from push tap: \(recordID.recordName)")
                        return
                    }
                    
                    print("Posting .didTapPushNotificationForChat with senderDeviceID: \(senderDeviceID)")
                    NotificationCenter.default.post(name: .didTapPushNotificationForChat, object: nil, userInfo: ["senderDeviceID": senderDeviceID])

                    if let message = Message(record: fetchedRecord, currentDeviceID: nil) {
                        PendingMessageFetchStore.remove(recordID.recordName)
                        MessageInboxStore.upsert(message)
                        self.newMessageReceived.send(message)
                        NotificationCenter.default.post(name: .didIngestCloudKitMessage, object: message)
                    }
                }
            }
        }
    }
    
    func fetchMessage(
        withRecordID recordID: CKRecord.ID,
        currentDeviceID: String?,
        announce: Bool = false,
        completion: ((Result<Message, Error>) -> Void)?
    ) {
        PendingMessageFetchStore.enqueue(recordID.recordName)
        publicDB.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching single message by ID \(recordID.recordName): \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }
                guard let fetchedRecord = record, let message = Message(record: fetchedRecord, currentDeviceID: currentDeviceID) else {
                    print("Failed to fetch or parse message from push notification: \(recordID.recordName)")
                    completion?(.failure(NSError(
                        domain: "MessagingService",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse message record."]
                    )))
                    return
                }

                MessageDeliveryTrace.log("fetchByID ok id=\(message.id.prefix(8)) from=\(message.senderDeviceID.prefix(8)) image=\(message.encryptedImageData != nil)")
                print("Successfully fetched message from push: \(message.text)")
                PendingMessageFetchStore.remove(recordID.recordName)
                MessageInboxStore.upsert(message)
                self.newMessageReceived.send(message)
                NotificationCenter.default.post(name: .didIngestCloudKitMessage, object: message)
                if announce {
                    MessageDeliveryTrace.log("banner.request id=\(message.id.prefix(8))")
                    MessageBannerNotifier.announce(message, currentDeviceID: currentDeviceID)
                }
                completion?(.success(message))
            }
        }
    }

    func fetchPendingRecords(currentDeviceID: String?, completion: @escaping ([Message]) -> Void) {
        fetchRecords(named: PendingMessageFetchStore.all(), currentDeviceID: currentDeviceID, completion: completion)
    }

    func fetchRecords(named recordNames: [String], currentDeviceID: String?, completion: @escaping ([Message]) -> Void) {
        let uniqueNames = Array(Set(recordNames.filter { !$0.isEmpty }))
        guard !uniqueNames.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let group = DispatchGroup()
        var fetched: [Message] = []
        let lock = NSLock()

        for name in uniqueNames {
            group.enter()
            publicDB.fetch(withRecordID: CKRecord.ID(recordName: name)) { record, error in
                defer { group.leave() }
                if let error = error {
                    print("Error fetching pending message \(name): \(error.localizedDescription)")
                    return
                }
                guard let record, let message = Message(record: record, currentDeviceID: currentDeviceID) else { return }
                PendingMessageFetchStore.remove(name)
                MessageInboxStore.upsert(message)
                lock.lock()
                fetched.append(message)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(fetched)
        }
    }
}