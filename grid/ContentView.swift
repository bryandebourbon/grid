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
    @State private var showSignInView = false  // Start as false, check credentials first
    @State private var appleUserID: String? = nil
    @State private var isCheckingCredentials = true  // NEW: Track initial credential check

    // Profile State
    @State private var userProfile: UserProfile? = nil
    @State private var showCreateProfileView = false
    @State private var isLoadingProfile = false

    // Navigation is now handled directly by GridViewModel via its chatRecipientToPresent property

    @ViewBuilder
    var body: some View {
        Group {
            if isCheckingCredentials {
                // NEW: Show loading while checking existing credentials
                AnyView(ProgressView("Checking credentials...")
                    .onAppear {
                        checkExistingCredentials()
                    })
            } else if showSignInView {
                AnyView(SignInView(
                    showSignInView: $showSignInView,
                    onSignInSuccess: { credential in
                        self.appleUserID = credential.user
                        // Store user ID for future launches
                        UserDefaults.standard.set(credential.user, forKey: "appleUserID")
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
                AnyView(GridView(viewModel: gridViewModel, signOutAction: signOut, deleteAccountAction: deleteAccount))
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
        fetchOperation.desiredKeys = [
            "profileImage",
            "userID",
            "deviceID",
            "deviceName",
            "bio",
            "interests",
            "additionalPhotos",
            "latitude",
            "longitude",
            "lastActiveTimestamp",
            "isCurrentlyActive"
        ]
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
        // Clear stored credentials
        clearStoredCredentials()
        
        appleUserID = nil
        userProfile = nil
        gridViewModel.currentUserProfile = nil
        showSignInView = true
        showCreateProfileView = false
        isLoadingProfile = false
        isCheckingCredentials = false
    }

    private func deleteAccount() {
        guard let userID = appleUserID else {
            print("ContentView: Cannot delete account, userID is nil.")
            return
        }

        print("ContentView: Attempting to delete account for userID: \(userID)")
        isLoadingProfile = true // Show loading indicator

        gridViewModel.performFullAccountDeletion { error in
            DispatchQueue.main.async {
                self.isLoadingProfile = false // Use self explicitly or implicitly
                if let error = error {
                    print("ContentView: Error during account deletion: \(error.localizedDescription)")
                    // Optionally, show an alert to the user that deletion failed
                    // For now, we still sign out even if server-side deletion had issues.
                } else {
                    print("ContentView: Account deletion process completed.")
                }
                // Whether deletion succeeds or fails on the server, sign the user out locally.
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

    // NEW: Check for existing Apple ID credentials on app launch
    private func checkExistingCredentials() {
        print("ContentView: Checking existing credentials...")
        
        // First, check if we have a stored user ID
        if let storedUserID = UserDefaults.standard.string(forKey: "appleUserID") {
            print("ContentView: Found stored Apple ID: \(storedUserID)")
            
            // Verify the credential is still valid with Apple
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: storedUserID) { credentialState, error in
                DispatchQueue.main.async {
                    self.isCheckingCredentials = false
                    
                    switch credentialState {
                    case .authorized:
                        print("ContentView: Apple ID credential is still valid")
                        self.appleUserID = storedUserID
                        self.checkUserProfile(userID: storedUserID)
                    case .revoked, .notFound:
                        print("ContentView: Apple ID credential is no longer valid")
                        self.clearStoredCredentials()
                        self.showSignInView = true
                    default:
                        print("ContentView: Unknown credential state")
                        self.clearStoredCredentials()
                        self.showSignInView = true
                    }
                }
            }
        } else {
            print("ContentView: No stored Apple ID found")
            DispatchQueue.main.async {
                self.isCheckingCredentials = false
                self.showSignInView = true
            }
        }
    }
    
    // NEW: Clear stored credentials
    private func clearStoredCredentials() {
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        self.appleUserID = nil
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
        //        .modelContainer(for: Item.self, inMemory: true)
}
