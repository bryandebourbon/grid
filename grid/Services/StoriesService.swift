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
        // Create temporary file for upload
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        
        try imageData.write(to: tempFileURL)
        let imageAsset = CKAsset(fileURL: tempFileURL)
        
        // Create story
        let story = Story(userID: userID, deviceID: deviceID, imageAsset: imageAsset, caption: caption)
        let record = story.toCKRecord()
        
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
                Task { @MainActor in
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: tempFileURL)
                    
                    if let error = error {
                        print("StoriesService: Error uploading story: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else if let savedRecord = savedRecords?.first,
                              let savedStory = Story(record: savedRecord) {
                        print("StoriesService: Successfully uploaded story: \(savedStory.id)")
                        self.myStories.append(savedStory)
                        self.allActiveStories.append(savedStory)
                        continuation.resume(returning: savedStory)
                    } else {
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
        let predicate = NSPredicate(format: "deviceID == %@ AND isActive == 1 AND expirationDate > %@", deviceID, Date() as NSDate)
        let query = CKQuery(recordType: "Stories", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let records = try await publicDB.records(matching: query)
            let stories = records.matchResults.compactMap { (_, result) in
                switch result {
                case .success(let record):
                    return Story(record: record)
                case .failure(let error):
                    print("StoriesService: Error fetching story record for device \(deviceID): \(error.localizedDescription)")
                    return nil
                }
            }
            
            print("StoriesService: Fetched \(stories.count) stories for device: \(deviceID)")
            return stories
        } catch {
            print("StoriesService: Error fetching stories for device \(deviceID): \(error.localizedDescription)")
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