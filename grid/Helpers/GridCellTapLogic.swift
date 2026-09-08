import Foundation

/// The only mapping from a grid cell to a chat partner.
/// Tests lock this so a tap cannot open someone else's thread.
enum GridCellTapLogic {
    static func chatPartnerDeviceID(for node: GridNode) -> String? {
        guard let deviceID = node.userProfile?.deviceID,
              deviceID.isEmpty == false else { return nil }
        return PersonIdentity.id(forDeviceID: deviceID)
    }
}
