import Foundation

struct MessageReaction: Codable, Equatable, Hashable {
    var emoji: String
    var reactorDeviceID: String
}

enum MessageReactionLogic {
    static let quickEmojis = ["❤️", "😂", "😮", "😢", "👍", "👎"]

    static func toggle(
        emoji: String,
        reactorDeviceID: String,
        on message: Message,
        now: Date = Date()
    ) -> Message {
        var next = message
        next.reactions = toggle(
            emoji: emoji,
            reactorDeviceID: reactorDeviceID,
            in: message.reactions
        )
        next.reactionsUpdatedAt = now
        return next
    }

    static func toggle(
        emoji: String,
        reactorDeviceID: String,
        in reactions: [MessageReaction]
    ) -> [MessageReaction] {
        let reactor = PersonIdentity.id(forDeviceID: reactorDeviceID)
        guard !reactor.isEmpty, quickEmojis.contains(emoji) else { return reactions }

        if reactions.contains(where: { $0.reactorDeviceID == reactor && $0.emoji == emoji }) {
            return reactions.filter { !($0.reactorDeviceID == reactor && $0.emoji == emoji) }
        }

        var next = reactions.filter { $0.reactorDeviceID != reactor }
        next.append(MessageReaction(emoji: emoji, reactorDeviceID: reactor))
        return next
    }

    static func grouped(
        _ reactions: [MessageReaction],
        currentDeviceID: String
    ) -> [(emoji: String, count: Int, includesMe: Bool)] {
        let me = PersonIdentity.id(forDeviceID: currentDeviceID)
        return quickEmojis.compactMap { emoji in
            let matches = reactions.filter { $0.emoji == emoji }
            guard !matches.isEmpty else { return nil }
            return (emoji, matches.count, matches.contains { $0.reactorDeviceID == me })
        }
    }

    static func pick(local: Message, incoming: Message) -> [MessageReaction] {
        let localTime = local.reactionsUpdatedAt ?? .distantPast
        let incomingTime = incoming.reactionsUpdatedAt ?? .distantPast
        if localTime == incomingTime {
            return incoming.reactionsUpdatedAt != nil ? incoming.reactions : local.reactions
        }
        return localTime > incomingTime ? local.reactions : incoming.reactions
    }

    static func pickUpdatedAt(local: Message, incoming: Message) -> Date? {
        let times = [local.reactionsUpdatedAt, incoming.reactionsUpdatedAt].compactMap { $0 }
        return times.max()
    }

    static func encode(_ reactions: [MessageReaction]) -> String? {
        guard !reactions.isEmpty,
              let data = try? JSONEncoder().encode(reactions) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ raw: String?) -> [MessageReaction] {
        guard let raw, let data = raw.data(using: .utf8),
              let reactions = try? JSONDecoder().decode([MessageReaction].self, from: data) else {
            return []
        }
        return reactions.filter { quickEmojis.contains($0.emoji) && !$0.reactorDeviceID.isEmpty }
    }
}
