import Foundation

/// CloudKit query-subscription fields that are already in the *production* schema.
/// Adding another `desiredKeys` entry creates `notif_additional_field_N` and
/// CloudKit rejects the save, which breaks push delivery.
enum MessageSubscriptionLogic {
    static let desiredKeys = ["senderDeviceID"]
    static let productionDesiredKeyLimit = 1
}
