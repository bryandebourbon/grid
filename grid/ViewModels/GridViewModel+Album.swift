import Combine
import SwiftUI
import CloudKit
import CoreLocation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension GridViewModel {
    // MARK: - Album Management

    func createAlbumIfNeeded() async -> AlbumResult {
        guard let currentProfile = currentUserProfile else {
            return .failure("No current user profile")
        }
        if let existing = userAlbums[currentProfile.deviceID] {
            return .success(existing)
        }
        let result = await albumService.createAlbum(for: currentProfile)
        if result.success, let album = result.album {
            userAlbums[currentProfile.deviceID] = album
        }
        return result
    }

    func pinStoryToAlbum(_ story: Story) async -> PinResult {
        guard let currentProfile = currentUserProfile else {
            return .failure("No current user profile")
        }
        guard story.deviceID == currentProfile.deviceID else {
            return .failure("Cannot pin other users' stories")
        }
        let albumResult = await createAlbumIfNeeded()
        guard albumResult.success, var album = albumResult.album else {
            return .failure(albumResult.error ?? "Failed to get or create album")
        }
        let pinResult = albumService.pinStory(story, to: &album)
        guard pinResult.success else { return pinResult }
        let saveResult = await albumService.saveAlbum(album)
        if saveResult.success, let saved = saveResult.album {
            userAlbums[currentProfile.deviceID] = saved
            return .success()
        }
        return .failure(saveResult.error ?? "Failed to save album")
    }

    func unpinStoryIDFromAlbum(_ storyID: String) async -> PinResult {
        guard let currentProfile = currentUserProfile else {
            return .failure("No current user profile")
        }
        guard var album = userAlbums[currentProfile.deviceID] else {
            return .failure("No album found")
        }
        guard album.removePhoto(storyID: storyID) else {
            return .failure("Story not found in album")
        }
        let saveResult = await albumService.saveAlbum(album)
        if saveResult.success, let saved = saveResult.album {
            userAlbums[currentProfile.deviceID] = saved
            return .success()
        }
        return .failure(saveResult.error ?? "Failed to save album")
    }

    func unpinStoryFromAlbum(_ story: Story) async -> PinResult {
        await unpinStoryIDFromAlbum(story.id)
    }

    func getAlbum(for deviceID: String) async -> Album? {
        if let cached = userAlbums[deviceID] { return cached }
        guard let album = await albumService.fetchAlbum(ownerDeviceID: deviceID) else { return nil }
        userAlbums[deviceID] = album
        return album
    }
    
    /// Check if a story is pinned in current user's album
    func isStoryPinned(_ storyID: String) -> Bool {
        guard let currentProfile = currentUserProfile else {
            return false
        }
        
        guard let album = userAlbums[currentProfile.deviceID] else {
            return false
        }
        
        return album.isPhotoPinned(storyID: storyID)
    }
    
    /// Get current user's album
    func getCurrentUserAlbum() async -> Album? {
        guard let currentProfile = currentUserProfile else {
            return nil
        }
        
        return await getAlbum(for: currentProfile.deviceID)
    }
    
    // MARK: - Initialization Helpers

    /// Load current user's album from CloudKit on app startup
    func loadCurrentUserAlbum(forDeviceID deviceID: String, completion: @escaping () -> Void = {}) {
        Task {
            if let album = await getAlbum(for: deviceID) {
                AppLog.album.debug("Loaded album with \(album.photosCount, privacy: .public) pinned photos")
            } else {
                AppLog.album.debug("No album for device")
            }
            
            await MainActor.run {
                completion()
            }
        }
    }
}
