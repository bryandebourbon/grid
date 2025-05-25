//
//  ContentView.swift
//  grid
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import SwiftUI
import AuthenticationServices
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

// UserProfile and CreateProfileView should be defined in their own files
// (e.g., Models/UserProfile.swift and Views/CreateProfileView.swift)
// and included in the app target.

// Ensure UserProfile is imported if it's in a different module or file structure needs it
// If UserProfile is in the Models directory, you might not need an explicit import 
// if your project structure and target membership are set up correctly.
// However, to be explicit, especially if issues arise:
// import Models // Or the specific module name if you have one for Models

// Assuming UserProfile is in the main app target and Models group, direct import might not be needed
// but if it were in a separate module or framework, it would be.
// For now, we'll rely on Swift's module system to find UserProfile.swift

struct ContentView: View {
    //    @Query private var items: [Item]
    
    @StateObject private var gridViewModel = GridViewModel()

    // Authentication State
    @State private var showSignInView = true
    @State private var appleUserID: String? = nil

    // Profile State
    @State private var userProfile: UserProfile? = nil
    @State private var showCreateProfileView = false
    @State private var isLoadingProfile = false

    // Navigation state for push notifications
    @State private var shouldOpenChat = false
    @State private var chatRecipientDeviceID: String? = nil

    @ViewBuilder
    var body: some View {
        Group {
            if showSignInView {
                AnyView(SignInView(
                    showSignInView: $showSignInView,
                    onSignInSuccess: { credential in
                        self.appleUserID = credential.user
                        checkUserProfile(userID: credential.user)
                    }
                ))
            } else if isLoadingProfile {
                AnyView(ProgressView("Loading Profile..."))
            } else if showCreateProfileView {
                if let userID = appleUserID {
                    AnyView(CreateProfileView(showCreateProfileView: $showCreateProfileView,
                                      appleUserID: userID)
                        .onDisappear {
                            if !showCreateProfileView {
                                self.isLoadingProfile = true
                                checkUserProfile(userID: userID)
                            }
                        })
                } else {
                    AnyView(VStack { // Wrap in VStack for consistent view structure
                        Text("Error: User ID missing. Cannot create profile.")
                        Button("Try Sign In Again") { signOut() }
                    })
                }
            } else if let currentProfile = userProfile {
                AnyView(GridView(viewModel: gridViewModel, signOutAction: signOut, deleteAccountAction: deleteAccount)
                    .sheet(isPresented: $shouldOpenChat) {
                        if let recipientID = chatRecipientDeviceID {
                            NavigationView {
                                ChatView(viewModel: gridViewModel, recipientDeviceID: recipientID)
                            }
                        }
                    }
                )
            } else {
                AnyView(ProgressView("Initializing...")
                    .onAppear {
                        if let userID = appleUserID {
                            checkUserProfile(userID: userID)
                        } else {
                            signOut()
                        }
                    })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChat)) { notification in
            if let senderDeviceID = notification.object as? String {
                self.chatRecipientDeviceID = senderDeviceID
                self.shouldOpenChat = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Handle app becoming active - mark user as active and restart location updates
            gridViewModel.handleAppDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActive)) { _ in
            // Handle app going to background/inactive - mark user as inactive and stop location updates
            gridViewModel.handleAppWillResignActive()
        }
    }

