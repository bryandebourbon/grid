import Foundation
import SwiftUI
import CloudKit
import CoreLocation

struct DemoConfiguration {
    let interests: [Interest]
    let bio: String
    let area: String
    
    static let configurations: [DemoConfiguration] = [
        DemoConfiguration(
            interests: [.technology, .programming, .startups],
            bio: "Tech entrepreneur building the next big thing. Always looking for co-founders and investment opportunities.",
            area: "Silicon Valley"
        ),
        DemoConfiguration(
            interests: [.art, .photography, .design],
            bio: "Creative soul capturing life through my lens. Available for portrait sessions and gallery exhibitions.",
            area: "Arts District"
        ),
        DemoConfiguration(
            interests: [.fitness, .running, .hiking],
            bio: "Marathon runner and outdoor enthusiast. Looking for running partners and hiking buddies.",
            area: "Golden Gate Park"
        ),
        DemoConfiguration(
            interests: [.music, .concerts, .nightlife],
            bio: "Music producer and DJ. Catch me at underground venues and music festivals around the city.",
            area: "Mission District"
        ),
        DemoConfiguration(
            interests: [.cooking, .foodie, .wine],
            bio: "Culinary artist and wine connoisseur. Let's explore the city's best restaurants and cooking classes.",
            area: "Nob Hill"
        ),
        DemoConfiguration(
            interests: [.education, .books, .languages],
            bio: "PhD student in linguistics. Passionate about learning new languages and sharing knowledge.",
            area: "University District"
        ),
        DemoConfiguration(
            interests: [.travel, .outdoors, .photography],
            bio: "World traveler and adventure seeker. Just back from Southeast Asia, planning next expedition.",
            area: "Marina District"
        ),
        DemoConfiguration(
            interests: [.business, .investing, .networking],
            bio: "Investment analyst and networking enthusiast. Always excited to discuss market trends and opportunities.",
            area: "Financial District"
        ),
        DemoConfiguration(
            interests: [.sports, .fitness, .cycling],
            bio: "Semi-professional cyclist and sports enthusiast. Training for next year's competitive season.",
            area: "Richmond District"
        ),
        DemoConfiguration(
            interests: [.meditation, .yoga, .spirituality],
            bio: "Mindfulness coach and yoga instructor. Finding peace and helping others discover their inner calm.",
            area: "Inner Sunset"
        ),
        DemoConfiguration(
            interests: [.gaming, .technology, .design],
            bio: "Game developer and UI/UX designer. Working on an indie game that's going to revolutionize mobile gaming.",
            area: "SOMA"
        ),
        DemoConfiguration(
            interests: [.fashion, .art, .design],
            bio: "Fashion designer and style consultant. Creating sustainable fashion that makes a statement.",
            area: "Castro District"
        ),
        DemoConfiguration(
            interests: [.volunteering, .pets, .outdoors],
            bio: "Animal rescue volunteer and dog trainer. Helping pets find their forever homes on weekends.",
            area: "Sunset District"
        ),
        DemoConfiguration(
            interests: [.movies, .theater, .comedy],
            bio: "Film critic and theater actor. Passionate about storytelling in all its forms.",
            area: "Hayes Valley"
        ),
        DemoConfiguration(
            interests: [.coffee, .writing, .books],
            bio: "Freelance writer and coffee enthusiast. Working on my first novel while discovering the perfect brew.",
            area: "North Beach"
        )
    ]
}

