import SwiftUI

struct GridView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var showingEditUsernameSheet = false

    var body: some View {
        NavigationView {
            VStack {
                Text(viewModel.connectedPeersText)
                    .font(.caption)
                    .padding(.top)

                if let profile = viewModel.currentUserProfile {
                    Text("Welcome, \(profile.username)!")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: viewModel.gridSize), spacing: 2) {
                        ForEach(viewModel.gridNodes.flatMap { $0 }) { node in
                            GridNodeView(node: node)
                        }
                    }
                    .padding()
                    .aspectRatio(1, contentMode: .fit)
                    .border(Color.gray)
                } else {
                    Text("Loading profile or no profile set...")
                }
                Spacer()
            }
            .navigationTitle("The Grid")
            .toolbar {
                 if viewModel.currentUserProfile != nil {
                     Button("Edit Username") {
                         showingEditUsernameSheet = true
                     }
                 }
            }
            .sheet(isPresented: $showingEditUsernameSheet) {
                EditUsernameView(viewModel: viewModel)
            }
        }
    }
}

struct GridNodeView: View {
    let node: GridNode

    var body: some View {
        Rectangle()
            .fill(node.userProfile != nil ? colorForUser(node.userProfile) : Color.gray.opacity(0.3))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Text(node.userProfile?.username.prefix(1) ?? "")
                    .foregroundColor(.white)
                    .font(.caption)
            )
    }
    
    private func colorForUser(_ profile: UserProfile?) -> Color {
        guard let profile = profile else { return .gray }
        var hash = 0
        for char in profile.userID {
            hash = Int(char.asciiValue ?? 0) + ((hash << 5) - hash)
        }
        let hue = Double(abs(hash) % 256) / 255.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
}

struct EditUsernameView: View {
    @ObservedObject var viewModel: GridViewModel
    @State private var newUsername: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                TextField("Enter new username", text: $newUsername)
                Button("Save Username") {
                    if !newUsername.isEmpty {
                        viewModel.updateCurrentUsername(newUsername: newUsername)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Username")
            .onAppear {
                if let currentUsername = viewModel.currentUserProfile?.username {
                    newUsername = currentUsername
                }
            }
            .toolbar{
                ToolbarItem(placement: .navigationBarLeading){
                    Button("Cancel"){
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GridView_Previews: PreviewProvider {
    static var previews: some View {
        let mockViewModel = GridViewModel()
        let dummyProfile = UserProfile(userID: "previewUser123", username: "PreviewUser")
        mockViewModel.setCurrentUserProfile(dummyProfile)
        
        return GridView(viewModel: mockViewModel)
    }
} 