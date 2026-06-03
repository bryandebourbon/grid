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

    /// Loads encryption, relationships, receipts, story views, album, messages, and stories cache.
    func bootstrapSession(for profile: UserProfile) {
        enableEncryptionOnlyMode()

        loadEncryptionProfiles { [weak self] in
            guard let self = self else { return }

            self.loadStarBlockRelationships(forUserID: profile.userID) { [weak self] in
                guard let self = self else { return }

                self.loadReadReceipts(forDeviceID: profile.deviceID) { [weak self] in
                    guard let self = self else { return }

                    self.storiesService.loadStoryViewsForViewer(deviceID: profile.deviceID) { [weak self] in
                        guard let self = self else { return }

                        self.loadCurrentUserAlbum(forDeviceID: profile.deviceID) { [weak self] in
                            guard let self = self else { return }

                            self.fetchAllMessagesForCurrentDevice(deviceID: profile.deviceID)
                            self.checkForUnencryptedMessages()

                            Task {
                                await self.storiesService.refreshStories()
                            }
                        }
                    }
                }
            }
        }
    }

    func displayName(forDeviceID deviceID: String) -> String {
        ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: deviceID,
            currentDeviceID: currentUserProfile?.deviceID,
            gridNodes: gridNodes
        )
    }
}
