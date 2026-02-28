//
//  AuthViewModel.swift
//  ScriptureScribe
//
//  Manages authentication state for the whole app.
//  Injected as an environment object from ScriptureScribeApp.
//
//  • Listens to Firebase Auth's state change — survives app restarts automatically.
//  • currentUser is nil when signed out, populated when signed in.
//  • Sign in with Apple uses a two-step flow: startAppleSignIn() then completeAppleSignIn(_:).
//

import AuthenticationServices
import Combine
import FirebaseAuth
import GoogleSignIn
import SwiftUI
import UIKit

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isSignedIn:   Bool     = false
    @Published var currentUser:  AppUser? = nil
    @Published var errorMessage: String?  = nil
    @Published var isLoading:    Bool     = false

    /// Convenience: returns the Firebase UID of the signed-in user, or nil.
    var currentUserID: String? { currentUser?.id }

    // MARK: - Private

    private let authService      = AuthService()
    private let firestoreService = FirestoreService()
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Init

    init() {
        // Firebase persists the session — this listener fires immediately on launch
        // if the user is already signed in.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let firebaseUser {
                    self.isSignedIn = true
                    if self.currentUser == nil {
                        // Load from Firestore; fall back to building from Firebase Auth data
                        var user = (try? await self.firestoreService.fetchUser(userId: firebaseUser.uid))
                            ?? AppUser(
                                id:          firebaseUser.uid,
                                displayName: firebaseUser.displayName ?? "Scribe",
                                email:       firebaseUser.email ?? "",
                                createdAt:   Date(),
                                photoURL:    firebaseUser.photoURL?.absoluteString
                            )
                        // Firebase Auth always stores the Google/Apple photo URL.
                        // If our Firestore doc is missing it (old accounts), copy it in now.
                        if user.photoURL == nil, let authPhoto = firebaseUser.photoURL?.absoluteString {
                            user.photoURL = authPhoto
                            try? await self.firestoreService.updateUserPhoto(
                                userId: firebaseUser.uid, photoURL: authPhoto)
                        }
                        self.currentUser = user
                    }
                } else {
                    self.isSignedIn  = false
                    self.currentUser = nil
                }
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signIn(email: email, password: password)
            // Auth state listener handles updating currentUser
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await authService.signUp(
                email: email, password: password, displayName: displayName)
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        isLoading    = true
        errorMessage = nil

        // Find the currently visible window/screen to present the Google sheet from
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            errorMessage = "Could not present Google sign-in. Please try again."
            isLoading = false
            return
        }

        do {
            let user     = try await authService.signInWithGoogle(presenting: rootVC)
            currentUser  = user
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple

    /// Step 1: call when the user taps the Sign in with Apple button.
    /// Pass the returned hashed nonce into ASAuthorizationAppleIDRequest.nonce.
    func startAppleSignIn() -> String {
        authService.startAppleSignIn()
    }

    /// Step 2: call inside the ASAuthorizationController delegate callback.
    func completeAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await authService.completeAppleSignIn(credential: credential)
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Profile Photo

    /// Call with JPEG data from PhotosPicker. Uploads to Firebase Storage, then saves the URL.
    func uploadAndSetProfilePhoto(imageData: Data) async {
        guard let userId = currentUserID else { return }
        isLoading = true
        do {
            let url = try await authService.uploadProfilePhoto(userId: userId, imageData: imageData)
            try await FirestoreService().updateUserPhoto(userId: userId, photoURL: url)
            currentUser?.photoURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try authService.signOut()
            currentUser = nil
            isSignedIn  = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
