//
//  ContentView.swift
//  grid
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import SwiftUI
import SwiftData
import AuthenticationServices
import CloudKit

// UserProfile and CreateProfileView should be defined in their own files
// (e.g., Models/UserProfile.swift and Views/CreateProfileView.swift)
// and included in the app target.

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    // Authentication State
    @State private var showSignInView = true
    @State private var appleUserID: String? = nil
    @State private var userFullName: PersonNameComponents? = nil
    @State private var userEmail: String? = nil

    // Profile State
    @State private var userProfile: UserProfile? = nil // Uses UserProfile from Models/
    @State private var showCreateProfileView = false
    @State private var isLoadingProfile = false

    var body: some View {
        Group {
            if showSignInView {
                SignInView(
                    showSignInView: $showSignInView,
                    appleUserID: $appleUserID,
                    userFullName: $userFullName,
                    userEmail: $userEmail,
                    onSignInSuccess: { userID in
                        self.appleUserID = userID
                        checkUserProfile(userID: userID)
                    }
                )
            } else if isLoadingProfile {
                ProgressView("Loading Profile...")
            } else if showCreateProfileView {
                if let userID = appleUserID, !userID.isEmpty {
                    CreateProfileView(showCreateProfileView: $showCreateProfileView, appleUserID: userID) // Uses CreateProfileView from Views/
                        .onDisappear {
                            if !showCreateProfileView { 
                                self.isLoadingProfile = false 
                                // After profile creation, attempt to load it to transition to main view
                                if let currentUserID = self.appleUserID, !currentUserID.isEmpty {
                                    checkUserProfile(userID: currentUserID)
                                }
                            }
                        }
                } else {
                    Text("Error: User ID not available for profile creation.")
                    Button("Try Sign In Again") { signOut() }
                }
            } else if let currentProfile = userProfile {
                // Main App Content (Grid View will go here)
                NavigationSplitView {
                    List {
                        Text("Welcome, \(currentProfile.username)!")
                        ForEach(items) { item in
                            NavigationLink {
                                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                            } label: {
                                Text("Item: \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Text("Profile: \(currentProfile.username)")
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                        }
                        ToolbarItem {
                            Button(action: addItem) {
                                Label("Add Item", systemImage: "plus")
                            }
                        }
                        ToolbarItem(placement: .bottomBar) {
                             Button("Sign Out") {
                                 signOut()
                             }
                         }
                    }
                } detail: {
                    Text("Select an item. Grid View will replace this.")
                }
            } else {
                ProgressView("Initializing...")
                    .onAppear {
                        if appleUserID == nil {
                           showSignInView = true
                        } else if let userID = appleUserID, !userID.isEmpty {
                            checkUserProfile(userID: userID)
                        } else {
                            signOut() 
                        }
                    }
            }
        }
    }

    private func checkUserProfile(userID: String) {
        guard !userID.isEmpty else {
            print("checkUserProfile called with empty userID.")
            signOut()
            return
        }
        isLoadingProfile = true
        let privateDB = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: userID) 

        privateDB.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                isLoadingProfile = false
                if let fetchedRecord = record, error == nil {
                    self.userProfile = UserProfile(record: fetchedRecord) // Uses UserProfile from Models/
                    if self.userProfile != nil {
                        self.showSignInView = false
                        self.showCreateProfileView = false
                        print("User profile loaded: \(self.userProfile!.username)")
                    } else {
                        print("Error: Could not parse fetched profile record.")
                        self.showCreateProfileView = true 
                    }
                } else {
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        print("No profile found for user ID: \(userID). Prompting to create one.")
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else {
                        print("Error fetching profile: \(error?.localizedDescription ?? "Unknown error")")
                        signOut() 
                    }
                }
            }
        }
    }
    
    private func signOut() {
        appleUserID = nil
        userFullName = nil
        userEmail = nil
        userProfile = nil
        showSignInView = true
        showCreateProfileView = false
        isLoadingProfile = false
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(modelContext.delete)
        }
    }
}

// SignInView struct was previously part of ContentView.swift
struct SignInView: View {
    @Binding var showSignInView: Bool
    @Binding var appleUserID: String?
    @Binding var userFullName: PersonNameComponents?
    @Binding var userEmail: String?
    var onSignInSuccess: (String) -> Void

    var body: some View {
        VStack {
            Text("Welcome to Grid")
                .font(.largeTitle)
                .padding()

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            let userID = appleIDCredential.user
                            self.appleUserID = userID
                            self.userFullName = appleIDCredential.fullName
                            self.userEmail = appleIDCredential.email
                            
                            print("User ID: \(userID)")
                            print("Full Name: \(appleIDCredential.fullName?.givenName ?? "") \(appleIDCredential.fullName?.familyName ?? "")")
                            print("Email: \(appleIDCredential.email ?? "")")
                            
                            onSignInSuccess(userID)
                        }
                    case .failure(let error):
                        print("Sign in with Apple failed: \(error.localizedDescription)")
                    }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 60)
            .padding()
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
