import Foundation

// MARK: - Interest Categories
enum Interest: String, CaseIterable, Codable, Identifiable {
    // Tech & Gaming
    case technology = "Technology"
    case gaming = "Gaming"
    case programming = "Programming"
    case startups = "Startups"
    
    // Fitness & Health
    case fitness = "Fitness"
    case yoga = "Yoga"
    case running = "Running"
    case cycling = "Cycling"
    case hiking = "Hiking"
    case swimming = "Swimming"
    
    // Arts & Creativity
    case art = "Art"
    case photography = "Photography"
    case music = "Music"
    case writing = "Writing"
    case design = "Design"
    case dancing = "Dancing"
    
    // Food & Lifestyle
    case cooking = "Cooking"
    case coffee = "Coffee"
    case wine = "Wine"
    case foodie = "Foodie"
    case travel = "Travel"
    case fashion = "Fashion"
    
    // Learning & Professional
    case education = "Education"
    case business = "Business"
    case investing = "Investing"
    case networking = "Professional Networking"
    case languages = "Languages"
    case books = "Books"
    
    // Entertainment & Social
    case movies = "Movies"
    case sports = "Sports"
    case concerts = "Concerts"
    case nightlife = "Nightlife"
    case comedy = "Comedy"
    case theater = "Theater"
    
    // Lifestyle & Wellness
    case meditation = "Meditation"
    case spirituality = "Spirituality"
    case volunteering = "Volunteering"
    case pets = "Pets"
    case gardening = "Gardening"
    case outdoors = "Outdoors"
    
    var id: String { rawValue }
    
    var emoji: String {
        switch self {
        case .technology: return "💻"
        case .gaming: return "🎮"
        case .programming: return "⌨️"
        case .startups: return "🚀"
        case .fitness: return "💪"
        case .yoga: return "🧘"
        case .running: return "🏃"
        case .cycling: return "🚴"
        case .hiking: return "🥾"
        case .swimming: return "🏊"
        case .art: return "🎨"
        case .photography: return "📸"
        case .music: return "🎵"
        case .writing: return "✍️"
        case .design: return "🎭"
        case .dancing: return "💃"
        case .cooking: return "👨‍🍳"
        case .coffee: return "☕"
        case .wine: return "🍷"
        case .foodie: return "🍽️"
        case .travel: return "✈️"
        case .fashion: return "👗"
        case .education: return "📚"
        case .business: return "💼"
        case .investing: return "📈"
        case .networking: return "🤝"
        case .languages: return "🗣️"
        case .books: return "📖"
        case .movies: return "🎬"
        case .sports: return "⚽"
        case .concerts: return "🎤"
        case .nightlife: return "🌃"
        case .comedy: return "😂"
        case .theater: return "🎭"
        case .meditation: return "🕯️"
        case .spirituality: return "🙏"
        case .volunteering: return "❤️"
        case .pets: return "🐕"
        case .gardening: return "🌱"
        case .outdoors: return "🌲"
        }
    }
    
    var displayName: String {
        return "\(emoji) \(rawValue)"
    }
    
    // Group interests by category for UI organization
    static var categories: [InterestCategory] {
        return [
            InterestCategory(name: "Tech & Innovation", interests: [.technology, .gaming, .programming, .startups]),
            InterestCategory(name: "Fitness & Health", interests: [.fitness, .yoga, .running, .cycling, .hiking, .swimming]),
            InterestCategory(name: "Arts & Creativity", interests: [.art, .photography, .music, .writing, .design, .dancing]),
            InterestCategory(name: "Food & Lifestyle", interests: [.cooking, .coffee, .wine, .foodie, .travel, .fashion]),
            InterestCategory(name: "Learning & Professional", interests: [.education, .business, .investing, .networking, .languages, .books]),
            InterestCategory(name: "Entertainment", interests: [.movies, .sports, .concerts, .nightlife, .comedy, .theater]),
            InterestCategory(name: "Wellness & Community", interests: [.meditation, .spirituality, .volunteering, .pets, .gardening, .outdoors])
        ]
    }
}

// MARK: - Interest Category for UI Organization
struct InterestCategory: Identifiable {
    let id = UUID()
    let name: String
    let interests: [Interest]
} 