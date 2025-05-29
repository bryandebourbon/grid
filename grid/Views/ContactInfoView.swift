import SwiftUI

struct ContactInfoView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Contact Us")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("We're here to help! If you have any concerns about content or user behavior, please reach out to us.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Email Support
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Email Support", systemImage: "envelope.fill")
                            .font(.headline)
                        Link("bdebourbon@me.com", destination: URL(string: "mailto:bdebourbon@me.com")!)
                            .font(.body)
                            .foregroundColor(.blue)
                        Text("For general inquiries and support")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Content Moderation
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Content Moderation", systemImage: "exclamationmark.shield.fill")
                            .font(.headline)
                        Link("bdebourbon@me.com", destination: URL(string: "mailto:bdebourbon@me.com")!)
                            .font(.body)
                            .foregroundColor(.blue)
                        Text("Report inappropriate content or users")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Privacy Concerns
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privacy Concerns", systemImage: "lock.shield.fill")
                            .font(.headline)
                        Link("bdebouron@me.com", destination: URL(string: "mailto:bdebourbon@me.com")!)
                            .font(.body)
                            .foregroundColor(.blue)
                        Text("Questions about data and privacy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                Text("Response Time")
                    .font(.headline)
                    .padding(.top)
                
                Text("We aim to respond to all inquiries within 24-48 hours. For urgent safety concerns, please include 'URGENT' in your subject line.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
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