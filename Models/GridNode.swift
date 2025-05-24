import Foundation

struct GridNode: Identifiable, Codable {
    let id: UUID
    var x: Int
    var y: Int
    var userProfile: UserProfile? // Can be nil if the node is empty
    // Placeholder for GridNode properties
} 