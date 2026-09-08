import Foundation
import CloudKit

/// Local snapshot so a debug test peer can open the grid without iCloud.
enum TestPeerProfileStore {
    static let snapshotKey = "grid.testPeer.profileSnapshot"
    static let photoKey = "grid.testPeer.photoJPEG"

    struct Snapshot: Codable {
        var userID: String
        var deviceID: String
        var deviceName: String
        var bio: String?
        var interests: [String]
    }

    static func makeDefault(userID: String, deviceID: String) -> UserProfile {
        let photo = ProfileCreationLogic.placeholderPhotoJPEG()
        UserDefaults.standard.set(photo, forKey: photoKey)
        return profile(
            userID: userID,
            deviceID: deviceID,
            deviceName: "Test Peer",
            bio: "Simulator test peer",
            interests: [.technology, .music],
            photoData: photo
        )
    }

    static func save(_ profile: UserProfile) {
        let snapshot = Snapshot(
            userID: profile.userID,
            deviceID: profile.deviceID,
            deviceName: profile.deviceName,
            bio: profile.bio,
            interests: profile.interests.map(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    static func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return profile(
            userID: snapshot.userID,
            deviceID: snapshot.deviceID,
            deviceName: snapshot.deviceName,
            bio: snapshot.bio,
            interests: snapshot.interests.map(Interest.init(rawValue:)),
            photoData: UserDefaults.standard.data(forKey: photoKey)
        )
    }

    private static func profile(
        userID: String,
        deviceID: String,
        deviceName: String,
        bio: String?,
        interests: [Interest],
        photoData: Data?
    ) -> UserProfile {
        var asset: CKAsset?
        if let photoData, let url = writeTempPhoto(photoData) {
            asset = CKAsset(fileURL: url)
        }
        return UserProfile(
            userID: userID,
            deviceID: deviceID,
            deviceName: deviceName,
            profileImage: asset,
            bio: bio,
            interests: interests
        )
    }

    private static func writeTempPhoto(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grid-test-peer")
            .appendingPathExtension("jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
