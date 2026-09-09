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
    // MARK: - Encryption Mode Support
    
    func loadEncryptionProfiles(completion: @escaping () -> Void = {}) {
        encryptionProfileService.loadEnabledProfiles { [weak self] profiles in
            guard let self = self else {
                completion()
                return
            }
            // Merge into the existing cache rather than replacing it.
            for profile in profiles {
                self.encryptionProfiles[profile.id] = profile
            }
            print("GridViewModel: loaded \(profiles.count) encryption profiles")
            self.refreshGridForEncryptionMode()
            completion()
        }
    }
    
    func refreshGridForEncryptionMode() {
        // All messaging is now encrypted by default - always filter to show encryption-enabled profiles
        let encryptedDeviceIDs = Set(encryptionProfiles.keys)
        // Always include current user in encryption mode
        let currentDeviceID = currentUserProfile?.deviceID
        let filteredProfiles = proximityService.activeNearbyProfiles.filter { profile in
            // Check encryption requirement
            let hasEncryption = profile.deviceID == currentDeviceID || encryptedDeviceIDs.contains(profile.deviceID)
            
            // Also check blocking status
            let isNotBlocked = profile.deviceID == currentDeviceID || (!blockedUsers.contains(profile.userID) && !usersWhoBlockedMe.contains(profile.userID))
            
            return hasEncryption && isNotBlocked
        }
        updateGridWithAllProfiles(filteredProfiles)
    }
    
    // Get encryption profile for a device
    func getEncryptionProfile(for deviceID: String) -> EncryptionProfile? {
        return encryptionProfiles[deviceID]
    }
    
    // Decrypt message for display
    func decryptMessage(_ message: Message) -> String {
        if let cached = decryptedTextCache[message.id] {
            return cached
        }
        guard message.isEncrypted,
              let encryptedContentString = message.encryptedContent,
              let encryptedContent = Data(base64Encoded: encryptedContentString),  // Convert from base64 string
              let privateKey = CryptoService.shared.getPrivateKey() else {
            return message.text
        }
        
        let text = CryptoService.shared.decrypt(data: encryptedContent, withPrivateKey: privateKey)
            ?? MessageDecryptabilityLogic.failedTextPlaceholder
        decryptedTextCache[message.id] = text
        return text
    }
    
    // Decrypt image for display
    func decryptImageMessage(_ message: Message) -> Data? {
        if failedDecryptIDs.contains(message.id) {
            return nil
        }
        if let cached = decryptedImageCache[message.id] {
            return cached
        }
        if let disk = PhotoDiskCache.load(kind: .message, id: message.id) {
            decryptedImageCache[message.id] = disk
            return disk
        }
        guard message.isEncrypted,
              let encryptedImageDataString = message.encryptedImageData,
              let encryptedImageData = Data(base64Encoded: encryptedImageDataString),
              let privateKey = CryptoService.shared.getPrivateKey() else {
            return nil
        }
        
        if let decryptedImageData = CryptoService.shared.decryptImage(data: encryptedImageData, withPrivateKey: privateKey) {
            decryptedImageCache[message.id] = decryptedImageData
            PhotoDiskCache.save(kind: .message, id: message.id, data: decryptedImageData)
            return decryptedImageData
        }
        failedDecryptIDs.insert(message.id)
        return nil
    }

    // NEW: Report a user for inappropriate content
    func reportUser(
        deviceID: String,
        reason: Report.ReportReason,
        description: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let currentUserID = currentUserProfile?.userID,
              let reportedUserID = getUserID(forDeviceID: deviceID) else { 
            print("Error: Missing user IDs for report")
            completion?(.failure(NSError(
                domain: "GridViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not identify the reported user."]
            )))
            return 
        }
        
        let report = Report(
            reporterUserID: currentUserID,
            reportedUserID: reportedUserID,
            reportedDeviceID: deviceID,
            reportReason: reason,
            reportDescription: description
        )
        
        reportService.submit(report) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if !self.isBlocked(deviceID) { self.toggleBlock(for: deviceID) }
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }
    
    // MARK: - Privacy and Content Moderation Methods
    
    /// Send message with content filtering
    func sendMessageWithModeration(text: String, to recipientDeviceID: String, isEncrypted: Bool = false) {
        // First check content appropriateness
        let moderationResult = contentModerationService.isMessageAppropriate(text)
        
        if !moderationResult.isAppropriate {
            presentUserFacingAlert(moderationResult.reason ?? "That message was blocked by the content filter.")
            return
        }
        
        // If content is appropriate, send the message normally
        // Note: encryption is handled automatically since all messaging is now encrypted by default
        sendMessage(text: text, to: recipientDeviceID)
        
        // Local no-op hook unless a privacy-compliant analytics provider is added.
        privacyService.trackEvent("message_sent", parameters: [
            "recipient_type": recipientDeviceID == currentUserProfile?.deviceID ? "self" : "other",
            "is_encrypted": isEncrypted,
            "message_length": text.count
        ])
    }
    
    /// Update bio with content filtering
    func updateUserProfileBioWithModeration(bio: String, completion: @escaping (Bool, String?) -> Void) {
        // Check bio appropriateness
        let moderationResult = contentModerationService.isBioAppropriate(bio)
        
        if !moderationResult.isAppropriate {
            completion(false, moderationResult.reason)
            return
        }
        
        // If bio is appropriate, update normally
        updateUserProfileBio(bio: bio) { [weak self] success in
            if success {
                self?.privacyService.trackEvent("bio_updated", parameters: [
                    "bio_length": bio.count
                ])
            }
            completion(success, nil)
        }
    }
    
    /// Update profile image with content filtering
    func updateCurrentProfileImageWithModeration(newPhotoData: Data) {
        #if canImport(UIKit)
        // Check image appropriateness
        let moderationResult = contentModerationService.isImageAppropriate(newPhotoData)
        
        if !moderationResult.isAppropriate {
            presentUserFacingAlert(moderationResult.reason ?? "That image was blocked by the content filter.")
            return
        }
        #endif
        
        // If image is appropriate, update normally
        updateCurrentProfileImage(newPhotoData: newPhotoData)
        
        // Track the event
        privacyService.trackEvent("profile_image_updated", parameters: [
            "image_size_kb": newPhotoData.count / 1024
        ])
    }
    
    /// Report user with automatic content analysis
    func reportUserWithAnalysis(
        deviceID: String,
        reason: Report.ReportReason,
        description: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // If there's a description, analyze it for appropriateness
        if let desc = description, !desc.isEmpty {
            let moderationResult = contentModerationService.isTextAppropriate(desc)
            if !moderationResult.isAppropriate {
                print("Report description blocked by content filter")
                completion?(.failure(NSError(
                    domain: "GridViewModel",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: moderationResult.reason ?? "Report description was blocked by the content filter."]
                )))
                return
            }
        }
        
        // Submit the report
        reportUser(deviceID: deviceID, reason: reason, description: description, completion: completion)
        
        // Track the event
        privacyService.trackEvent("user_reported", parameters: [
            "reason": reason.rawValue,
            "has_description": description != nil
        ])
    }
    
    // MARK: - Interest Filter Methods
    
    /// Toggle interest filter on/off
    func addCustomInterest(named name: String, emoji: String) {
        guard let interest = CustomInterestStore.add(name: name, emoji: emoji) else { return }
        if interest.isCustom {
            let published = CustomInterestRecord(
                name: interest.rawValue,
                emoji: CustomInterestStore.emoji(for: interest.rawValue) ?? emoji
            )
            sharedInterestService.publish(published, createdByUserID: currentUserProfile?.userID)
            ingestSharedInterests([published])
        }
        openInterestPage(interest)
        objectWillChange.send()
    }

    func focusInterestForNearby(_ interest: Interest) {
        openInterestPage(interest)
    }

    func toggleInterestFilter(_ interest: Interest) {
        if selectedInterestFilter.contains(interest) {
            selectedInterestFilter.remove(interest)
            if lastTappedInterest == interest {
                lastTappedInterest = selectedInterestFilter.sorted { $0.rawValue < $1.rawValue }.first
            }
        } else {
            selectedInterestFilter.insert(interest)
            lastTappedInterest = interest
        }
    }
    
    /// Remove specific interest from filter
    func removeInterestFilter(_ interest: Interest) {
        selectedInterestFilter.remove(interest)
        if lastTappedInterest == interest {
            lastTappedInterest = selectedInterestFilter.sorted { $0.rawValue < $1.rawValue }.first
        }
    }
    
    /// Clear all interest filters
    func clearInterestFilter() {
        selectedInterestFilter.removeAll()
        lastTappedInterest = nil
    }
    
    /// Check if interest filter is active
    var hasActiveInterestFilter: Bool {
        return !selectedInterestFilter.isEmpty
    }
    
    // MARK: - Encryption-Only Mode Methods
    
    /// Enable encryption for all messaging (called automatically on init)
    func enableEncryptionOnlyMode() {
        print("GridViewModel: Enabling encryption-only mode...")
        
        // Check if keys exist
        hasEncryptionKeys = CryptoService.shared.hasEncryptionKeys()
        
        if !hasEncryptionKeys {
            // Generate new keys
            if let (publicKey, _) = CryptoService.shared.generateKeyPair() {
                hasEncryptionKeys = true
                
                // Create and save encryption profile
                guard let deviceID = currentUserProfile?.deviceID else { return }
                let encryptionProfile = EncryptionProfile(deviceID: deviceID, publicKey: publicKey)
                
                // Add to local cache immediately
                encryptionProfiles[deviceID] = encryptionProfile
                
                encryptionProfileService.save(encryptionProfile)
            }
        } else {
            // Keys exist, ensure our profile is published
            guard let deviceID = currentUserProfile?.deviceID,
                  let publicKey = CryptoService.shared.getPublicKey() else { return }
            let encryptionProfile = EncryptionProfile(deviceID: deviceID, publicKey: publicKey)
            
            // Add to local cache immediately
            encryptionProfiles[deviceID] = encryptionProfile
            
            encryptionProfileService.save(encryptionProfile)
        }
        
        // Note: loadEncryptionProfiles() is now called explicitly in the initialization sequence
    }
    
    // Check if there are unread messages (all messages are now encrypted)
    func hasUnreadMessages() -> Bool {
        guard let currentDeviceID = currentUserProfile?.deviceID else { return false }
        return readableMessages().contains { message in
            message.recipientDeviceID == currentDeviceID &&
            message.senderDeviceID != currentDeviceID &&
            !readReceipts.contains(message.id)
        }
    }

    func messageIsReadable(_ message: Message) -> Bool {
        if failedDecryptIDs.contains(message.id) { return false }
        if message.encryptedImageData != nil {
            return true
        }
        if message.isEncrypted {
            return !MessageDecryptabilityLogic.isUndecryptableText(decryptMessage(message))
        }
        return true
    }

    func readableMessages() -> [Message] {
        messages.filter(messageIsReadable)
    }
}
