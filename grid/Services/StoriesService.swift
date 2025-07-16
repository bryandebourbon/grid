import Foundation
import CloudKit
import Combine

@MainActor
class StoriesService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var allActiveStories: [Story] = []
    @Published var myStories: [Story] = []
    @Published var storyViews: [String: [StoryView]] = [:] // storyID -> [StoryView]
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupCleanupTimer()
    }
    
    // MARK: - Story Upload
    
    /// Upload a new story to CloudKit
    func uploadStory(imageData: Data, caption: String?, userID: String, deviceID: String) async throws -> Story {
        print("StoriesService: 📤 Starting story upload...")
        print("StoriesService: 📊 Image data size: \(imageData.count) bytes")
        print("StoriesService: 👤 UserID: \(userID), DeviceID: \(deviceID)")
        print("StoriesService: 💬 Caption: \(caption ?? "none")")
        
        // Create temporary file for upload
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        
        print("StoriesService: 📁 Creating temp file at: \(tempFileURL.path)")
        
        do {
            try imageData.write(to: tempFileURL)
            print("StoriesService: ✅ Successfully wrote image data to temp file")
            
            // Verify the file was created
            let fileExists = FileManager.default.fileExists(atPath: tempFileURL.path)
            print("StoriesService: 📁 Temp file exists: \(fileExists)")
            
            if fileExists {
                let fileSize = try? FileManager.default.attributesOfItem(atPath: tempFileURL.path)[.size] as? Int64 ?? 0
                print("StoriesService: 📏 Temp file size: \(fileSize ?? 0) bytes")
            }
        } catch {
            print("StoriesService: ❌ Failed to write image data to temp file: \(error)")
            throw error
        }
        
        let imageAsset = CKAsset(fileURL: tempFileURL)
        print("StoriesService: 📷 Created CKAsset with fileURL: \(imageAsset.fileURL?.absoluteString ?? "nil")")
        
        // Create story
        let story = Story(userID: userID, deviceID: deviceID, imageAsset: imageAsset, caption: caption)
        print("StoriesService: 📝 Created Story object with ID: \(story.id)")
        
        let record = story.toCKRecord()
        print("StoriesService: 🗂️ Created CKRecord with type: \(record.recordType), ID: \(record.recordID.recordName)")
        
        // Log what fields are being saved to CloudKit
        print("StoriesService: 📊 CKRecord fields:")
        for (key, value) in record.allKeys().enumerated() {
            let fieldValue = record[value]
            if let asset = fieldValue as? CKAsset {
                print("StoriesService:   \(value): CKAsset(fileURL: \(asset.fileURL?.absoluteString ?? "nil"))")
            } else {
                print("StoriesService:   \(value): \(String(describing: fieldValue))")
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            print("StoriesService: 📡 Starting CloudKit save operation...")
            
            operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
                Task { @MainActor in
                    // Clean up temp file
                    print("StoriesService: 🧹 Cleaning up temp file...")
                    try? FileManager.default.removeItem(at: tempFileURL)
                    
                    if let error = error {
                        print("StoriesService: ❌ CloudKit save error: \(error.localizedDescription)")
                        print("StoriesService: ❌ Error details: \(error)")
                        continuation.resume(throwing: error)
                    } else if let savedRecord = savedRecords?.first {
                        print("StoriesService: ✅ CloudKit save successful!")
                        print("StoriesService: 📝 Saved record ID: \(savedRecord.recordID.recordName)")
                        
                        // Verify the saved record has the imageAsset
                        if let savedAsset = savedRecord["imageAsset"] as? CKAsset {
                            print("StoriesService: 📷 Saved record has imageAsset with fileURL: \(savedAsset.fileURL?.absoluteString ?? "nil")")
                        } else {
                            print("StoriesService: ⚠️ Saved record has no imageAsset!")
                        }
                        
                        if let savedStory = Story(record: savedRecord) {
                            print("StoriesService: ✅ Successfully created Story from saved record")
                            self.myStories.append(savedStory)
                            self.allActiveStories.append(savedStory)
                            continuation.resume(returning: savedStory)
                        } else {
                            print("StoriesService: ❌ Failed to create Story from saved record")
                            let error = NSError(domain: "StoriesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Story from saved record"])
                            continuation.resume(throwing: error)
                        }
                    } else {
                        print("StoriesService: ❌ No saved records returned from CloudKit")
                        let error = NSError(domain: "StoriesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save story"])
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            publicDB.add(operation)
        }
    }
    
    // MARK: - Story Fetching
    
    /// Fetch all active stories from CloudKit
    func fetchActiveStories() async {
        let predicate = NSPredicate(format: "isActive == 1 AND expirationDate > %@", Date() as NSDate)
        let query = CKQuery(recordType: "Stories", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let records = try await publicDB.records(matching: query)
            let stories = records.matchResults.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return Story(record: record)
                case .failure(let error):
                    print("StoriesService: Error fetching story record: \(error.localizedDescription)")
                    return nil
                }
            }
            
            self.allActiveStories = stories
            print("StoriesService: Fetched \(stories.count) active stories")
        } catch {
            print("StoriesService: Error fetching active stories: \(error.localizedDescription)")
        }
    }
    
    /// Fetch stories for a specific user/device
    func fetchStoriesForDevice(_ deviceID: String) async -> [Story] {
        print("StoriesService: 🔍 Starting fetchStoriesForDevice for deviceID: \(deviceID)")
        
        let predicate = NSPredicate(format: "deviceID == %@ AND isActive == 1 AND expirationDate > %@", deviceID, Date() as NSDate)
        let query = CKQuery(recordType: "Stories", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            print("StoriesService: 📡 Executing CloudKit query for stories...")
            let records = try await publicDB.records(matching: query)
            print("StoriesService: 📥 Received \(records.matchResults.count) raw records from CloudKit")
            
            let stories = records.matchResults.compactMap { (recordID, result) in
                switch result {
                case .success(let record):
                    print("StoriesService: ✅ Processing record: \(record.recordID.recordName)")
                    
                    // Log record details for debugging
                    if let imageAsset = record["imageAsset"] as? CKAsset {
                        print("StoriesService: 📷 Record has imageAsset with fileURL: \(imageAsset.fileURL?.absoluteString ?? "nil")")
                        
                        // Check if the file exists locally
                        if let fileURL = imageAsset.fileURL {
                            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
                            print("StoriesService: 📁 Asset file exists locally: \(fileExists)")
                            if fileExists {
                                do {
                                    let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
                                    print("StoriesService: 📏 Asset file size: \(fileSize) bytes")
                                } catch {
                                    print("StoriesService: ⚠️ Could not get file size: \(error)")
                                }
                            }
                        } else {
                            print("StoriesService: ⚠️ ImageAsset has no fileURL")
                        }
                    } else {
                        print("StoriesService: ⚠️ Record has no imageAsset")
                    }
                    
                    if let caption = record["caption"] as? String {
                        print("StoriesService: 💬 Record has caption: \(caption)")
                    }
                    
                    let story = Story(record: record)
                    if story != nil {
                        print("StoriesService: ✅ Successfully created Story object from record")
                    } else {
                        print("StoriesService: ❌ Failed to create Story object from record")
                    }
                    return story
                    
                case .failure(let error):
                    print("StoriesService: ❌ Error fetching story record for device \(deviceID): \(error.localizedDescription)")
                    return nil
                }
            }
            
            print("StoriesService: 📊 Successfully processed \(stories.count) out of \(records.matchResults.count) records")
            print("StoriesService: ✅ Fetched \(stories.count) stories for device: \(deviceID)")
            
            // Log each story's details
            for (index, story) in stories.enumerated() {
                print("StoriesService: Story \(index): ID=\(story.id), hasAsset=\(story.imageAsset != nil), valid=\(story.isValid)")
            }
            
            return stories
        } catch {
            print("StoriesService: ❌ Error fetching stories for device \(deviceID): \(error.localizedDescription)")
            print("StoriesService: ❌ Error details: \(error)")
            return []
        }
    }
    
    // MARK: - Story Views
    
    /// Record that a user viewed a story
    func recordStoryView(storyID: String, viewerUserID: String, viewerDeviceID: String) async {
        // Check if user already viewed this story
        if let existingViews = storyViews[storyID],
           existingViews.contains(where: { $0.viewerDeviceID == viewerDeviceID }) {
            print("StoriesService: User already viewed story \(storyID)")
            return
        }
        
        let storyView = StoryView(storyID: storyID, viewerUserID: viewerUserID, viewerDeviceID: viewerDeviceID)
        let record = storyView.toCKRecord()
        
        do {
            let savedRecord = try await publicDB.save(record)
            if let savedView = StoryView(record: savedRecord) {
                // Update local cache
                if storyViews[storyID] == nil {
                    storyViews[storyID] = []
                }
                storyViews[storyID]?.append(savedView)
                print("StoriesService: Recorded story view for story: \(storyID)")
            }
        } catch {
            print("StoriesService: Error recording story view: \(error.localizedDescription)")
        }
    }
    
    /// Fetch story views for a specific story
    func fetchStoryViews(for storyID: String) async -> [StoryView] {
        let predicate = NSPredicate(format: "storyID == %@", storyID)
        let query = CKQuery(recordType: "StoryViews", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let records = try await publicDB.records(matching: query)
            let views = records.matchResults.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return StoryView(record: record)
                case .failure(let error):
                    print("StoriesService: Error fetching story view record: \(error.localizedDescription)")
                    return nil
                }
            }
            
            storyViews[storyID] = views
            return views
        } catch {
            print("StoriesService: Error fetching story views for \(storyID): \(error.localizedDescription)")
            return []
        }
    }
    
    /// Check if a user has viewed a story
    func hasUserViewedStory(_ storyID: String, viewerDeviceID: String) -> Bool {
        guard let views = storyViews[storyID] else { return false }
        return views.contains { $0.viewerDeviceID == viewerDeviceID }
    }
    
    // MARK: - Story Management
    
    /// Get stories with unread indicator for a device
    func getStoriesForDevice(_ deviceID: String, viewerDeviceID: String) async -> (stories: [Story], hasUnviewed: Bool) {
        let stories = await fetchStoriesForDevice(deviceID)
        
        // Check if any stories are unviewed
        var hasUnviewed = false
        for story in stories {
            if !hasUserViewedStory(story.id, viewerDeviceID: viewerDeviceID) {
                hasUnviewed = true
                break
            }
        }
        
        return (stories, hasUnviewed)
    }
    
    /// Delete a specific story
    func deleteStory(_ story: Story) async {
        guard let recordID = story.recordID else { return }
        
        do {
            try await publicDB.deleteRecord(withID: recordID)
            
            // Remove from local arrays
            allActiveStories.removeAll { $0.id == story.id }
            myStories.removeAll { $0.id == story.id }
            
            print("StoriesService: Deleted story: \(story.id)")
        } catch {
            print("StoriesService: Error deleting story \(story.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - 24-Hour Cleanup
    
    /// Setup automatic cleanup timer
    private func setupCleanupTimer() {
        // Run cleanup every hour
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.cleanupExpiredStories()
                }
            }
            .store(in: &cancellables)
        
        // Also run cleanup on init
        Task {
            await cleanupExpiredStories()
        }
    }
    
    /// Clean up expired stories
    func cleanupExpiredStories() async {
        print("StoriesService: Starting cleanup of expired stories...")
        
        // Find expired stories - Split into two separate queries as CloudKit doesn't like complex OR predicates
        let now = Date()
        
        // Query 1: Find stories that have expired by date
        let expiredByDatePredicate = NSPredicate(format: "expirationDate <= %@", now as NSDate)
        let expiredByDateQuery = CKQuery(recordType: "Stories", predicate: expiredByDatePredicate)
        
        // Query 2: Find stories that are marked as inactive
        let inactivePredicate = NSPredicate(format: "isActive == 0")
        let inactiveQuery = CKQuery(recordType: "Stories", predicate: inactivePredicate)
        
        var expiredRecordIDs: [CKRecord.ID] = []
        
        do {
            // Execute first query - expired by date
            let expiredByDateRecords = try await publicDB.records(matching: expiredByDateQuery)
            let expiredByDateIDs = expiredByDateRecords.matchResults.compactMap { (recordID, result) in
                switch result {
                case .success(_):
                    return recordID
                case .failure(let error):
                    print("StoriesService: Error checking expired story (by date): \(error.localizedDescription)")
                    return nil
                }
            }
            expiredRecordIDs.append(contentsOf: expiredByDateIDs)
            
            // Execute second query - inactive stories
            let inactiveRecords = try await publicDB.records(matching: inactiveQuery)
            let inactiveIDs = inactiveRecords.matchResults.compactMap { (recordID, result) in
                switch result {
                case .success(_):
                    return recordID
                case .failure(let error):
                    print("StoriesService: Error checking inactive story: \(error.localizedDescription)")
                    return nil
                }
            }
            expiredRecordIDs.append(contentsOf: inactiveIDs)
            
            // Remove duplicates
            expiredRecordIDs = Array(Set(expiredRecordIDs))
            
            if !expiredRecordIDs.isEmpty {
                // Delete expired stories
                let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: expiredRecordIDs)
                
                deleteOperation.modifyRecordsCompletionBlock = { _, deletedRecordIDs, error in
                    Task { @MainActor in
                        if let error = error {
                            print("StoriesService: Error during cleanup: \(error.localizedDescription)")
                        } else {
                            let deletedCount = deletedRecordIDs?.count ?? 0
                            print("StoriesService: Cleaned up \(deletedCount) expired stories")
                            
                            // Update local arrays
                            if let deletedIDs = deletedRecordIDs {
                                let deletedIDStrings = Set(deletedIDs.map { $0.recordName })
                                self.allActiveStories.removeAll { deletedIDStrings.contains($0.id) }
                                self.myStories.removeAll { deletedIDStrings.contains($0.id) }
                            }
                        }
                    }
                }
                
                publicDB.add(deleteOperation)
            } else {
                print("StoriesService: No expired stories to clean up")
            }
        } catch {
            print("StoriesService: Error during cleanup query: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh
    
    /// Refresh all stories data
    func refreshStories() async {
        await fetchActiveStories()
    }
} 