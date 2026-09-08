import Foundation

struct Interest: RawRepresentable, Hashable, Codable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Tech & Gaming
    static let technology = Interest(rawValue: "Technology")
    static let gaming = Interest(rawValue: "Gaming")
    static let programming = Interest(rawValue: "Programming")
    static let startups = Interest(rawValue: "Startups")

    // Fitness & Health
    static let fitness = Interest(rawValue: "Fitness")
    static let yoga = Interest(rawValue: "Yoga")
    static let running = Interest(rawValue: "Running")
    static let cycling = Interest(rawValue: "Cycling")
    static let hiking = Interest(rawValue: "Hiking")
    static let swimming = Interest(rawValue: "Swimming")

    // Arts & Creativity
    static let art = Interest(rawValue: "Art")
    static let photography = Interest(rawValue: "Photography")
    static let music = Interest(rawValue: "Music")
    static let writing = Interest(rawValue: "Writing")
    static let design = Interest(rawValue: "Design")
    static let dancing = Interest(rawValue: "Dancing")

    // Food & Lifestyle
    static let cooking = Interest(rawValue: "Cooking")
    static let coffee = Interest(rawValue: "Coffee")
    static let wine = Interest(rawValue: "Wine")
    static let foodie = Interest(rawValue: "Foodie")
    static let travel = Interest(rawValue: "Travel")
    static let fashion = Interest(rawValue: "Fashion")

    // Learning & Professional
    static let education = Interest(rawValue: "Education")
    static let business = Interest(rawValue: "Business")
    static let investing = Interest(rawValue: "Investing")
    static let networking = Interest(rawValue: "Professional Networking")
    static let languages = Interest(rawValue: "Languages")
    static let books = Interest(rawValue: "Books")

    // Entertainment & Social
    static let movies = Interest(rawValue: "Movies")
    static let sports = Interest(rawValue: "Sports")
    static let concerts = Interest(rawValue: "Concerts")
    static let nightlife = Interest(rawValue: "Nightlife")
    static let gay = Interest(rawValue: "Gay")
    static let lgbtq = Interest(rawValue: "LGBTQ+")
    static let comedy = Interest(rawValue: "Comedy")
    static let theater = Interest(rawValue: "Theater")

    // Lifestyle & Wellness
    static let meditation = Interest(rawValue: "Meditation")
    static let spirituality = Interest(rawValue: "Spirituality")
    static let volunteering = Interest(rawValue: "Volunteering")
    static let pets = Interest(rawValue: "Pets")
    static let gardening = Interest(rawValue: "Gardening")
    static let outdoors = Interest(rawValue: "Outdoors")

    static let builtInCases: [Interest] = [
        .technology, .gaming, .programming, .startups,
        .fitness, .yoga, .running, .cycling, .hiking, .swimming,
        .art, .photography, .music, .writing, .design, .dancing,
        .cooking, .coffee, .wine, .foodie, .travel, .fashion,
        .education, .business, .investing, .networking, .languages, .books,
        .movies, .sports, .concerts, .nightlife, .gay, .lgbtq, .comedy, .theater,
        .meditation, .spirituality, .volunteering, .pets, .gardening, .outdoors
    ]

    static var customCases: [Interest] {
        CustomInterestStore.load().map { Interest(rawValue: $0.name) }
    }

    static var allCases: [Interest] {
        builtInCases + customCases
    }

    var isCustom: Bool {
        !Self.builtInCases.contains(self)
    }

    var emoji: String {
        Self.builtInEmoji[rawValue]
            ?? CustomInterestStore.emoji(for: rawValue)
            ?? "✨"
    }

    var displayName: String {
        "\(emoji) \(rawValue)"
    }

    static func named(_ raw: String) -> Interest? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let builtIn = builtInCases.first(where: { $0.rawValue.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return builtIn
        }
        if let custom = CustomInterestStore.load().first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return Interest(rawValue: custom.name)
        }
        return Interest(rawValue: trimmed)
    }

    static var categories: [InterestCategory] {
        var list = [
            InterestCategory(name: "Tech & Innovation", interests: [.technology, .gaming, .programming, .startups]),
            InterestCategory(name: "Fitness & Health", interests: [.fitness, .yoga, .running, .cycling, .hiking, .swimming]),
            InterestCategory(name: "Arts & Creativity", interests: [.art, .photography, .music, .writing, .design, .dancing]),
            InterestCategory(name: "Food & Lifestyle", interests: [.cooking, .coffee, .wine, .foodie, .travel, .fashion]),
            InterestCategory(name: "Learning & Professional", interests: [.education, .business, .investing, .networking, .languages, .books]),
            InterestCategory(name: "Entertainment", interests: [.movies, .sports, .concerts, .nightlife, .gay, .lgbtq, .comedy, .theater]),
            InterestCategory(name: "Wellness & Community", interests: [.meditation, .spirituality, .volunteering, .pets, .gardening, .outdoors])
        ]
        let added = customCases
        if !added.isEmpty {
            list.append(InterestCategory(name: "Added", interests: added))
        }
        return list
    }

    private static let builtInEmoji: [String: String] = [
        "Technology": "💻", "Gaming": "🎮", "Programming": "⌨️", "Startups": "🚀",
        "Fitness": "💪", "Yoga": "🧘", "Running": "🏃", "Cycling": "🚴", "Hiking": "🥾", "Swimming": "🏊",
        "Art": "🎨", "Photography": "📸", "Music": "🎵", "Writing": "✍️", "Design": "🎭", "Dancing": "💃",
        "Cooking": "👨‍🍳", "Coffee": "☕", "Wine": "🍷", "Foodie": "🍽️", "Travel": "✈️", "Fashion": "👗",
        "Education": "📚", "Business": "💼", "Investing": "📈", "Professional Networking": "🤝",
        "Languages": "🗣️", "Books": "📖",
        "Movies": "🎬", "Sports": "⚽", "Concerts": "🎤", "Nightlife": "🌃",
        "Gay": "🏳️‍🌈", "LGBTQ+": "🏳️‍🌈", "Comedy": "😂", "Theater": "🎭",
        "Meditation": "🕯️", "Spirituality": "🙏", "Volunteering": "❤️",
        "Pets": "🐕", "Gardening": "🌱", "Outdoors": "🌲"
    ]
}