@MainActor
class DemoService: ObservableObject {
    @Published var isDemoMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isDemoMode, forKey: "isDemoMode")
        }
    }
    
    private var demoPhotos: [URL] = []
    private var demoUsers: [UserProfile] = []
    
    init() {
        #if DEBUG
        // Demo mode is a development/screenshot-only feature. It injects
        // fabricated users into the grid and must never be reachable in
        // release builds (App Store Guideline 2.3 — accurate metadata).
        self.isDemoMode = UserDefaults.standard.bool(forKey: "isDemoMode")
        loadDemoPhotos()
        #else
        self.isDemoMode = false
        #endif
    }
    
    private func loadDemoPhotos() {
        let fileManager = FileManager.default
        
        // Method 1: Try to find Demo folder as a bundle resource
        if let bundlePath = Bundle.main.path(forResource: "Demo", ofType: nil) {
            let demoFolderURL = URL(fileURLWithPath: bundlePath)
            print("DemoService: Found Demo folder in bundle at: \(demoFolderURL.path)")
            loadPhotosFromURL(demoFolderURL)
            return
        }
        
        // Method 2: Try to find individual demo images in the main bundle
        print("DemoService: Demo folder not found in bundle, looking for individual images...")
        let imageExtensions = ["png", "jpg", "jpeg"]
        var foundImages: [URL] = []
        
        // Get all bundle resource URLs
        for ext in imageExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                // Filter for images that look like demo images (contain "ChatGPT Image")
                let demoImages = urls.filter { url in
                    url.lastPathComponent.contains("ChatGPT Image")
                }
                foundImages.append(contentsOf: demoImages)
            }
        }
        
        if !foundImages.isEmpty {
            print("DemoService: Found \(foundImages.count) demo images in main bundle")
            demoPhotos = foundImages
            // Shuffle the photos so they appear in random order
            demoPhotos.shuffle()
            print("DemoService: Shuffled \(demoPhotos.count) demo photos")
            return
        }
        
        // Method 3: Try to find Demo folder in the app bundle's resource path
        let bundleResourcePath = Bundle.main.resourcePath ?? ""
        let demoFolderPath = (bundleResourcePath as NSString).appendingPathComponent("Demo")
        
        if fileManager.fileExists(atPath: demoFolderPath) {
            let demoFolderURL = URL(fileURLWithPath: demoFolderPath)
            print("DemoService: Found Demo folder in bundle resource path: \(demoFolderPath)")
            loadPhotosFromURL(demoFolderURL)
            return
        }
        
        print("DemoService: Demo images not found in bundle")
        print("DemoService: Bundle resource path: \(bundleResourcePath)")
        
        // List bundle contents for debugging
        do {
            let bundleContents = try fileManager.contentsOfDirectory(atPath: bundleResourcePath)
            print("DemoService: Bundle contents: \(bundleContents.prefix(10))") // Show first 10 items
        } catch {
            print("DemoService: Could not list bundle contents: \(error)")
        }
        
        print("DemoService: No demo photos found in bundle")
    }
    
    private func loadPhotosFromURL(_ url: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: url, 
                                                          includingPropertiesForKeys: nil, 
                                                          options: .skipsHiddenFiles)
            
            demoPhotos = files.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["png", "jpg", "jpeg"].contains(pathExtension)
            }
            
            // Shuffle the photos so they appear in random order
            demoPhotos.shuffle()
            
            print("DemoService: Loaded and shuffled \(demoPhotos.count) demo photos from \(url.path)")
            
            // Print first few photo names for debugging
            for (index, photo) in demoPhotos.prefix(3).enumerated() {
                print("DemoService: Photo \(index + 1): \(photo.lastPathComponent)")
            }
        } catch {
            print("DemoService: Error loading demo photos: \(error)")
        }
    }
    
    func generateDemoUsers(near currentLocation: CLLocation, count: Int = 20) -> [UserProfile] {
        guard isDemoMode else { 
            print("DemoService: Demo mode is disabled, returning empty array")
            return [] 
        }
        
        print("DemoService: Generating demo users. Photo count: \(demoPhotos.count), Requested count: \(count)")
        
        if demoPhotos.isEmpty {
            print("DemoService: No demo photos available. Attempting to reload...")
            loadDemoPhotos()
            
            if demoPhotos.isEmpty {
                print("DemoService: Still no photos after reload. Creating demo users without photos.")
                // Create demo users without photos for testing
                return generateDemoUsersWithoutPhotos(near: currentLocation, count: min(count, 10))
            }
        }
        
        // Reshuffle photos for variety in each generation
        var shuffledPhotos = demoPhotos
        shuffledPhotos.shuffle()
        
        var generatedUsers: [UserProfile] = []
        var configurations = DemoConfiguration.configurations
        // Shuffle configurations too for more variety
        configurations.shuffle()
        
        let photosToUse = min(count, shuffledPhotos.count)
        
        print("DemoService: Creating \(photosToUse) demo users with shuffled photos and configurations")
        
        for i in 0..<photosToUse {
            let photoURL = shuffledPhotos[i]
            let config = configurations[i % configurations.count]
            
            // Generate a more realistic distance distribution (more users nearby, fewer far away)
            // Use weighted random distribution: 70% within 2km, 25% within 5km, 5% up to 8km
            let randomValue = Double.random(in: 0...1)
            let randomDistance: Double
            
            if randomValue < 0.7 {
                // 70% chance: 100m to 2km (nearby users)
                randomDistance = Double.random(in: 100...2000)
            } else if randomValue < 0.95 {
                // 25% chance: 2km to 5km (moderate distance)
                randomDistance = Double.random(in: 2000...5000)
            } else {
                // 5% chance: 5km to 8km (far away users)
                randomDistance = Double.random(in: 5000...8000)
            }
            
            let randomBearing = Double.random(in: 0...(2 * Double.pi))
            
            let lat = currentLocation.coordinate.latitude + (randomDistance / 111000.0) * cos(randomBearing)
            let lon = currentLocation.coordinate.longitude + (randomDistance / (111000.0 * cos(currentLocation.coordinate.latitude * Double.pi / 180))) * sin(randomBearing)
            
            // Create demo user profile with unique IDs
            let deviceID = "demo_user_\(i)_\(UUID().uuidString.prefix(8))"
            let userID = "demo_apple_id_\(i)_\(UUID().uuidString.prefix(8))"
            
            // Create CKAsset from demo photo
            let asset = createCKAsset(from: photoURL)
            
            if asset == nil {
                print("DemoService: Failed to create CKAsset for photo: \(photoURL.lastPathComponent)")
            }
            
            var demoProfile = UserProfile(
                userID: userID,
                deviceID: deviceID,
                deviceName: "\(config.area) User",
                profileImage: asset,
                bio: config.bio,
                interests: config.interests,
                latitude: lat,
                longitude: lon,
                lastActiveTimestamp: Date().addingTimeInterval(-Double.random(in: 0...3600)), // Active within last hour
                isCurrentlyActive: Bool.random()
            )
            
            generatedUsers.append(demoProfile)
            print("DemoService: Created demo user \(i + 1): \(config.area) User with interests: \(config.interests.map { $0.rawValue }.joined(separator: ", ")) using photo: \(photoURL.lastPathComponent)")
        }
        
        // If we need more users than we have photos, generate additional users without photos
        if count > photosToUse {
            let additionalUsersNeeded = count - photosToUse
            print("DemoService: Need \(additionalUsersNeeded) additional users without photos to fill grid")
            
            let additionalUsers = generateDemoUsersWithoutPhotos(near: currentLocation, count: additionalUsersNeeded)
            generatedUsers.append(contentsOf: additionalUsers)
        }
        
        // Sort all generated users by distance from current location (closest first)
        generatedUsers.sort { user1, user2 in
            let distance1 = currentLocation.distance(from: CLLocation(latitude: user1.latitude ?? 0, longitude: user1.longitude ?? 0))
            let distance2 = currentLocation.distance(from: CLLocation(latitude: user2.latitude ?? 0, longitude: user2.longitude ?? 0))
            return distance1 < distance2
        }
        
        print("DemoService: Successfully generated and sorted \(generatedUsers.count) demo users by distance")
        return generatedUsers
    }
    
    private func generateDemoUsersWithoutPhotos(near currentLocation: CLLocation, count: Int) -> [UserProfile] {
        var generatedUsers: [UserProfile] = []
        let configurations = DemoConfiguration.configurations
        
        for i in 0..<count {
            let config = configurations[i % configurations.count]
            
            // Generate a more realistic distance distribution (more users nearby, fewer far away)
            // Use weighted random distribution: 70% within 2km, 25% within 5km, 5% up to 8km
            let randomValue = Double.random(in: 0...1)
            let randomDistance: Double
            
            if randomValue < 0.7 {
                // 70% chance: 100m to 2km (nearby users)
                randomDistance = Double.random(in: 100...2000)
            } else if randomValue < 0.95 {
                // 25% chance: 2km to 5km (moderate distance)
                randomDistance = Double.random(in: 2000...5000)
            } else {
                // 5% chance: 5km to 8km (far away users)
                randomDistance = Double.random(in: 5000...8000)
            }
            
            let randomBearing = Double.random(in: 0...(2 * Double.pi))
            
            let lat = currentLocation.coordinate.latitude + (randomDistance / 111000.0) * cos(randomBearing)
            let lon = currentLocation.coordinate.longitude + (randomDistance / (111000.0 * cos(currentLocation.coordinate.latitude * Double.pi / 180))) * sin(randomBearing)
            
            // Create demo user profile without photo
            let deviceID = "demo_user_no_photo_\(i)_\(UUID().uuidString.prefix(8))"
            let userID = "demo_apple_id_no_photo_\(i)_\(UUID().uuidString.prefix(8))"
            
            var demoProfile = UserProfile(
                userID: userID,
                deviceID: deviceID,
                deviceName: "\(config.area) User",
                profileImage: nil, // No photo
                bio: config.bio,
                interests: config.interests,
                latitude: lat,
                longitude: lon,
                lastActiveTimestamp: Date().addingTimeInterval(-Double.random(in: 0...3600)), // Active within last hour
                isCurrentlyActive: Bool.random()
            )
            
            generatedUsers.append(demoProfile)
        }
        
        // Sort users by distance from current location (closest first)
        generatedUsers.sort { user1, user2 in
            let distance1 = currentLocation.distance(from: CLLocation(latitude: user1.latitude ?? 0, longitude: user1.longitude ?? 0))
            let distance2 = currentLocation.distance(from: CLLocation(latitude: user2.latitude ?? 0, longitude: user2.longitude ?? 0))
            return distance1 < distance2
        }
        
        print("DemoService: Generated \(generatedUsers.count) demo users without photos as fallback (sorted by distance)")
        return generatedUsers
    }
    
    private func createCKAsset(from fileURL: URL) -> CKAsset? {
        print("DemoService: Attempting to create CKAsset from: \(fileURL.path)")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("DemoService: Demo photo not found at \(fileURL.path)")
            return nil
        }
        
        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                print("DemoService: Photo file size: \(fileSize) bytes")
            }
        } catch {
            print("DemoService: Could not get file attributes: \(error)")
        }
        
        // Copy to a temporary location since CKAsset needs a file URL it can manage
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileURL.pathExtension)
        
        do {
            try FileManager.default.copyItem(at: fileURL, to: tempFile)
            print("DemoService: Successfully copied photo to temp file: \(tempFile.path)")
            let asset = CKAsset(fileURL: tempFile)
            print("DemoService: Successfully created CKAsset")
            return asset
        } catch {
            print("DemoService: Error creating CKAsset: \(error)")
            return nil
        }
    }
    
    func toggleDemoMode() {
        isDemoMode.toggle()
        print("DemoService: Demo mode toggled to: \(isDemoMode)")
        
        if isDemoMode {
            // Reload photos when entering demo mode
            print("DemoService: Entering demo mode, reloading photos...")
            loadDemoPhotos()
        } else {
            // Clear demo data when exiting demo mode
            clearDemoData()
        }
    }
    
    func shufflePhotos() {
        demoPhotos.shuffle()
        print("DemoService: Manually shuffled \(demoPhotos.count) demo photos")
    }
    
    func reloadAndShufflePhotos() {
        print("DemoService: Reloading and shuffling demo photos...")
        loadDemoPhotos() // This already includes shuffling
    }
    
    func reloadDemoPhotos() {
        print("DemoService: Manually reloading demo photos...")
        loadDemoPhotos()
    }
    
    func clearDemoData() {
        demoUsers.removeAll()
        print("DemoService: Cleared demo data")
    }
    
    func createDemoCurrentUser(from originalProfile: UserProfile) -> UserProfile? {
        guard isDemoMode else { return originalProfile }
        
        if demoPhotos.isEmpty {
            print("DemoService: No demo photos available for current user demo, reloading...")
            loadDemoPhotos()
            
            if demoPhotos.isEmpty {
                print("DemoService: Still no demo photos available for current user demo")
                return originalProfile
            }
        }
        
        // Get a random photo for the current user (shuffle to ensure variety)
        var availablePhotos = demoPhotos
        availablePhotos.shuffle()
        let randomPhoto = availablePhotos.randomElement()!
        
        // Get a random configuration
        var configurations = DemoConfiguration.configurations
        configurations.shuffle()
        let randomConfig = configurations.randomElement()!
        
        // Create CKAsset from demo photo
        let asset = createCKAsset(from: randomPhoto)
        
        if asset == nil {
            print("DemoService: Failed to create CKAsset for current user demo photo: \(randomPhoto.lastPathComponent)")
        }
        
        // Create a demo version of the current user
        var demoCurrentUser = originalProfile
        demoCurrentUser.profileImage = asset
        demoCurrentUser.bio = randomConfig.bio
        demoCurrentUser.interests = randomConfig.interests
        
        print("DemoService: Created demo version of current user with photo: \(randomPhoto.lastPathComponent) and config: \(randomConfig.area)")
        
        return demoCurrentUser
    }
} 