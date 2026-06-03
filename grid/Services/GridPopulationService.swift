import Foundation
import CoreLocation

/// Builds the list of profiles to render and applies grid display filters.
struct GridDisplayState {
    var blockedUserIDs: Set<String>
    var usersWhoBlockedMe: Set<String>
    var selectedInterestFilter: Set<Interest>
}

@MainActor
final class GridPopulationService {

    func profilesToDisplay(nearby: [UserProfile]) -> [UserProfile] {
        nearby
    }

    func layoutProfiles(
        into grid: inout [[GridNode]],
        profiles: [UserProfile],
        currentUser: UserProfile?,
        display: GridDisplayState
    ) {
        grid = GridPlacementLogic.makeEmptyGrid()
        guard let currentDeviceID = currentUser?.deviceID else {
            for profile in profiles { placeRemaining(profile, into: &grid) }
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
            selectedInterestFilter: display.selectedInterestFilter
        )

        if let current = currentUser {
            GridPlacementLogic.place(profile: current, in: &grid, at: 0, col: 0)
        }

        for profile in others {
            placeRemaining(profile, into: &grid, skip: (0, 0))
        }
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
