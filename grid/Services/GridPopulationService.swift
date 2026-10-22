import Foundation
import CoreLocation

/// Builds the list of profiles to render and applies grid display filters.
struct GridDisplayState {
    var blockedUserIDs: Set<String>
    var usersWhoBlockedMe: Set<String>
    var selectedInterestFilter: Set<Interest>
    var starredUserIDs: Set<String> = []
    var favoritesOnly: Bool = false
    var showsLocalLLM: Bool = false
    var showsSelfOnGrid: Bool = false
    var showsNearbyPeople: Bool = true
}

@MainActor
final class GridPopulationService {

    func profilesToDisplay(
        nearby: [UserProfile],
        currentUser: UserProfile? = nil,
        includeHidden: Bool = false
    ) -> [UserProfile] {
        nearby.filter { profile in
            if let currentUser, profile.deviceID == currentUser.deviceID {
                return true
            }
            return GridMasterViewerLogic.shouldShowPeer(profile, includeHidden: includeHidden)
        }
    }

    func layoutProfiles(
        into grid: inout [[GridNode]],
        profiles: [UserProfile],
        currentUser: UserProfile?,
        display: GridDisplayState
    ) {
        guard let currentDeviceID = currentUser?.deviceID else {
            let peers = profiles.filter { !LocalLLMIdentity.isLLM($0.deviceID) }
            let extra = display.showsLocalLLM ? 1 : 0
            grid = GridPlacementLogic.makeEmptyGrid(
                size: GridPlacementLogic.size(fitting: peers.count + extra)
            )
            if display.showsLocalLLM {
                placeLocalLLM(into: &grid, currentUserPresent: false)
            }
            for profile in peers {
                placeRemaining(profile, into: &grid)
            }
            return
        }

        let partitioned = GridProfileFilterLogic.partition(
            profiles: profiles,
            currentUserDeviceID: currentDeviceID
        )
        let others = GridProfileFilterLogic.applyDisplayFilters(
            to: partitioned.others,
            blockedUserIDs: display.blockedUserIDs,
            usersWhoBlockedMe: display.usersWhoBlockedMe,
            selectedInterestFilter: display.selectedInterestFilter,
            starredUserIDs: display.starredUserIDs,
            favoritesOnly: display.favoritesOnly
        )
        let peers = others.filter { !LocalLLMIdentity.isLLM($0.deviceID) }
        var count = peers.count
        if display.showsSelfOnGrid { count += 1 }
        if display.showsLocalLLM && !display.favoritesOnly { count += 1 }
        grid = GridPlacementLogic.makeEmptyGrid(size: GridPlacementLogic.size(fitting: count))

        if display.showsSelfOnGrid, let current = currentUser {
            GridPlacementLogic.place(profile: current, in: &grid, at: 0, col: 0)
        }

        guard display.showsNearbyPeople else { return }

        if display.showsLocalLLM && !display.favoritesOnly {
            placeLocalLLM(into: &grid, currentUserPresent: display.showsSelfOnGrid)
        }

        let skip: (x: Int, y: Int)? = display.showsSelfOnGrid ? (0, 0) : nil
        for profile in peers {
            placeRemaining(profile, into: &grid, skip: skip)
        }
    }

    private func placeLocalLLM(into grid: inout [[GridNode]], currentUserPresent: Bool) {
        guard grid.isEmpty == false else { return }
        let row = 0
        let col = currentUserPresent && grid[row].count > 1 ? 1 : 0
        guard col < grid[row].count, grid[row][col].userProfile == nil else {
            placeRemaining(LocalLLMIdentity.profile, into: &grid, skip: currentUserPresent ? (0, 0) : nil)
            return
        }
        GridPlacementLogic.place(profile: LocalLLMIdentity.profile, in: &grid, at: row, col: col)
    }

    private func placeRemaining(
        _ profile: UserProfile,
        into grid: inout [[GridNode]],
        skip: (x: Int, y: Int)? = nil
    ) {
        if let slot = GridPlacementLogic.firstEmptySlot(in: grid, skipping: skip) {
            GridPlacementLogic.place(profile: profile, in: &grid, at: slot.row, col: slot.col)
        }
    }
}
