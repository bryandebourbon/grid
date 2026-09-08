import Foundation

struct GridNode: Identifiable, Codable {
    var x: Int
    var y: Int
    var userProfile: UserProfile?

    /// Occupied cells use the person's `deviceID`. Empty cells use their slot.
    var id: String {
        PersonIdentity.cellID(profile: userProfile, x: x, y: y)
    }
}
