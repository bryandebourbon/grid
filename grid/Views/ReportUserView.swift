import SwiftUI

struct ReportUserView: View {
    @ObservedObject var viewModel: GridViewModel
    let userProfile: UserProfile
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedReason: Report.ReportReason = .inappropriateContent
    @State private var additionalDetails: String = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report \(userProfile.displayName)")
                            .font(.headline)
                        Text("Please select a reason for reporting this user")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(Report.ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Additional Details (Optional)") {
                    TextEditor(text: $additionalDetails)
                        .frame(minHeight: 100)
                        .placeholder(when: additionalDetails.isEmpty) {
                            Text("Provide more information about the issue...")
                                .foregroundColor(.secondary)
                        }
                }
                
                Section {
                    Text("Reports are reviewed to keep our community safe. False reports may result in action against your account.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        submitReport()
                    }
                    .disabled(isSubmitting)
                }
            }
            .disabled(isSubmitting)
            .overlay {
                if isSubmitting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Submitting...")
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                                .shadow(radius: 5)
                        }
                }
            }
            .alert("Report Submitted", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for helping keep our community safe. We will review this report.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func submitReport() {
        isSubmitting = true
        
        // Create report
        viewModel.reportUser(
            deviceID: userProfile.deviceID,
            reason: selectedReason,
            description: additionalDetails.isEmpty ? nil : additionalDetails
        )
        
        // Wait a moment for the report to be submitted
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSubmitting = false
            
            // For now, always show success
            // In a real app, you'd check the result from reportUser
            showSuccessAlert = true
        }
    }
}

// Extension for placeholder in TextEditor
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .topLeading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 