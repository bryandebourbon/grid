import Foundation

@MainActor
extension StoriesService {

    func hasActiveStories(for deviceID: String) -> Bool {
        allActiveStories.contains { $0.deviceID == deviceID && $0.isValid }
    }

    func uploadStoryAndRefresh(
        imageData: Data,
        caption: String?,
        userID: String,
        deviceID: String
    ) async throws -> Story {
        let story = try await uploadStory(
            imageData: imageData,
            caption: caption,
            userID: userID,
            deviceID: deviceID
        )
        await refreshStories()
        return story
    }

    func storiesForViewer(
        deviceID: String,
        viewerDeviceID: String
    ) async -> (stories: [Story], hasUnviewed: Bool) {
        await getStoriesForDevice(deviceID, viewerDeviceID: viewerDeviceID)
    }

    func hasUnviewedStories(for deviceID: String, viewerDeviceID: String) async -> Bool {
        let result = await getStoriesForDevice(deviceID, viewerDeviceID: viewerDeviceID)
        return result.hasUnviewed
    }
}
