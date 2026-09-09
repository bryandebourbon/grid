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
        loadPersistedInbox()
        loadPersistedAlbums()
        readReceipts.formUnion(ReadReceiptStore.load())
        mergeLocalLLMMessages()
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

                            self.refreshIncomingMessages()
                            self.refreshSharedInterestCatalog()

                            Task {
                                await self.storiesService.refreshStories()
                            }
                        }
                    }
                }
            }
        }
    }

    func warmDecryptionCache() {
        for message in messages where message.isEncrypted && message.encryptedImageData == nil {
            _ = decryptMessage(message)
        }
    }

    func mergeLocalLLMMessages() {
        let stored = LocalLLMMessageStore.load()
        guard stored.isEmpty == false else { return }
        let existingIDs = Set(messages.map(\.id))
        let extra = stored.filter { !existingIDs.contains($0.id) }
        guard extra.isEmpty == false else { return }
        messages.append(contentsOf: extra)
        messages.sort { $0.timestamp < $1.timestamp }
    }

    func displayName(forDeviceID deviceID: String) -> String {
        ProfileDisplayNameLogic.chatTitle(
            recipientDeviceID: deviceID,
            currentDeviceID: currentUserProfile?.deviceID,
            gridNodes: allGridNodes
        )
    }
}
