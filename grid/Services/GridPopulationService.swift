import Foundation
import CoreLocation

/// Builds the list of profiles to render and applies grid display filters.
struct GridDisplayState {
    var showingStarredOnly: Bool
    var starredUserIDs: Set<String>
    var blockedUserIDs: Set<String>
    var usersWhoBlockedMe: Set<String>
    var selectedInterestFilter: Set<Interest>
    var isDemoMode: Bool
}

@MainActor
final class GridPopulationService {

    func profilesToDisplay(
        nearby: [UserProfile],
        currentUser: UserProfile?,
        demoService: DemoService,
        locationService: LocationService
    ) -> [UserProfile] {
        guard demoService.isDemoMode else { return nearby }
        if let location = locationService.currentLocation {
            return demoService.generateDemoUsers(near: location, count: 24)
        }
        let defaultLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        return demoService.generateDemoUsers(near: defaultLocation, count: 24)
    }

    func layoutProfiles(
        into grid: inout [[GridNode]],
        profiles: [UserProfile],
        currentUser: UserProfile?,
        display: GridDisplayState,
        demoService: DemoService
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
            showingStarredOnly: display.showingStarredOnly,
            starredUserIDs: display.starredUserIDs,
            blockedUserIDs: display.blockedUserIDs,
            usersWhoBlockedMe: display.usersWhoBlockedMe,
            selectedInterestFilter: display.selectedInterestFilter,
            isDemoMode: display.isDemoMode
        )

        if let current = currentUser {
            let toPlace = demoService.isDemoMode
                ? (demoService.createDemoCurrentUser(from: current) ?? current)
                : current
            GridPlacementLogic.place(profile: toPlace, in: &grid, at: 0, col: 0)
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
