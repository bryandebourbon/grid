import Foundation
import AppTrackingTransparency
import AdSupport

@MainActor
class PrivacyService: ObservableObject {
    @Published var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    @Published var hasRequestedTracking = false
    
    init() {
        updateTrackingStatus()
    }
    
    private func updateTrackingStatus() {
        trackingAuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus
        print("Current tracking authorization status: \(trackingAuthorizationStatus.rawValue)")
    }
    
    // Request tracking permission
    func requestTrackingPermission() async {
        guard trackingAuthorizationStatus == .notDetermined else {
            print("Tracking permission already determined: \(trackingAuthorizationStatus)")
            return
        }
        
        hasRequestedTracking = true
        
        do {
            let status = await ATTrackingManager.requestTrackingAuthorization()
            trackingAuthorizationStatus = status
            
            switch status {
            case .authorized:
                print("User authorized app tracking")
                // You can now access IDFA and perform cross-app tracking
                let idfa = ASIdentifierManager.shared().advertisingIdentifier
                print("IDFA: \(idfa)")
            case .denied:
                print("User denied app tracking")
            case .restricted:
                print("App tracking is restricted")
            case .notDetermined:
                print("App tracking authorization not determined")
            @unknown default:
                print("Unknown tracking authorization status")
            }
        }
    }
    
    // Check if we can track user
    func canTrackUser() -> Bool {
        return trackingAuthorizationStatus == .authorized
    }
    
    // Get current IDFA (only if authorized)
    func getIDFA() -> String? {
        guard canTrackUser() else { return nil }
        let idfa = ASIdentifierManager.shared().advertisingIdentifier
        return idfa.uuidString
    }
    
    // Privacy-compliant analytics helper
    func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        guard canTrackUser() else {
            print("Cannot track event '\(eventName)' - user has not authorized tracking")
            return
        }
        
        // Here you would integrate with your analytics service
        // For example: Firebase, Amplitude, etc.
        print("Tracking event: \(eventName) with parameters: \(parameters ?? [:])")
    }
} 