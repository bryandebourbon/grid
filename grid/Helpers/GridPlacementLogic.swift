import Foundation

/// Pure 5×5 grid placement helpers.
enum GridPlacementLogic {
    static let defaultSize = 5

    static func makeEmptyGrid(size: Int = defaultSize) -> [[GridNode]] {
        (0..<size).map { row in
            (0..<size).map { col in
                GridNode(id: UUID(), x: row, y: col, userProfile: nil)
            }
        }
    }

    static func firstEmptySlot(
        in grid: [[GridNode]],
        skipping skip: (x: Int, y: Int)? = nil
    ) -> (row: Int, col: Int)? {
        for row in 0..<grid.count {
            for col in 0..<grid[row].count {
                if let skip, skip.x == row, skip.y == col { continue }
                if grid[row][col].userProfile == nil { return (row, col) }
            }
        }
        return nil
    }

    static func place(
        profile: UserProfile,
        in grid: inout [[GridNode]],
        at row: Int,
        col: Int
    ) {
        guard row >= 0, row < grid.count, col >= 0, col < grid[row].count else { return }
        grid[row][col].userProfile = profile
    }

    static func removeProfile(deviceID: String, from grid: inout [[GridNode]]) {
        for row in 0..<grid.count {
            for col in 0..<grid[row].count where grid[row][col].userProfile?.deviceID == deviceID {
                grid[row][col].userProfile = nil
            }
        }
    }
}
