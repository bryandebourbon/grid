import SwiftUI
import CloudKit

struct CreateProfileView: View {
    @State private var username: String = ""
    @Binding var showCreateProfileView: Bool // To dismiss the view
    // You'll need to pass the Apple User ID to associate with the profile
    let appleUserID: String 

    // Environment object for CloudKit operations (you'll set this up later)
    // @EnvironmentObject var cloudKitManager: CloudKitManager 

    var body: some View {
        VStack {
            Text("Create Your Profile")
                .font(.largeTitle)
                .padding()

            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Button("Save Profile") {
                saveProfile()
            }
            .padding()
            .buttonStyle(.borderedProminent)
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }

    private func saveProfile() {
        let newProfile = UserProfile(userID: appleUserID, username: username)
        let profileRecord = newProfile.toCKRecord()

        // Get the private database
        let privateDB = CKContainer.default().privateCloudDatabase

        // Save the record
        privateDB.save(profileRecord) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    // Handle error (e.g., show an alert to the user)
                    print("Error saving profile to CloudKit: \(error.localizedDescription)")
                    // You might want to show an alert here
                } else if record != nil {
                    print("Profile saved successfully!")
                    // Potentially fetch the full profile or use the saved record details
                    // For now, just dismiss the view
                    self.showCreateProfileView = false 
                } else {
                    print("Unknown error saving profile.")
                }
            }
        }
    }
}

struct CreateProfileView_Previews: PreviewProvider {
    static var previews: some View {
        CreateProfileView(showCreateProfileView: .constant(true), appleUserID: "previewUserID")
    }
} 