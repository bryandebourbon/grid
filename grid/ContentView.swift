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

struct ContentView: View {
    @StateObject private var gridViewModel = GridViewModel()

    // Authentication State
    @State private var showSignInView = false  // Start as false, check credentials first
    @State private var appleUserID: String? = nil
    @State private var isCheckingCredentials = true  // NEW: Track initial credential check

    // Profile State
    @State private var userProfile: UserProfile? = nil
    @State private var showAskDisplayName = false
    @State private var isLoadingProfile = false
    @State private var profileLoadFailed = false  // Transient load failure (network/server) — offer retry instead of signing out
    @State private var deletionErrorMessage: String?

    // Navigation is now handled directly by GridViewModel via its chatRecipientToPresent property

    @ViewBuilder
    var body: some View {
        Group {
            if isCheckingCredentials {
                AnyView(loadingScreen("Checking credentials..."))
            } else if showSignInView {
                AnyView(SignInView(
                    showSignInView: $showSignInView,
                    onSignInSuccess: { credential in
                        completeSignIn(
                            userID: credential.user,
                            appleName: ProfileDisplayNameLogic.formattedAppleName(
                                givenName: credential.fullName?.givenName,
                                familyName: credential.fullName?.familyName
                            )
                        )
                    }
                ))
            } else if isLoadingProfile {
                AnyView(loadingScreen("Loading Profile..."))
            } else if profileLoadFailed {
                AnyView(VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Couldn't load your profile")
                        .font(.headline)
                    Text("Check your connection and try again.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        profileLoadFailed = false
                        if let userID = appleUserID {
                            checkUserProfile(userID: userID)
                        } else {
                            signOut()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding())
            } else if showAskDisplayName {
                if let userID = appleUserID {
                    AnyView(AskDisplayNameView(
                        initialName: ProfileDisplayNameLogic.pendingPersonName() ?? "",
                        onSave: { name in
                            createMinimalProfile(named: name, userID: userID)
                        }
                    ))
                } else {
                    AnyView(VStack {
                        Text("Error: User ID missing. Cannot create profile.")
                        Button("Try Sign In Again") { signOut() }
                    })
                }
            } else if let currentProfile = userProfile {
                if !GridUITestHarness.isActive
                    && ProfileDisplayNameLogic.isMissingPersonName(currentProfile.deviceName) {
                    AnyView(AskDisplayNameView(
                        initialName: ProfileDisplayNameLogic.pendingPersonName() ?? "",
                        onSave: { name in
                            applyPersonName(name, to: currentProfile)
                        }
                    ))
                } else {
                    AnyView(GridView(viewModel: gridViewModel, signOutAction: signOut, deleteAccountAction: deleteAccount))
                }
            } else {
                AnyView(loadingScreen("Initializing..."))
            }
        }
        .task {
            if isCheckingCredentials {
                checkExistingCredentials()
            } else if userProfile == nil, let userID = appleUserID, !isLoadingProfile, !showAskDisplayName, !showSignInView, !profileLoadFailed {
                checkUserProfile(userID: userID)
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
        .alert(
            "Account Deletion Failed",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("OK") { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
    }

    private func completeSignIn(userID: String, appleName: String? = nil) {
        if let appleName {
            ProfileDisplayNameLogic.storePendingPersonName(appleName)
        }
        appleUserID = userID
        UserDefaults.standard.set(userID, forKey: "appleUserID")
        showSignInView = false
        checkUserProfile(userID: userID)
    }

    private func applyPersonName(_ name: String, to profile: UserProfile) {
        var updated = profile
        updated.deviceName = name
        userProfile = updated
        if gridViewModel.currentUserProfile == nil {
            gridViewModel.setCurrentUserProfile(updated)
        } else {
            gridViewModel.updatePersonName(name)
        }
    }

    private func createMinimalProfile(named name: String, userID: String) {
        let deviceID = generateConsistentDeviceID(for: userID)
        let profile = UserProfile(
            userID: userID,
            deviceID: deviceID,
            deviceName: name
        )
        userProfile = profile
        showAskDisplayName = false
        isLoadingProfile = false
        profileLoadFailed = false
        ProfileDisplayNameLogic.clearPendingPersonName()
        gridViewModel.setCurrentUserProfile(profile)
        gridViewModel.persistAndUpdateProfileAndGrid()
    }

    private func checkUserProfile(userID: String) {
        guard !userID.isEmpty else {
            print("ContentView: checkUserProfile called with empty userID.")
            signOut()
            return
        }
        
        // Generate a consistent device identifier based on Apple User ID
        // This ensures the same account works across dev builds, TestFlight, and App Store
        let deviceID = generateConsistentDeviceID(for: userID)

        print("ContentView: Checking profile for deviceID: \(deviceID) (userID: \(userID))")
        isLoadingProfile = true
        profileLoadFailed = false
        
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
                        self.showAskDisplayName = true
                    } else if actualError.code == .partialFailure {
                        // This commonly happens when trying to fetch a record that doesn't exist
                        print("ContentView: CloudKit partial failure for deviceID: \(deviceID). Likely no profile exists yet. Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showAskDisplayName = true
                    } else {
                        print("ContentView: CloudKit error fetching profile for deviceID: \(deviceID). Error: \(actualError.localizedDescription)")
                        // Genuine network/server issue — keep the user signed in and
                        // offer a retry rather than forcing them back to sign-in.
                        self.profileLoadFailed = true
                    }
                } else if let anError = error { 
                    // For first-time devices, "Failed to fetch some records" is normal when no profile exists
                    print("ContentView: Non-CloudKit error fetching profile for deviceID: \(deviceID). Error: \(anError.localizedDescription)")
                    if anError.localizedDescription.contains("Failed to fetch some records") {
                        print("ContentView: Treating 'Failed to fetch some records' as missing profile. Prompting to create one.")
                        self.userProfile = nil
                        self.showSignInView = false 
                        self.showAskDisplayName = true
                    } else {
                        // Likely transient — offer retry instead of signing out.
                        self.profileLoadFailed = true
                    }
                } else if let fetchedRecord = recordsByRecordID?[recordID] {
                    // Record was successfully fetched with assets downloaded
                    print("ContentView: Successfully fetched CKRecord for deviceID: \(deviceID). Attempting to initialize UserProfile.")
                    if let profile = UserProfile(record: fetchedRecord) {
                        self.showSignInView = false
                        self.showAskDisplayName = false
                        if ProfileDisplayNameLogic.isMissingPersonName(profile.deviceName),
                           let pending = ProfileDisplayNameLogic.pendingPersonName() {
                            self.applyPersonName(pending, to: profile)
                        } else {
                            self.userProfile = profile
                            self.gridViewModel.setCurrentUserProfile(profile)
                        }
                        print("ContentView: UserProfile initialized and set for deviceID: \(profile.deviceID). Should navigate to GridView.")
                    } else {
                        print("ContentView: CRITICAL ERROR - Failed to initialize UserProfile from fetched CKRecord for deviceID: \(deviceID). The record data might be incompatible with UserProfile.init(record:). Check model and CloudKit schema.")
                        self.profileLoadFailed = true
                    }
                } else {
                    // Should not happen: no error, but also no record.
                    print("ContentView: Unexpected state - no error and no record fetched for deviceID: \(deviceID). Treating as if profile not found.")
                    self.userProfile = nil
                    self.showSignInView = false 
                    self.showAskDisplayName = true
                }
            }
        }
        
        publicDB.add(fetchOperation)
    }
    
    // Generate a consistent device ID that works across dev builds, TestFlight, and App Store
    private func generateConsistentDeviceID(for userID: String) -> String {
        // Check if we have a stored device ID for this user
        let deviceID = DeviceIdentityLogic.resolvedDeviceID(forAppleUserID: userID)
        print("Generated consistent device ID: \(deviceID) for user: \(userID)")
        return deviceID
    }
    
    private func signOut() {
        // Clear stored credentials
        clearStoredCredentials()
        
        // Clear the stored device ID for this user
        if let userID = appleUserID {
            let token = DeviceIdentityLogic.peerToken()
            UserDefaults.standard.removeObject(forKey: DeviceIdentityLogic.storageKey(forAppleUserID: userID, peerToken: token))
            print("Cleared stored device ID for user: \(userID)")
        }
        
        appleUserID = nil
        userProfile = nil
        gridViewModel.currentUserProfile = nil
        showSignInView = true
        showAskDisplayName = false
        isLoadingProfile = false
        isCheckingCredentials = false
        profileLoadFailed = false
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
                self.isLoadingProfile = false
                if let error = error {
                    print("ContentView: Error during account deletion: \(error.localizedDescription)")
                    self.deletionErrorMessage = "Your account could not be fully deleted. \(error.localizedDescription) You are still signed in. Try again or email \(AppSupport.email)."
                } else {
                    print("ContentView: Account deletion process completed.")
                    self.signOut()
                }
            }
        }
    }

    private func loadingScreen(_ title: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // NEW: Check for existing Apple ID credentials on app launch
    private func checkExistingCredentials() {
        print("ContentView: Checking existing credentials...")
        if GridUITestHarness.isActive {
            enterUITestSession()
            return
        }

        // First, check if we have a stored user ID
        if let storedUserID = UserDefaults.standard.string(forKey: "appleUserID") {
            print("ContentView: Found stored Apple ID: \(storedUserID)")

            if storedUserID.hasPrefix("grid.test-peer.") {
                UserDefaults.standard.removeObject(forKey: "appleUserID")
                UserDefaults.standard.removeObject(forKey: "grid.testPeerUserID")
                UserDefaults.standard.removeObject(forKey: "grid.testPeer.profileSnapshot")
                UserDefaults.standard.removeObject(forKey: "grid.testPeer.photoJPEG")
                showSignInView = true
                isCheckingCredentials = false
                return
            }

            // Verify the credential is still valid with Apple
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: storedUserID) { credentialState, error in
                DispatchQueue.main.async {
                    guard self.isCheckingCredentials else { return }
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

            // iOS 27 + a broken debugger attach can stall this callback forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard self.isCheckingCredentials else { return }
                print("ContentView: Apple credential check timed out; using stored userID")
                self.isCheckingCredentials = false
                self.appleUserID = storedUserID
                self.checkUserProfile(userID: storedUserID)
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
    private func enterUITestSession() {
        let profile = GridUITestHarness.me
        appleUserID = profile.userID
        userProfile = profile
        showSignInView = false
        showAskDisplayName = false
        isCheckingCredentials = false
        isLoadingProfile = false
        profileLoadFailed = false
        gridViewModel.installUITestFixtures()
    }

    private func clearStoredCredentials() {
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        self.appleUserID = nil
    }
}

struct SignInView: View {
    @Binding var showSignInView: Bool
    var onSignInSuccess: (ASAuthorizationAppleIDCredential) -> Void

    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var confirmedAge17 = UserDefaults.standard.bool(forKey: AgeGateLogic.confirmationDefaultsKey)

    var body: some View {
        VStack {
            Text("Welcome to Grid")
                .font(.largeTitle)
                .padding()

            Button {
                confirmedAge17.toggle()
                UserDefaults.standard.set(confirmedAge17, forKey: AgeGateLogic.confirmationDefaultsKey)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: confirmedAge17 ? "checkmark.square.fill" : "square")
                        .font(.title3)
                    Text("I confirm I am \(AgeGateLogic.minimumAge) or older")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .accessibilityLabel("Confirm you are \(AgeGateLogic.minimumAge) or older")
            .accessibilityAddTraits(confirmedAge17 ? [.isSelected] : [])

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
            .disabled(!AgeGateLogic.canProceedToSignIn(confirmedMinimumAge: confirmedAge17))
            .opacity(AgeGateLogic.canProceedToSignIn(confirmedMinimumAge: confirmedAge17) ? 1 : 0.4)

            agreementNotice
                .padding(.horizontal, 32)

            Spacer()
        }
        .sheet(isPresented: $showingTerms) { TermsOfUseView() }
        .sheet(isPresented: $showingPrivacy) { PrivacyPolicyView() }
    }

    private var agreementNotice: some View {
        VStack(spacing: 6) {
            Text("By continuing, you agree to our Terms of Use (EULA) and Privacy Policy. Grid has zero tolerance for objectionable content and abusive behavior.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Terms of Use") { showingTerms = true }
                Button("Privacy Policy") { showingPrivacy = true }
            }
            .font(.footnote.weight(.semibold))
        }
    }
}

#Preview {
    ContentView()
}
