import Foundation
import CloudKit
import Combine
import UserNotifications

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
        print("MessagingService: Handling CloudKit notification for record: \(recordID.recordName)")
        fetchMessage(withRecordID: recordID)
    }

    func sendMessage(_ message: Message, completion: @escaping (Result<Message, Error>) -> Void) {
        let messageRecord = message.toCKRecord()
        
        publicDB.save(messageRecord) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving message to public CloudKit: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let savedRecord = record, let savedMessage = Message(record: savedRecord) else {
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
                let sentMessages = records?.compactMap { Message(record: $0) } ?? []
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
                let receivedMessages = records?.compactMap { Message(record: $0) } ?? []
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
        notificationInfo.shouldSendContentAvailable = true // For background updates
        notificationInfo.alertBody = "New message received!" // User-visible alert
        notificationInfo.soundName = "default" // Sound
        notificationInfo.shouldBadge = true // Badge count
        
        // Add custom fields to the notification payload for routing
        notificationInfo.desiredKeys = ["senderDeviceID", "text"] // Include sender info
        
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
    
    // Call this from your AppDelegate or SceneDelegate when a push notification is received
    func handlePushNotification(userInfo: [AnyHashable : Any]) {
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           notification.subscriptionID?.starts(with: "new-messages-for-device-") == true,
           let recordID = notification.recordID {
            
            print("Push notification received for a message. RecordID: \(recordID.recordName)")
            fetchMessage(withRecordID: recordID)
        }
    }
    
    private func fetchMessage(withRecordID recordID: CKRecord.ID) {
        publicDB.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching single message by ID \(recordID.recordName): \(error.localizedDescription)")
                    return
                }
                guard let fetchedRecord = record, let message = Message(record: fetchedRecord) else {
                    print("Failed to fetch or parse message from push notification: \(recordID.recordName)")
                    return
                }
                
                print("Successfully fetched message from push: \(message.text)")
                // Update local store and notify UI
                if !self.receivedMessages.contains(where: { $0.id == message.id }) {
                    self.receivedMessages.append(message)
                    self.receivedMessages.sort(by: { $0.timestamp < $1.timestamp })
                }
                self.newMessageReceived.send(message) // Notify subscribers (e.g., ViewModel)
            }
        }
    }
} 