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

    static func messagesHome(
        currentDeviceID: String,
        currentUserID: String?,
        messages: [Message],
        readReceipts: Set<String> = [],
        starredUserIDs: Set<String>,
        profiles: [UserProfile],
        displayNameLookup: (String) -> String
    ) -> (pinned: [PinnedPerson], conversations: [ConversationSummary]) {
        let conversations = conversationList(
            currentDeviceID: currentDeviceID,
            messages: messages,
            readReceipts: readReceipts,
            displayNameLookup: displayNameLookup
        )
        let pinned = pinnedPeople(
            starredUserIDs: starredUserIDs,
            currentUserID: currentUserID,
            profiles: profiles,
            conversations: conversations,
            displayNameLookup: displayNameLookup
        )
        let pinnedIDs = Set(pinned.map(\.deviceID))
        return (pinned, conversations.filter { !pinnedIDs.contains($0.deviceID) })
    }

    static func pinnedPeople(
        starredUserIDs: Set<String>,
        currentUserID: String?,
        profiles: [UserProfile],
        conversations: [ConversationSummary],
        displayNameLookup: (String) -> String
    ) -> [PinnedPerson] {
        guard starredUserIDs.isEmpty == false else { return [] }

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
            guard let userID = conversation.partnerUserID,
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

        return pinned.values.sorted { lhs, rhs in
            let leftDate = recency[lhs.userID] ?? .distantPast
            let rightDate = recency[rhs.userID] ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
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
            || raw == "[Failed to decrypt message]"
    }
}