    private func checkUserProfile(userID: String) {
        guard !userID.isEmpty else {
            print("ContentView: checkUserProfile called with empty userID.")
            signOut()
            return
        }
        
        // Generate a unique device identifier
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = UIDevice.current.name
        
        print("ContentView: Checking profile for deviceID: \(deviceID) (userID: \(userID))")
        isLoadingProfile = true
        
        // Check PUBLIC database first (since profiles are now public)
        let publicDB = CKContainer.default().publicCloudDatabase
        let recordID = CKRecord.ID(recordName: deviceID) // Use deviceID as record name

        // Use CKFetchRecordsOperation to properly download CKAssets
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        fetchOperation.desiredKeys = ["profileImage", "userID", "deviceID", "deviceName"] // Specify which fields to fetch
        fetchOperation.fetchRecordsCompletionBlock = { recordsByRecordID, error in
            DispatchQueue.main.async {
                self.isLoadingProfile = false
                if let actualError = error as? CKError {
                    if actualError.code == .unknownItem {
                        print("ContentView: No profile record found for deviceID: \(deviceID) (CKError.unknownItem). Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else if actualError.code == .partialFailure {
                        // This commonly happens when trying to fetch a record that doesn't exist
                        print("ContentView: CloudKit partial failure for deviceID: \(deviceID). Likely no profile exists yet. Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showCreateProfileView = true
                    } else {
                        print("ContentView: CloudKit error fetching profile for deviceID: \(deviceID). Error: \(actualError.localizedDescription)")
                        // For genuine network/server issues, maybe retry instead of signing out
                        self.signOut() // Simple fallback: sign out
                    }
                } else if let anError = error { 
                    // For first-time devices, "Failed to fetch some records" is normal when no profile exists
                    print("ContentView: Non-CloudKit error fetching profile for deviceID: \(deviceID). Error: \(anError.localizedDescription)")
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
                    print("ContentView: Successfully fetched CKRecord for deviceID: \(deviceID). Attempting to initialize UserProfile.")
                    if let profile = UserProfile(record: fetchedRecord) {
                        self.userProfile = profile
                        self.gridViewModel.setCurrentUserProfile(profile)
                        self.showSignInView = false
                        self.showCreateProfileView = false
                        print("ContentView: UserProfile initialized and set for deviceID: \(profile.deviceID). Should navigate to GridView.")
                    } else {
                        // Critical error: Record exists but UserProfile.init(record:) failed.
                        // This should NOT loop back to CreateProfileView if the record is present but malformed or init logic is flawed.
                        print("ContentView: CRITICAL ERROR - Failed to initialize UserProfile from fetched CKRecord for deviceID: \(deviceID). The record data might be incompatible with UserProfile.init(record:). Check model and CloudKit schema.")
                        // Display a persistent error to the user or sign out to prevent loop.
                        // For now, signing out.
                        self.signOut()
                        // TODO: Consider showing a user-facing alert here.
                    }
                } else {
                    // Should not happen: no error, but also no record.
                    print("ContentView: Unexpected state - no error and no record fetched for deviceID: \(deviceID). Treating as if profile not found.")
                    self.userProfile = nil
                    self.showSignInView = false 
                    self.showCreateProfileView = true // Fallback to create profile
                }
            }
        }
        
        publicDB.add(fetchOperation)
    }
    
    private func signOut() {
        appleUserID = nil
        userProfile = nil
        gridViewModel.currentUserProfile = nil
        showSignInView = true
        showCreateProfileView = false
        isLoadingProfile = false
    }

    private func deleteAccount() {
        guard let userID = appleUserID else {
            print("ContentView: Cannot delete account, userID is nil.")
            return
        }

        print("ContentView: Attempting to delete account for userID: \(userID)")
        isLoadingProfile = true // Show loading indicator during deletion

        let privateDB = CKContainer.default().privateCloudDatabase
        let recordIDToDelete = CKRecord.ID(recordName: userID)

        privateDB.delete(withRecordID: recordIDToDelete) { deletedRecordID, error in
            DispatchQueue.main.async {
                self.isLoadingProfile = false // Hide loading indicator
                if let error = error {
                    print("ContentView: Error deleting record from CloudKit: \(error.localizedDescription)")
                    // Optionally, show an alert to the user
                } else {
                    print("ContentView: Successfully deleted record from CloudKit for userID: \(userID)")
                }
                // Whether deletion succeeds or fails, sign the user out
                self.signOut()
            }
        }
    }

    // addItem and deleteItems are from the template, may not be needed for the grid app's core logic
    // depending on what `Item` represents.
    //    private func addItem() {
    //        withAnimation {
    //            let newItem = Item(timestamp: Date())
    //            modelContext.insert(newItem)
    //        }
    //    }
    //
    //    private func deleteItems(offsets: IndexSet) {
    //        withAnimation {
    //            offsets.map { items[$0] }.forEach(modelContext.delete)
    //        }
    //    }
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
        //        .modelContainer(for: Item.self, inMemory: true)
}