struct InterestCategory: Identifiable {
    let id = UUID()
    let name: String
    let interests: [Interest]
}

struct CustomInterestRecord: Codable, Equatable {
    var name: String
    var emoji: String
}

enum CustomInterestStore {
    static let defaultsKey = "grid.customInterests"

    static let emojiPalette: [String] = [
        "✨", "🔥", "💜", "🎯", "⭐", "🎲", "🎸", "🏀", "🏐", "🧩",
        "🌸", "🍕", "🧁", "🦄", "🌈", "🧠", "🛠️", "🎬", "📝", "🌍",
        "💎", "🪄", "🫶", "😎"
    ]

    static func load(defaults: UserDefaults = .standard) -> [CustomInterestRecord] {
        guard let data = defaults.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([CustomInterestRecord].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [CustomInterestRecord], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    static func emoji(for name: String, defaults: UserDefaults = .standard) -> String? {
        load(defaults: defaults).first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.emoji
    }

    @discardableResult
    static func add(name: String, emoji: String, defaults: UserDefaults = .standard) -> Interest? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let builtIn = Interest.builtInCases.first(where: {
            $0.rawValue.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return builtIn
        }

        var items = load(defaults: defaults)
        if let existing = items.first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return Interest(rawValue: existing.name)
        }

        items.append(CustomInterestRecord(name: trimmed, emoji: emoji))
        save(items, defaults: defaults)
        return Interest(rawValue: trimmed)
    }

    static func merge(_ incoming: [CustomInterestRecord], defaults: UserDefaults = .standard) {
        let merged = SharedInterestMergeLogic.merging(incoming, into: load(defaults: defaults))
        save(merged, defaults: defaults)
    }
}
