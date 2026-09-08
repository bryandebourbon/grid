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
    // MARK: - Messaging Methods

    /// Writes real CloudKit text + image messages to this device and walks
    /// save → fetch-by-ID → inbox → banner → query comparison.
    func sendDebugCloudKitIncomingPing() {
        runDebugIncomingExperience(.fullSuite)
    }

    func sendDebugIncomingTextBanner() {
        runDebugIncomingExperience(.textBanner)
    }

    func sendDebugIncomingPhotoBanner() {
        runDebugIncomingExperience(.photoBanner)
    }

    /// CloudKit save only. Lock the phone to wait for the real APNs banner.
    func sendDebugIncomingPushThenLock() {
        runDebugIncomingExperience(.textPushOnly)
    }

    /// Sends while that chat is open so the banner should be suppressed.
    func sendDebugIncomingWhileInThatChat() {
        runDebugIncomingExperience(.textWhileViewingSender)
    }

    private enum DebugIncomingExperience {
        case fullSuite
        case textBanner
        case photoBanner
        case textPushOnly
        case textWhileViewingSender

        var announceBanner: Bool {
            switch self {
            case .textPushOnly: return false
            default: return true
            }
        }

        var showReport: Bool {
            self == .fullSuite
        }
    }

    private func runDebugIncomingExperience(_ experience: DebugIncomingExperience) {
        guard let me = currentUserProfile else {
            presentUserFacingAlert("No profile loaded.")
            return
        }

        SenderNameCache.store("Test Peer", for: TestPeerIdentity.debugSenderDeviceID)
        if experience == .textWhileViewingSender {
            selectChatPartner(partnerDeviceID: TestPeerIdentity.debugSenderDeviceID)
        } else {
            deselectChatPartner()
        }

        MessageDeliveryTrace.start("experience \(experience) → \(me.deviceID)")
        MessageDeliveryTrace.log("peer=\(TestPeerIdentity.debugSenderDeviceID) announce=\(experience.announceBanner)")

        let finish: (MessageDeliverySuiteReport) -> Void = { [weak self] report in
            guard let self else { return }
            if experience.showReport {
                self.presentUserFacingAlert(report.summary)
            } else if experience == .textPushOnly {
                self.presentUserFacingAlert("Saved to CloudKit. Lock the phone now and watch for the Test Peer banner. Filter Xcode for [msg-test].")
            }
        }

        switch experience {
        case .photoBanner:
            runDebugImagePing(to: me, report: MessageDeliverySuiteReport(), announceBanner: true, completion: finish)
        case .fullSuite:
            runDebugTextPing(to: me, report: MessageDeliverySuiteReport(), announceBanner: true) { [weak self] report in
                guard let self else { return }
                self.runDebugImagePing(to: me, report: report, announceBanner: true, completion: finish)
            }
        case .textBanner, .textPushOnly, .textWhileViewingSender:
            runDebugTextPing(to: me, report: MessageDeliverySuiteReport(), announceBanner: experience.announceBanner, completion: finish)
        }
    }

    private func runDebugTextPing(
        to me: UserProfile,
        report: MessageDeliverySuiteReport,
        announceBanner: Bool = true,
        completion: @escaping (MessageDeliverySuiteReport) -> Void
    ) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let plaintext = "Debug ping \(stamp)"
        let built = EncryptedMessageBuilder.buildTextMessage(
            text: plaintext,
            sender: TestPeerIdentity.debugSenderProfile,
            recipientDeviceID: me.deviceID,
            recipient: me,
            encryptionProfiles: encryptionProfiles
        )
        var report = report
        report.add(
            name: "text.encrypt",
            ok: built.isEncrypted,
            detail: built.isEncrypted ? "key=\(built.encryptionKeyID ?? "?")" : "plaintext fallback"
        )

        let saveStarted = Date()
        messagingService.sendMessage(built) { [weak self] result in
            guard let self else { return }
            var report = report
            switch result {
            case .failure(let error):
                report.add(
                    name: "text.save",
                    ok: false,
                    detail: error.localizedDescription,
                    milliseconds: Self.elapsedMS(since: saveStarted)
                )
                completion(report)
            case .success(let saved):
                report.add(
                    name: "text.save",
                    ok: true,
                    detail: "id=\(saved.id.prefix(8))",
                    milliseconds: Self.elapsedMS(since: saveStarted)
                )
                self.finishDebugPing(
                    saved: saved,
                    expectedKind: "text",
                    me: me,
                    announceBanner: announceBanner,
                    report: report,
                    completion: completion
                )
            }
        }
    }

    private func runDebugImagePing(
        to me: UserProfile,
        report: MessageDeliverySuiteReport,
        announceBanner: Bool = true,
        completion: @escaping (MessageDeliverySuiteReport) -> Void
    ) {
        let imageData = MessageDeliveryTestImage.jpeg()
        let built = EncryptedMessageBuilder.buildImageMessage(
            imageData: imageData,
            sender: TestPeerIdentity.debugSenderProfile,
            recipientDeviceID: me.deviceID,
            recipient: me,
            encryptionProfiles: encryptionProfiles
        )
        var next = report
        next.add(
            name: "image.encrypt",
            ok: built.message.encryptedImageData != nil,
            detail: built.message.isEncrypted
                ? "\(imageData.count)b key=\(built.message.encryptionKeyID ?? "?")"
                : "unencrypted asset fallback"
        )

        let saveStarted = Date()
        messagingService.sendMessage(built.message) { [weak self] result in
            if let url = built.cleanupURL { try? FileManager.default.removeItem(at: url) }
            guard let self else { return }
            switch result {
            case .failure(let error):
                next.add(
                    name: "image.save",
                    ok: false,
                    detail: error.localizedDescription,
                    milliseconds: Self.elapsedMS(since: saveStarted)
                )
                completion(next)
            case .success(let saved):
                next.add(
                    name: "image.save",
                    ok: true,
                    detail: "id=\(saved.id.prefix(8))",
                    milliseconds: Self.elapsedMS(since: saveStarted)
                )
                self.finishDebugPing(
                    saved: saved,
                    expectedKind: "image",
                    me: me,
                    announceBanner: announceBanner,
                    report: next,
                    completion: completion
                )
            }
        }
    }

    private func finishDebugPing(
        saved: Message,
        expectedKind: String,
        me: UserProfile,
        announceBanner: Bool,
        report: MessageDeliverySuiteReport,
        completion: @escaping (MessageDeliverySuiteReport) -> Void
    ) {
        let recordID = saved.recordID ?? CKRecord.ID(recordName: saved.id)
        PendingMessageFetchStore.enqueue(saved.id)
        let fetchStarted = Date()
        messagingService.fetchMessage(
            withRecordID: recordID,
            currentDeviceID: me.deviceID,
            announce: false
        ) { [weak self] result in
            guard let self else { return }
            var report = report
            switch result {
            case .failure(let error):
                report.add(
                    name: "\(expectedKind).fetchByID",
                    ok: false,
                    detail: error.localizedDescription,
                    milliseconds: Self.elapsedMS(since: fetchStarted)
                )
                completion(report)
            case .success(let fetched):
                report.add(
                    name: "\(expectedKind).fetchByID",
                    ok: true,
                    detail: "encrypted=\(fetched.isEncrypted)",
                    milliseconds: Self.elapsedMS(since: fetchStarted)
                )
                self.ingestIncomingMessage(fetched)
                let inInbox = self.messages.contains { $0.id == fetched.id }
                report.add(name: "\(expectedKind).inbox", ok: inInbox, detail: inInbox ? "present" : "missing")

                if expectedKind == "image" {
                    let bytes = self.decryptImageMessage(fetched)?.count ?? 0
                    report.add(
                        name: "image.decrypt",
                        ok: bytes > 0,
                        detail: bytes > 0 ? "\(bytes)b" : "Failed to decrypt image"
                    )
                }

                let preview = MessageBannerLogic.previewText(
                    message: fetched,
                    decryptedText: MessageBannerNotifier.decryptedPreview(for: fetched)
                )
                let expectedPreview = expectedKind == "image"
                    ? MessageBannerLogic.photoBody
                    : preview
                if announceBanner {
                    MessageBannerNotifier.announce(fetched, currentDeviceID: me.deviceID)
                    report.add(
                        name: "\(expectedKind).banner",
                        ok: expectedKind == "image" ? preview == MessageBannerLogic.photoBody : preview.isEmpty == false,
                        detail: "\"\(expectedPreview)\""
                    )
                } else {
                    report.add(name: "\(expectedKind).banner", ok: true, detail: "skipped; wait for APNs")
                }

                self.compareQueryAgainstFetch(savedID: fetched.id, me: me, kind: expectedKind, report: report, completion: completion)
            }
        }
    }

    private func compareQueryAgainstFetch(
        savedID: String,
        me: UserProfile,
        kind: String,
        report: MessageDeliverySuiteReport,
        completion: @escaping (MessageDeliverySuiteReport) -> Void
    ) {
        let queryStarted = Date()
        messagingService.fetchMessages(forDeviceID: me.deviceID) { [weak self] result in
            guard let self else { return }
            var report = report
            switch result {
            case .failure(let error):
                report.add(
                    name: "\(kind).query",
                    ok: false,
                    detail: error.localizedDescription,
                    milliseconds: Self.elapsedMS(since: queryStarted)
                )
            case .success(let queried):
                let queryHasIt = queried.contains { $0.id == savedID }
                report.add(
                    name: "\(kind).query",
                    ok: true,
                    detail: queryHasIt ? "query already sees it" : "query still stale; inbox kept fetch-by-ID",
                    milliseconds: Self.elapsedMS(since: queryStarted)
                )
                self.applyIncomingMessages(queried)
            }
            completion(report)
        }
    }

    private static func elapsedMS(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    func selectChatPartner(partnerDeviceID: String) {
        self.currentChatRecipientDeviceID = partnerDeviceID
        ForegroundChatState.partnerDeviceID = partnerDeviceID
        print("Selected chat partner device: \(partnerDeviceID)")
    }

    func openChatOverlay(with deviceID: String) {
        chatOverlaySession.open(with: deviceID)
        uiTestOpenedPartner = deviceID
        selectChatPartner(partnerDeviceID: deviceID)
        objectWillChange.send()
    }

    func hideChatOverlay() {
        chatOverlaySession.hide()
        deselectChatPartner()
    }

    func deselectChatPartner() {
        currentChatRecipientDeviceID = nil
        ForegroundChatState.partnerDeviceID = nil
    }

    func toggleReaction(_ emoji: String, on messageID: String) {
        guard let me = currentUserProfile?.deviceID,
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let updated = MessageReactionLogic.toggle(
            emoji: emoji,
            reactorDeviceID: me,
            on: messages[index]
        )
        messages[index] = updated
        MessageInboxStore.save(messages)
        objectWillChange.send()
        guard !LocalLLMIdentity.involves(updated), updated.status != .sending else { return }
        messagingService.updateReactions(on: updated) { result in
            if case .failure(let error) = result {
                print("Could not sync reaction: \(error.localizedDescription)")
            }
        }
    }

    // Simplified sendMessage - can message anyone you can see
    func sendMessage(text: String, to recipientDeviceID: String) {
        if LocalLLMIdentity.isLLM(recipientDeviceID) {
            sendLocalLLMMessage(text: text)
            return
        }

        guard let senderProfile = currentUserProfile else { return }
        guard let recipientProfile = recipientProfile(for: recipientDeviceID, sender: senderProfile) else { return }

        let optimisticMessage = EncryptedMessageBuilder.buildTextMessage(
            text: text,
            sender: senderProfile,
            recipientDeviceID: recipientDeviceID,
            recipient: recipientProfile,
            encryptionProfiles: encryptionProfiles
        )
        let temporaryID = optimisticMessage.id
        messages.append(optimisticMessage)
        messages.sort { $0.timestamp < $1.timestamp }

        messagingService.sendMessage(optimisticMessage) { [weak self] result in
            guard let self else { return }
            OptimisticMessageSync.applySendResult(messages: &self.messages, temporaryID: temporaryID, result: result)
            MessageInboxStore.save(self.messages)
        }
    }

    func statusText(for deviceID: String) -> String? {
        if deviceID == currentUserProfile?.deviceID {
            let bio = currentUserProfile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return bio.isEmpty ? nil : bio
        }
        if LocalLLMIdentity.isLLM(deviceID) {
            let bio = LocalLLMIdentity.bio.trimmingCharacters(in: .whitespacesAndNewlines)
            return bio.isEmpty ? nil : bio
        }
        let bio = findNode(forDeviceID: deviceID)?.userProfile?.bio?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bio.isEmpty ? nil : bio
    }

    func recipientProfile(for recipientDeviceID: String, sender: UserProfile) -> UserProfile? {
        if LocalLLMIdentity.isLLM(recipientDeviceID) { return LocalLLMIdentity.profile }
        if recipientDeviceID == sender.deviceID { return sender }
        return findNode(forDeviceID: recipientDeviceID)?.userProfile
    }

    func sendLocalLLMMessage(text: String) {
        guard let sender = currentUserProfile else { return }
        let llm = LocalLLMIdentity.profile

        let userMessage = Message(
            senderDeviceID: sender.deviceID,
            recipientDeviceID: llm.deviceID,
            senderUserID: sender.userID,
            recipientUserID: llm.userID,
            text: text,
            status: .sent
        )
        messages.append(userMessage)

        let pendingID = UUID().uuidString
        let pending = Message(
            id: pendingID,
            senderDeviceID: llm.deviceID,
            recipientDeviceID: sender.deviceID,
            senderUserID: llm.userID,
            recipientUserID: sender.userID,
            text: "…",
            status: .sending
        )
        messages.append(pending)
        messages.sort { $0.timestamp < $1.timestamp }
        LocalLLMMessageStore.save(messages)

        let history = messages.filter { LocalLLMIdentity.involves($0) && $0.id != pendingID }
        let currentDeviceID = sender.deviceID

        Task { [weak self] in
            let reply = await LocalLLMService.shared.reply(
                to: text,
                priorMessages: history,
                currentDeviceID: currentDeviceID
            )
            guard let self else { return }
            if let index = self.messages.firstIndex(where: { $0.id == pendingID }) {
                self.messages[index].text = reply
                self.messages[index].status = .received
            }
            LocalLLMMessageStore.save(self.messages)
            self.objectWillChange.send()
        }
    }

    // NEW: Auto-refresh when location is obtained or app state changes
    func autoRefreshGrid(with location: CLLocation? = nil) {
        print("Auto-refreshing grid with current location...")
        let locationToUse = location ?? locationService.currentLocation
        proximityService.fetchAllUsers(currentUserLocation: locationToUse)
    }

    // NEW: Call this when grid appears (from GridView)
    func handleGridAppeared() {
        print("Grid appeared - getting current location and refreshing...")
        if locksGridToFixtures { return }

        // Ensure location services are active
        locationService.requestLocationPermission()
        
        // Request location once for this grid refresh
        locationService.requestLocationOnce()
        
        // Wait a moment for location to be available, then refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            if let currentLocation = self.locationService.currentLocation {
                // Manually trigger location update and grid refresh
                self.handleLocationUpdate(currentLocation)
            } else {
                // No location yet, just refresh with existing data
                print("No location available yet, refreshing with existing data")
                self.autoRefreshGrid()
            }
        }
    }

    func sendImageMessage(imageData: Data, to recipientDeviceID: String) {
        if LocalLLMIdentity.isLLM(recipientDeviceID) {
            presentUserFacingAlert("The local assistant can only read text for now.")
            return
        }

        #if canImport(UIKit)
        let moderationResult = contentModerationService.isImageAppropriate(imageData)
        if !moderationResult.isAppropriate {
            presentUserFacingAlert(moderationResult.reason ?? "That image was blocked by the content filter.")
            return
        }
        #endif

        guard let senderProfile = currentUserProfile else { return }
        guard let recipientProfile = recipientProfile(for: recipientDeviceID, sender: senderProfile) else { return }

        let built = EncryptedMessageBuilder.buildImageMessage(
            imageData: imageData,
            sender: senderProfile,
            recipientDeviceID: recipientDeviceID,
            recipient: recipientProfile,
            encryptionProfiles: encryptionProfiles
        )
        let temporaryID = built.message.id
        messages.append(built.message)
        messages.sort { $0.timestamp < $1.timestamp }

        messagingService.sendMessage(built.message) { [weak self] result in
            guard let self else {
                if let url = built.cleanupURL { try? FileManager.default.removeItem(at: url) }
                return
            }
            OptimisticMessageSync.applySendResult(messages: &self.messages, temporaryID: temporaryID, result: result)
            MessageInboxStore.save(self.messages)
            if let url = built.cleanupURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    func performFullAccountDeletion(completion: @escaping (Error?) -> Void) {
        guard let userIDToDelete = currentUserProfile?.userID else {
            print("GridViewModel: UserID not found, cannot perform account deletion.")
            completion(NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found."]))
            return
        }

        let deviceID = currentUserProfile?.deviceID ?? ""
        print("GridViewModel: Starting full account deletion for userID: \(userIDToDelete)")
        if !deviceID.isEmpty {
            messagingService.unsubscribeFromMessageChanges(forDeviceID: deviceID)
        }

        accountDeletionService.deleteAllRecords(
            forUserID: userIDToDelete,
            deviceID: deviceID
        ) { error in
            CryptoService.shared.deleteStoredKeys()
            self.hasEncryptionKeys = false
            if error == nil {
                print("GridViewModel: Successfully deleted all user-owned records for userID: \(userIDToDelete)")
            }
            completion(error)
        }
    }

    func updateUserProfileBio(bio: String, completion: @escaping (Bool) -> Void) {
        guard var userProfile = self.currentUserProfile else {
            print("No current user profile to update bio for.")
            completion(false)
            return
        }

        userProfile.bio = bio

        // Optimistically update local profile
        self.currentUserProfile?.bio = bio
        
        // Save to CloudKit using proximityService
        proximityService.updateUserActivity(userProfile) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedProfile):
                    // Update local profile with the one returned from save (might have updated recordID etc.)
                    self?.currentUserProfile = savedProfile
                    self?.objectWillChange.send() // Notify views
                    print("User bio updated and saved successfully.")
                    completion(true)
                case .failure(let error):
                    print("Error saving user profile bio to CloudKit: \\(error.localizedDescription)")
                    // Revert optimistic update on failure
                    self?.currentUserProfile?.bio = userProfile.bio // Restore previous value
                    completion(false)
                }
            }
        }
    }
    
    func updateUserProfileInterests(interests: [Interest], completion: @escaping (Bool) -> Void) {
        guard var userProfile = self.currentUserProfile else {
            print("No current user profile to update interests for.")
            completion(false)
            return
        }

        let oldInterests = userProfile.interests
        userProfile.interests = interests

        // Optimistically update local profile
        self.currentUserProfile?.interests = interests
        
        // Save to CloudKit using proximityService
        proximityService.updateUserActivity(userProfile) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedProfile):
                    // Update local profile with the one returned from save
                    self?.currentUserProfile = savedProfile
                    self?.objectWillChange.send() // Notify views
                    print("User interests updated and saved successfully. New interests: \(interests.map { $0.rawValue })")
                    
                    // Update the proximityService.activeNearbyProfiles array with the updated profile
                    if let proximityService = self?.proximityService {
                        // Find and update the current user's profile in the activeNearbyProfiles array
                        if let index = proximityService.activeNearbyProfiles.firstIndex(where: { $0.deviceID == savedProfile.deviceID }) {
                            proximityService.activeNearbyProfiles[index] = savedProfile
                        }
                        
                        // Now refresh the grid with the updated profiles
                        self?.updateGridWithAllProfiles(proximityService.activeNearbyProfiles)
                    }
                    
                    completion(true)
                case .failure(let error):
                    print("Error saving user profile interests to CloudKit: \(error.localizedDescription)")
                    // Revert optimistic update on failure
                    self?.currentUserProfile?.interests = oldInterests
                    completion(false)
                }
            }
        }
    }

    // NEW: Check CloudKit availability before attempting operations
    func checkCloudKitAvailability(completion: @escaping (Bool, String?) -> Void) {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    completion(true, nil)
                case .noAccount:
                    completion(false, "No iCloud account found. Please sign in to iCloud in Settings.")
                case .restricted:
                    completion(false, "iCloud access is restricted on this device.")
                case .couldNotDetermine:
                    completion(false, "Could not determine iCloud status. Please try again.")
                case .temporarilyUnavailable:
                    completion(false, "iCloud is temporarily unavailable. Please try again later.")
                @unknown default:
                    completion(false, "Unknown iCloud status.")
                }
            }
        }
    }
}
