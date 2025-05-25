import Foundation
import CloudKit
import Combine

class GridService: ObservableObject {
    private let publicDB = CKContainer.default().publicCloudDatabase
    @Published var allPublicProfiles: [UserProfile] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        fetchAllPublicProfiles()
        setupPublicProfileSubscription()
        
        // Listen for grid update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGridUpdateNotification),
            name: .newGridUpdate,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleGridUpdateNotification() {
        print("GridService: Handling grid update notification - refreshing public profiles")
        fetchAllPublicProfiles()
    }
    
    // Save user profile to PUBLIC database so everyone can see it on the grid
    func saveProfileToPublicGrid(_ profile: UserProfile, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        let publicRecord = profile.toPublicCKRecord()
        
        // Use modifyRecords to handle both insert and update cases
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [publicRecord], recordIDsToDelete: nil)
        modifyOperation.savePolicy = .changedKeys // Only update changed fields
        modifyOperation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving/updating profile to public grid: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let savedRecord = savedRecords?.first, let savedProfile = UserProfile(record: savedRecord) else {
                    print("Failed to convert saved public profile record")
                    completion(.failure(NSError(domain: "GridService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process saved profile."])))
                    return
                }
                
                print("Profile saved/updated to public grid for device: \(savedProfile.deviceName)")
                // Update local cache
                self.updateLocalProfileCache(savedProfile)
                completion(.success(savedProfile))
            }
        }
        
        publicDB.add(modifyOperation)
    }
    
    // Fetch all public profiles to populate the grid
    func fetchAllPublicProfiles() {
        // Query on a custom field that IS queryable (deviceID exists for all profiles)
        let predicate = NSPredicate(format: "deviceID != %@", "") // All profiles with non-empty deviceID
        let query = CKQuery(recordType: "UserProfiles", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching public profiles: \(error.localizedDescription)")
                    // If query still fails, try with different approach
                    if error.localizedDescription.contains("queryable") {
                        print("Attempting alternative fetch method...")
                        self.fetchAllPublicProfilesAlternative()
                    }
                    return
                }
                
                let profiles = records?.compactMap { UserProfile(record: $0) } ?? []
                print("Fetched \(profiles.count) public profiles for the grid")
                self.allPublicProfiles = profiles
            }
        }
    }
    
    // Alternative fetch method if the main query fails
    private func fetchAllPublicProfilesAlternative() {
        // For now, we'll rely on MultipeerConnectivity for profile discovery
        // and push notifications for updates. This is a fallback.
        print("Using alternative profile discovery via MultipeerConnectivity")
        self.allPublicProfiles = [] // Clear for now
    }
    
    // Set up subscription to get notified when new users join the grid
    private func setupPublicProfileSubscription() {
        let subscriptionID = "public-grid-updates"
        print("Attempting to create or update public-grid-updates subscription to ensure it has no alertBody.")
        // Directly call createPublicGridSubscription. CKDatabase.save(CKSubscription)
        // will update the subscription if it already exists with the same ID,
        // or create it if it doesn't. This ensures the notificationInfo is current (and has no alertBody).
        self.createPublicGridSubscription(subscriptionID: subscriptionID)
    }
    
    private func createPublicGridSubscription(subscriptionID: String) {
        let subscription = CKQuerySubscription(
            recordType: "UserProfiles",
            predicate: NSPredicate(value: true), // All profiles
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate] // New users and profile updates
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Background updates
        subscription.notificationInfo = notificationInfo
        
        publicDB.save(subscription) { savedSubscription, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error creating/updating public grid subscription: \(error.localizedDescription)")
                } else {
                    print("Successfully created/updated public grid subscription (should be silent).")
                }
            }
        }
    }
    
    private func updateLocalProfileCache(_ profile: UserProfile) {
        // Update or add profile in local cache
        if let index = allPublicProfiles.firstIndex(where: { $0.deviceID == profile.deviceID }) {
            allPublicProfiles[index] = profile
        } else {
            allPublicProfiles.append(profile)
        }
    }
    
    // Remove profile from public grid (when user deletes account)
    func removeProfileFromPublicGrid(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: deviceID)
        
        publicDB.delete(withRecordID: recordID) { deletedRecordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error removing profile from public grid: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("Successfully removed profile from public grid")
                    // Remove from local cache
                    self.allPublicProfiles.removeAll { $0.deviceID == deviceID }
                    completion(.success(()))
                }
            }
        }
    }
} 