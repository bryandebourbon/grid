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
    
    @StateObject private var gridViewModel = GridViewModel(networkService: NetworkService())

    // Authentication State
    @State private var showSignInView = true
    @State private var appleUserID: String? = nil

    // Profile State
    @State private var userProfile: UserProfile? = nil
    @State private var showCreateProfileView = false
    @State private var isLoadingProfile = false

    var body: some View {
        Group {
            if showSignInView {
                SignInView(
                    showSignInView: $showSignInView,
                    onSignInSuccess: { credential in
                        self.appleUserID = credential.user
                        checkUserProfile(userID: credential.user)
                    }
                )
            } else if isLoadingProfile {
                ProgressView("Loading Profile...")
            } else if showCreateProfileView {
                if let userID = appleUserID {
                    CreateProfileView(showCreateProfileView: $showCreateProfileView, 
                                      appleUserID: userID)
                        .onDisappear {
                            if !showCreateProfileView { 
                                self.isLoadingProfile = true
                                checkUserProfile(userID: userID)
                            }
                        }
                } else {
                    Text("Error: User ID missing. Cannot create profile.")
                    Button("Try Sign In Again") { signOut() }
                }
            } else if let currentProfile = userProfile { 
                GridView(viewModel: gridViewModel)
            } else {
                ProgressView("Initializing...")
                    .onAppear {
                        if let userID = appleUserID {
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
            print("ContentView: checkUserProfile called with empty userID.")
            signOut()
            return
        }
        print("ContentView: Checking profile for userID: \(userID)")
        isLoadingProfile = true
        let privateDB = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: userID) 

        // Use CKFetchRecordsOperation to properly download CKAssets
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        fetchOperation.desiredKeys = ["profileImage"] // Specify which fields to fetch
        fetchOperation.fetchRecordsCompletionBlock = { recordsByRecordID, error in
            DispatchQueue.main.async {
                self.isLoadingProfile = false
                if let actualError = error as? CKError {
                    if actualError.code == .unknownItem {
                        print("ContentView: No profile record found for userID: \(userID) (CKError.unknownItem). Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else if actualError.code == .partialFailure {
                        // This commonly happens when trying to fetch a record that doesn't exist
                        print("ContentView: CloudKit partial failure for userID: \(userID). Likely no profile exists yet. Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else {
                        print("ContentView: CloudKit error fetching profile for userID: \(userID). Error: \(actualError.localizedDescription)")
                        // For genuine network/server issues, maybe retry instead of signing out
                        self.signOut() // Simple fallback: sign out
                    }
                } else if let anError = error { 
                    // For first-time users, "Failed to fetch some records" is normal when no profile exists
                    print("ContentView: Non-CloudKit error fetching profile for userID: \(userID). Error: \(anError.localizedDescription)")
                    if anError.localizedDescription.contains("Failed to fetch some records") {
                        print("ContentView: Treating 'Failed to fetch some records' as missing profile. Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else {
                        self.signOut() // Only sign out for other errors
                    }
                } else if let fetchedRecord = recordsByRecordID?[recordID] {
                    // Record was successfully fetched with assets downloaded
                    print("ContentView: Successfully fetched CKRecord for userID: \(userID). Attempting to initialize UserProfile.")
                    if let profile = UserProfile(record: fetchedRecord) {
                        self.userProfile = profile
                        self.gridViewModel.setCurrentUserProfile(profile)
                        self.showSignInView = false
                        self.showCreateProfileView = false
                        print("ContentView: UserProfile initialized and set for userID: \(profile.userID). Should navigate to GridView.")
                    } else {
                        // Critical error: Record exists but UserProfile.init(record:) failed.
                        // This should NOT loop back to CreateProfileView if the record is present but malformed or init logic is flawed.
                        print("ContentView: CRITICAL ERROR - Failed to initialize UserProfile from fetched CKRecord for userID: \(userID). The record data might be incompatible with UserProfile.init(record:). Check model and CloudKit schema.")
                        // Display a persistent error to the user or sign out to prevent loop.
                        // For now, signing out.
                        self.signOut()
                        // TODO: Consider showing a user-facing alert here.
                    }
                } else {
                    // Should not happen: no error, but also no record.
                    print("ContentView: Unexpected state - no error and no record fetched for userID: \(userID). Treating as if profile not found.")
                    self.userProfile = nil
                    self.showSignInView = false 
                    self.showCreateProfileView = true // Fallback to create profile
                }
            }
        }
        
        privateDB.add(fetchOperation)
    }
    
    private func signOut() {
        appleUserID = nil
        userProfile = nil
        gridViewModel.currentUserProfile = nil
        showSignInView = true
        showCreateProfileView = false
        isLoadingProfile = false
    }

    // addItem and deleteItems are from the template, may not be needed for the grid app's core logic
    // depending on what `Item` represents.
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

struct SignInView: View {
    @Binding var showSignInView: Bool
    var onSignInSuccess: (ASAuthorizationAppleIDCredential) -> Void 

    var body: some View {
        VStack {
            Text("Welcome to Grid")
                .font(.largeTitle)
                .padding()

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email] // Still request fullName for potential future use or if Apple requires it
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            onSignInSuccess(appleIDCredential)
                        } else {
                             print("Sign in with Apple: Failed to cast credential.")
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
