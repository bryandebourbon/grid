import Foundation

enum AgeGateLogic {
    static let minimumAge = 17
    static let confirmationDefaultsKey = "confirmedAge17Plus"

    static func canProceedToSignIn(confirmedMinimumAge: Bool) -> Bool {
        confirmedMinimumAge
    }
}
