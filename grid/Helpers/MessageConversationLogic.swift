import Foundation

/// Pure conversation grouping/filtering used by `GridViewModel` (no CloudKit).
enum MessageConversationLogic {

    struct ConversationSummary {
        let deviceID: String
        let displayName: String
        let partnerUserID: String?
        let lastMessage: Message?
        let messageCount: Int
        let unreadCount: Int
    }

    struct PinnedPerson {
        let deviceID: String
        let userID: String
        let displayName: String
        let unreadCount: Int
    }

    static func messages(
        inConversationWith partnerDeviceID: String,
        currentDeviceID: String,
        from allMessages: [Message]
    ) -> [Message] {
        allMessages.filter { message in
            (message.senderDeviceID == currentDeviceID && message.recipientDeviceID == partnerDeviceID) ||
            (message.senderDeviceID == partnerDeviceID && message.recipientDeviceID == currentDeviceID)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func newestPage(from messages: [Message], count: Int) -> [Message] {
        guard count > 0 else { return [] }
        guard messages.count > count else { return messages }
        return Array(messages.suffix(count))
    }

    static func lastSelfMessage(for deviceID: String, in messages: [Message]) -> Message? {
        messages
            .filter { $0.senderDeviceID == deviceID && $0.recipientDeviceID == deviceID }
            .max { $0.timestamp < $1.timestamp }
    }

    static func conversationList(
        currentDeviceID: String,
        messages: [Message],
        readReceipts: Set<String> = [],
        displayNameLookup: (String) -> String
    ) -> [ConversationSummary] {
        let grouped = Dictionary(grouping: messages) { message in
            message.senderDeviceID == currentDeviceID ? message.recipientDeviceID : message.senderDeviceID
        }

        return grouped.compactMap { partnerID, thread -> ConversationSummary? in
            guard partnerID != currentDeviceID else { return nil }
            let sorted = thread.sorted { $0.timestamp < $1.timestamp }
            let last = sorted.last
            return ConversationSummary(
                deviceID: partnerID,
                displayName: displayNameLookup(partnerID),
                partnerUserID: partnerUserID(partnerID: partnerID, lastMessage: last),
                lastMessage: last,
                messageCount: thread.count,
                unreadCount: MessageReadLogic.unreadCount(
                    from: partnerID,
                    currentDeviceID: currentDeviceID,
                    messages: thread,
                    readReceipts: readReceipts
                )
            )
        }
        .sorted { lhs, rhs in
            guard let d1 = lhs.lastMessage?.timestamp, let d2 = rhs.lastMessage?.timestamp else {
                return lhs.lastMessage != nil && rhs.lastMessage == nil
            }
            return d1 > d2
        }
    }

    static func previewLine(
        message: Message,
        currentDeviceID: String,
        partnerName: String,
        decryptedText: String?,
        nameForDevice: (String) -> String
    ) -> String {
        if let reaction = message.reactions.last {
            let reactor = reaction.reactorDeviceID == currentDeviceID
                ? "You"
                : (ProfileDisplayNameLogic.personName(from: nameForDevice(reaction.reactorDeviceID)) ?? partnerName)
            let target = photoPreviewNoun(message)
            switch reaction.emoji {
            case "❤️":
                return "\(reactor) loved \(target)"
            case "👍":
                return "\(reactor) liked \(target)"
            case "👎":
                return "\(reactor) disliked \(target)"
            case "😂":
                return "\(reactor) laughed at \(target)"
            default:
                return "\(reactor) reacted to \(target)"
            }
        }

        if isPhoto(message) {
            return message.senderDeviceID == currentDeviceID ? "You sent a photo" : "A photo was sent"
        }

        let raw = (decryptedText ?? message.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if isPlaceholderText(raw) {
            text = MessageBannerLogic.genericBody
        } else {
            text = raw
        }
        if message.senderDeviceID == currentDeviceID {
            return "You: \(text)"
        }
        return text
    }

    static func listTimestamp(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func isPhoto(_ message: Message) -> Bool {
        message.imageAsset != nil
            || message.encryptedImageData != nil
            || message.text == MessageBannerLogic.encryptedImagePlaceholder
    }

    struct HomeFilter {
        var visibleUserIDs: Set<String>? = nil
        var pinnedUserIDs: Set<String>
        var blockedUserIDs: Set<String> = []
        var hiddenAt: [String: Date] = [:]
        var maxPins: Int = FavoritePinLogic.maxPins
    }

    static func isHidden(
        deviceID: String,
        lastMessageDate: Date?,
        hiddenAt: [String: Date]
    ) -> Bool {
        guard let hidden = hiddenAt[deviceID] else { return false }
        guard let lastMessageDate else { return true }
        return lastMessageDate <= hidden
    }

    static func messagesHome(
        currentDeviceID: String,
        currentUserID: String?,
        messages: [Message],
        readReceipts: Set<String> = [],
        starredUserIDs: Set<String>,
        profiles: [UserProfile],
        displayNameLookup: (String) -> String,
        filter: HomeFilter? = nil
    ) -> (pinned: [PinnedPerson], conversations: [ConversationSummary]) {
        let homeFilter = filter ?? HomeFilter(pinnedUserIDs: starredUserIDs)
        let conversations = conversationList(
            currentDeviceID: currentDeviceID,
            messages: messages,
            readReceipts: readReceipts,
            displayNameLookup: displayNameLookup
        )
        let visibleConversations = conversations.filter { conversation in
            let userID = resolvedUserID(
                deviceID: conversation.deviceID,
                partnerUserID: conversation.partnerUserID,
                profiles: profiles
            )
            if let userID, homeFilter.blockedUserIDs.contains(userID) { return false }
            if isHidden(
                deviceID: conversation.deviceID,
                lastMessageDate: conversation.lastMessage?.timestamp,
                hiddenAt: homeFilter.hiddenAt
            ) {
                return false
            }
            if let visible = homeFilter.visibleUserIDs {
                guard let userID else { return false }
                return visible.contains(userID)
            }
            return true
        }
        let pinned = pinnedPeople(
            pinnedUserIDs: homeFilter.pinnedUserIDs,
            currentUserID: currentUserID,
            profiles: profiles,
            conversations: visibleConversations,
            displayNameLookup: displayNameLookup,
            visibleUserIDs: homeFilter.visibleUserIDs,
            blockedUserIDs: homeFilter.blockedUserIDs,
            maxPins: homeFilter.maxPins
        )
        let pinnedIDs = Set(pinned.map(\.deviceID))
        return (pinned, visibleConversations.filter { !pinnedIDs.contains($0.deviceID) })
    }

    static func pinnedPeople(
        pinnedUserIDs: Set<String>,
        currentUserID: String?,
        profiles: [UserProfile],
        conversations: [ConversationSummary],
        displayNameLookup: (String) -> String,
        visibleUserIDs: Set<String>? = nil,
        blockedUserIDs: Set<String> = [],
        maxPins: Int = FavoritePinLogic.maxPins
    ) -> [PinnedPerson] {
        guard pinnedUserIDs.isEmpty == false else { return [] }
        let starredUserIDs = pinnedUserIDs

        var recency: [String: Date] = [:]
        var pinned: [String: PinnedPerson] = [:]

        for profile in profiles {
            guard starredUserIDs.contains(profile.userID),
                  profile.userID != currentUserID else { continue }
            if pinned[profile.userID] == nil {
                pinned[profile.userID] = PinnedPerson(
                    deviceID: profile.deviceID,
                    userID: profile.userID,
                    displayName: ProfileDisplayNameLogic.personName(from: profile.deviceName)
                        ?? displayNameLookup(profile.deviceID),
                    unreadCount: 0
                )
            }
        }

        for conversation in conversations {
            guard let userID = resolvedUserID(
                deviceID: conversation.deviceID,
                partnerUserID: conversation.partnerUserID,
                profiles: profiles
            ),
                  starredUserIDs.contains(userID),
                  userID != currentUserID else { continue }
            pinned[userID] = PinnedPerson(
                deviceID: conversation.deviceID,
                userID: userID,
                displayName: conversation.displayName,
                unreadCount: conversation.unreadCount
            )
            recency[userID] = conversation.lastMessage?.timestamp
        }

        let ranked = pinned.values.filter { person in
            if blockedUserIDs.contains(person.userID) { return false }
            if let visibleUserIDs { return visibleUserIDs.contains(person.userID) }
            return true
        }
        .sorted { lhs, rhs in
            let leftDate = recency[lhs.userID] ?? .distantPast
            let rightDate = recency[rhs.userID] ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return Array(ranked.prefix(max(0, maxPins)))
    }

    private static func resolvedUserID(
        deviceID: String,
        partnerUserID: String?,
        profiles: [UserProfile]
    ) -> String? {
        partnerUserID ?? profiles.first(where: { $0.deviceID == deviceID })?.userID
    }

    private static func partnerUserID(partnerID: String, lastMessage: Message?) -> String? {
        guard let lastMessage else { return nil }
        if lastMessage.senderDeviceID == partnerID { return lastMessage.senderUserID }
        if lastMessage.recipientDeviceID == partnerID { return lastMessage.recipientUserID }
        return nil
    }

    private static func photoPreviewNoun(_ message: Message) -> String {
        if isPhoto(message) { return "a photo" }
        let raw = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPlaceholderText(raw) {
            return "a message"
        }
        let clipped = raw.count > 28 ? String(raw.prefix(27)) + "…" : raw
        return "“\(clipped)”"
    }

    private static func isPlaceholderText(_ raw: String) -> Bool {
        raw.isEmpty
            || raw == MessageBannerLogic.encryptedTextPlaceholder
            || raw == MessageBannerLogic.encryptedImagePlaceholder
            || raw == MessageDecryptabilityLogic.failedTextPlaceholder
    }
}

enum FavoritePinLogic {
    static let maxPins = 3

    static func toggling(_ userID: String, in current: Set<String>, maxPins: Int = maxPins) -> Set<String>? {
        var next = current
        if next.contains(userID) {
            next.remove(userID)
            return next
        }
        guard next.count < maxPins else { return nil }
        next.insert(userID)
        return next
    }

    static func toggling(_ userID: String, in current: [String], maxPins: Int = maxPins) -> [String]? {
        if let index = current.firstIndex(of: userID) {
            var next = current
            next.remove(at: index)
            return next
        }
        guard current.count < maxPins else { return nil }
        return current + [userID]
    }

    static let pinLimitMessage = "You can pin up to \(maxPins) people here."
}
