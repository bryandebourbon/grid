import Foundation

struct PeopleGroup: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var memberUserIDs: Set<String>

    init(id: UUID = UUID(), name: String, memberUserIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.memberUserIDs = memberUserIDs
    }
}

enum GridPeopleTab: Hashable {
    case all
    case favorites
    case custom(UUID)
    case interest(String)

    var rawValue: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .custom(let id): return id.uuidString
        case .interest(let raw): return "interest.\(raw)"
        }
    }

    func title(in groups: [PeopleGroup]) -> String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .custom(let id): return groups.first(where: { $0.id == id })?.name ?? "Group"
        case .interest(let raw):
            let interest = Interest(rawValue: raw)
            return "\(interest.emoji) \(interest.rawValue)"
        }
    }
}

enum PeopleGroupStore {
    static func defaultsKey(userID: String) -> String {
        "grid.peopleGroups.\(userID)"
    }

    static func load(userID: String, defaults: UserDefaults = .standard) -> [PeopleGroup] {
        guard let data = defaults.data(forKey: defaultsKey(userID: userID)),
              let groups = try? JSONDecoder().decode([PeopleGroup].self, from: data) else {
            return []
        }
        return groups
    }

    static func save(_ groups: [PeopleGroup], userID: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(groups) {
            defaults.set(data, forKey: defaultsKey(userID: userID))
        }
    }
}

enum InterestPageStore {
    static let maxPages = 3

    static func defaultsKey(userID: String) -> String {
        "grid.interestPages.\(userID)"
    }

    static func load(userID: String, defaults: UserDefaults = .standard) -> [Interest] {
        guard let data = defaults.data(forKey: defaultsKey(userID: userID)),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Array(names.prefix(maxPages)).map { Interest(rawValue: $0) }
    }

    static func save(_ pages: [Interest], userID: String, defaults: UserDefaults = .standard) {
        let names = Array(pages.prefix(maxPages).map(\.rawValue))
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: defaultsKey(userID: userID))
        }
    }

    static func canAdd(to pages: [Interest]) -> Bool {
        pages.count < maxPages
    }

    static func inserting(_ interest: Interest, into pages: [Interest]) -> [Interest] {
        if contains(interest, in: pages) { return pages }
        guard canAdd(to: pages) else { return pages }
        return pages + [interest]
    }

    static func removing(_ interest: Interest, from pages: [Interest]) -> [Interest] {
        pages.filter {
            $0.rawValue.compare(interest.rawValue, options: .caseInsensitive) != .orderedSame
        }
    }

    static func contains(_ interest: Interest, in pages: [Interest]) -> Bool {
        pages.contains {
            $0.rawValue.compare(interest.rawValue, options: .caseInsensitive) == .orderedSame
        }
    }
}

enum GridPeopleTabPaging {
    static func orderedTabs(
        customGroups: [PeopleGroup],
        interestPages: [Interest] = []
    ) -> [GridPeopleTab] {
        [.all, .favorites]
            + customGroups.map { .custom($0.id) }
            + interestPages.map { .interest($0.rawValue) }
    }

    static func tabAfterSwipe(
        translation: CGFloat,
        current: GridPeopleTab,
        tabs: [GridPeopleTab]
    ) -> GridPeopleTab {
        guard let index = tabs.firstIndex(of: current) else { return current }
        if translation < -40, index + 1 < tabs.count { return tabs[index + 1] }
        if translation > 40, index > 0 { return tabs[index - 1] }
        return current
    }

    /// Swiping toward the next page while already on the last tab opens interest search,
    /// unless the user already has the maximum number of interest pages.
    static func shouldOpenInterestSearch(
        translation: CGFloat,
        current: GridPeopleTab,
        tabs: [GridPeopleTab],
        canAddInterestPage: Bool = true
    ) -> Bool {
        guard canAddInterestPage else { return false }
        guard let index = tabs.firstIndex(of: current), !tabs.isEmpty else { return false }
        return translation < -40 && index == tabs.count - 1
    }

    static func pageOffset(tab: GridPeopleTab, width: CGFloat, drag: CGFloat) -> CGFloat {
        let index = tab == .all ? 0 : 1
        return -CGFloat(index) * width + drag
    }

    static func clampedDrag(translation: CGFloat, tab: GridPeopleTab, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        switch tab {
        case .all:
            if translation > 0 { return translation * 0.25 }
            return max(-width, translation)
        case .favorites, .custom, .interest:
            if translation < 0 { return translation * 0.25 }
            return min(width, translation)
        }
    }

    static func tabAfterSwipe(
        translation: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        current: GridPeopleTab
    ) -> GridPeopleTab {
        guard width > 0 else { return current }
        let projected = translation + velocity * 0.2
        let threshold = width * 0.2
        switch current {
        case .all:
            return projected < -threshold ? .favorites : .all
        case .favorites, .custom, .interest:
            return projected > threshold ? .all : current
        }
    }
}
