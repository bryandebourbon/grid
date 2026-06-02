import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    Text("Last updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Introduction
                        Section {
                            Text("Introduction")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Grid respects your privacy and is committed to protecting your personal data. This privacy policy explains how we collect, use, and safeguard your information when you use our location-based social networking app.")
                                .font(.body)
                        }
                        
                        Divider()
                        
                        // Information We Collect
                        Section {
                            Text("Information We Collect")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Group {
                                    Text("**Account Information:**")
                                        .font(.headline)
                                    Text("• Apple ID (for Sign in with Apple authentication)\n• Device identifier\n• Profile name and bio\n• Profile photos")
                                        .font(.body)
                                }
                                
                                Group {
                                    Text("**Location Data:**")
                                        .font(.headline)
                                    Text("• Current precise location coordinates while the app is open and permission is granted\n• Current device location for nearby-user discovery\n• No background location tracking or location-history archive")
                                        .font(.body)
                                }
                                
                                Group {
                                    Text("**Usage Data:**")
                                        .font(.headline)
                                    Text("• Messages sent and received\n• User interactions (stars, blocks, reports)\n• Device information needed for account and CloudKit operation\n• No IDFA collection or cross-app tracking")
                                        .font(.body)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // How We Use Your Information
                        Section {
                            Text("How We Use Your Information")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Core Functionality:** To provide location-based user discovery and messaging")
                                Text("• **Safety:** To moderate content and ensure community safety")
                                Text("• **Improvement:** To diagnose issues and improve app reliability")
                                Text("• **Communication:** To send notifications about app activity")
                                Text("• **Legal Compliance:** To comply with applicable laws and regulations")
                            }
                            .font(.body)
                        }
                        
                        Divider()
                        
                        // Data Sharing
                        Section {
                            Text("Data Sharing")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("**We Do NOT sell your personal data.**")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                
                                Text("Limited data sharing occurs only for:")
                                    .font(.body)
                                
                                Text("• **Other Users:** Profile information visible to nearby users")
                                Text("• **Safety:** Content moderation and abuse prevention")
                                Text("• **Legal Requirements:** When required by law enforcement")
                                Text("• **Service Providers:** CloudKit (Apple) for data storage")
                            }
                            .font(.body)
                        }
                        
                        Divider()
                        
                        // App Tracking Transparency
                        Section {
                            Text("App Tracking Transparency")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Grid does not track your activity across other companies' apps or websites, does not collect the IDFA, and does not request App Tracking Transparency permission.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Data Security
                        Section {
                            Text("Data Security")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Encryption:** Message content and images are encrypted end-to-end by default")
                                Text("• **Apple CloudKit:** Secure cloud storage with Apple's infrastructure")
                                Text("• **Metadata:** Message sender/recipient identifiers and timestamps are currently stored in CloudKit public records while shared-zone metadata protection is being built")
                                Text("• **Regular Updates:** Security patches and improvements")
                            }
                            .font(.body)
                        }
                        
                        Divider()
                        
                        // Your Rights
                        Section {
                            Text("Your Privacy Rights")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Access:** Request a copy of your data")
                                Text("• **Correction:** Update incorrect information")
                                Text("• **Deletion:** Delete your account and data")
                                Text("• **Portability:** Export your data")
                                Text("• **Opt-out:** Disable location sharing in iOS Settings")
                            }
                            .font(.body)
                        }
                        
                        Divider()
                        
                        // Data Retention
                        Section {
                            Text("Data Retention")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Account Data:** Retained while account is active")
                                Text("• **Messages:** Stored until deleted by user")
                                Text("• **Location Data:** Current location is updated for proximity matching while the app is open")
                                Text("• **Diagnostics:** Local debug logs are disabled in release builds")
                                Text("• **Safety Data:** Reports and moderation data retained for safety")
                            }
                            .font(.body)
                        }
                        
                        Divider()
                        
                        // Children's Privacy
                        Section {
                            Text("Children's Privacy")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Grid is not intended for users under 17 years old. We do not knowingly collect personal information from children under 17.")
                                .font(.body)
                        }
                        
                        Divider()
                        
                        // Location Services
                        Section {
                            Text("Location Services")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Location access is **required** for core functionality:")
                                    .font(.body)
                                
                                Text("• **User Discovery:** Finding nearby users")
                                Text("• **Distance Display:** Showing proximity to other users")
                                Text("• **Grid Positioning:** Organizing users by location")
                                
                                Text("You can disable location services in iOS Settings, but this will limit app functionality.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        
                        Divider()
                        
                        // Contact Information
                        Section {
                            Text("Contact Us")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("For privacy questions or to exercise your rights:")
                                    .font(.body)
                                
                                Link("Email: bdebourbon@me.com", destination: URL(string: "mailto:bdebourbon@me.com")!)
                                    .font(.body)
                                    .foregroundColor(.blue)
                                
                                Text("We will respond to privacy requests within 30 days.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Changes to Policy
                        Section {
                            Text("Changes to This Policy")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("We may update this privacy policy periodically. Changes will be posted in the app and take effect immediately. Continued use of the app indicates acceptance of updated terms.")
                                .font(.body)
                        }
                        
                        // Legal Notice
                        Section {
                            Text("This privacy policy complies with applicable privacy laws including GDPR, CCPA, and App Store Review Guidelines.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
} 