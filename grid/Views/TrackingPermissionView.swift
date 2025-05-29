import SwiftUI
import AppTrackingTransparency

struct TrackingPermissionView: View {
    @ObservedObject var privacyService: PrivacyService
    @Environment(\.dismiss) var dismiss
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon - different based on status
            Image(systemName: iconForStatus)
                .font(.system(size: 60))
                .foregroundColor(colorForStatus)
            
            VStack(spacing: 16) {
                Text(titleForStatus)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(descriptionForStatus)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            if privacyService.trackingAuthorizationStatus == .notDetermined {
                // Show permission request UI
                permissionRequestContent
            } else {
                // Show current status and settings option
                currentStatusContent
            }
            
            // Privacy Policy Link
            Button("View Privacy Policy") {
                showingPrivacyPolicy = true
            }
            .font(.caption)
            .foregroundColor(.blue)
            
            Spacer()
            
            Text(footerText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var permissionRequestContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionReasonRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Improve Performance",
                description: "Understand how you use Grid to make it better"
            )
            
            PermissionReasonRow(
                icon: "person.2.badge.gearshape",
                title: "Enhance Features",
                description: "Develop features that users find most valuable"
            )
            
            PermissionReasonRow(
                icon: "personalhotspot",
                title: "Better Connections",
                description: "Optimize user discovery and matching"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        
        VStack(spacing: 12) {
            Button("Allow Tracking") {
                Task {
                    await privacyService.requestTrackingPermission()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button("Don't Allow") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    @ViewBuilder
    private var currentStatusContent: some View {
        VStack(spacing: 16) {
            // Current status display
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(privacyService.trackingAuthorizationStatus == .authorized ? .green : .orange)
                
                Text("Current Status: \(statusDisplayText)")
                    .font(.headline)
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Explanation of current setting
            Text(statusExplanation)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Button to open iOS Settings
            Button("Change in iOS Settings") {
                openAppSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    // MARK: - Computed Properties
    
    private var iconForStatus: String {
        switch privacyService.trackingAuthorizationStatus {
        case .notDetermined:
            return "shield.lefthalf.filled"
        case .authorized:
            return "checkmark.shield.fill"
        case .denied:
            return "xmark.shield.fill"
        case .restricted:
            return "exclamationmark.shield.fill"
        @unknown default:
            return "questionmark.shield.fill"
        }
    }
    
    private var colorForStatus: Color {
        switch privacyService.trackingAuthorizationStatus {
        case .notDetermined:
            return .blue
        case .authorized:
            return .green
        case .denied:
            return .orange
        case .restricted:
            return .red
        @unknown default:
            return .gray
        }
    }
    
    private var titleForStatus: String {
        switch privacyService.trackingAuthorizationStatus {
        case .notDetermined:
            return "Help Improve Grid"
        case .authorized:
            return "Tracking Enabled"
        case .denied:
            return "Tracking Disabled"
        case .restricted:
            return "Tracking Restricted"
        @unknown default:
            return "Tracking Status"
        }
    }
    
    private var descriptionForStatus: String {
        switch privacyService.trackingAuthorizationStatus {
        case .notDetermined:
            return "We'd like your permission to track your activity across other companies' apps and websites."
        case .authorized:
            return "You've allowed Grid to track your activity for analytics and improvements."
        case .denied:
            return "You've chosen not to allow tracking. Grid will still work great!"
        case .restricted:
            return "Tracking is restricted on this device by system settings or parental controls."
        @unknown default:
            return "The tracking permission status is unknown."
        }
    }
    
    private var statusDisplayText: String {
        switch privacyService.trackingAuthorizationStatus {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Not Allowed"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var statusExplanation: String {
        switch privacyService.trackingAuthorizationStatus {
        case .authorized:
            return "Grid can use analytics to improve your experience and develop better features."
        case .denied:
            return "Grid respects your choice and won't track you across other apps. All core features remain available."
        case .restricted:
            return "Tracking permissions are managed by device restrictions or parental controls."
        case .notDetermined:
            return "You haven't made a decision about tracking yet."
        @unknown default:
            return "The tracking status couldn't be determined."
        }
    }
    
    private var footerText: String {
        switch privacyService.trackingAuthorizationStatus {
        case .notDetermined:
            return "You can change this choice anytime in Settings > Privacy & Security > Tracking"
        default:
            return "To change this setting, go to Settings > Privacy & Security > Tracking > Grid"
        }
    }
    
    // MARK: - Helper Methods
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

struct PermissionReasonRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
} 