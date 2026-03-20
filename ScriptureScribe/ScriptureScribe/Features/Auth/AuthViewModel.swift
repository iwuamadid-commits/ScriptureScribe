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
                    // Set isSignedIn AFTER currentUser so that observers
                    // (e.g. ContentView's onChange) see both values populated.
                    self.isSignedIn = true
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
            errorMessage = error.userMessage
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
            errorMessage = error.userMessage
        }
        isLoading = false
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        isLoading    = true
        errorMessage = nil

        // Find the topmost presented view controller so Google Sign-In
        // can present its sheet even when AuthView is already a modal.
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            errorMessage = "Could not present Google sign-in. Please try again."
            isLoading = false
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        do {
            let user     = try await authService.signInWithGoogle(presenting: topVC)
            currentUser  = user
        } catch let error as NSError
            where error.code == GIDSignInError.canceled.rawValue
               && error.domain == "com.google.GIDSignIn" {
            // User tapped "X" on the Google sheet — not a real error
        } catch {
            errorMessage = error.userMessage
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
            errorMessage = error.userMessage
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
            errorMessage = error.userMessage
        }
        isLoading = false
    }

    // MARK: - Sign Out

    /// Signs out of Firebase Auth. Local data (bookmarks, notes, annotations,
    /// theme, etc.) stays on device — only account deletion clears everything.
    func signOut() {
        do {
            try authService.signOut()
            // Clear premium cache so it doesn't leak to a different account
            UserDefaults.standard.removeObject(forKey: "isPremiumCached")
            currentUser = nil
            isSignedIn  = false
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Delete Account

    /// True when Firebase requires the user to re-authenticate before deleting.
    @Published var needsReAuth: Bool = false

    /// Deletes all user data from Firestore, Firebase Storage, and Firebase Auth,
    /// then clears local UserDefaults data and signs out.
    /// Returns true on success, false if re-auth is needed.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard let userId = currentUserID else { return false }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.deleteAccount(userId: userId)
            clearLocalData()
            currentUser = nil
            isSignedIn  = false
            isLoading   = false
            return true
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            needsReAuth = true
            isLoading   = false
            return false
        } catch {
            errorMessage = error.userMessage
            isLoading    = false
            return false
        }
    }

    /// Clears all locally persisted user data: UserDefaults keys, annotation
    /// drawing files, and photo annotation files so sign-out yields a fresh state.
    private func clearLocalData() {
        // ── 1. UserDefaults keys (correct names matching what the app actually writes) ──

        let keys: [String] = [
            // Bookmarks & notes
            "scripture_scribe_bookmarks",
            "scripture_scribe_bookmark_groups",
            "scripture_scribe_notes",
            // Habits
            "scripture_scribe_habits",
            "scripture_scribe_habit_logs",
            // Streaks
            "streak_currentCount", "streak_longestCount",
            "streak_lastOpenedDate", "streak_openedDatesJSON",
            // Theme & translation
            "selectedTheme", "myVersionIds",
            // Saved annotation colors
            "ss_savedAnnotationColors", "ss_savedAnnotationColors_v2",
            // Annotation tool preferences
            "ss_layoutMode", "ss_eraserType", "ss_eraserSize",
            "ss_selectedTool", "ss_showGuidelines", "ss_guideSpacing",
            "ss_toolSettings", "ss_penFavSizes", "ss_hlFavSizes", "ss_eraserFavSizes",
            // Annotation toggles
            "isLeftHanded", "allowFingerDrawing", "useDoubleTapForNote",
            // Reading preferences
            "fontSize", "lineSpacing", "fontChoice", "showRedLetters", "textAlignment",
            // Last reading position
            "lastBibleId", "lastBookId", "lastChapterId",
            // Audio
            "preferredVoiceIdentifier",
            // Daily section order
            "dailySectionOrder",
            // Onboarding / walkthrough
            "hasSeenOnboarding", "hasCompletedWalkthrough",
            // Premium cache (prevent leaking premium status between accounts)
            "isPremiumCached",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // ── 2. Clear per-chapter photo metadata (ss_photos_*) ──

        let allDefaults = UserDefaults.standard.dictionaryRepresentation()
        for key in allDefaults.keys where key.hasPrefix("ss_photos_") {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // ── 3. Delete annotation drawing files (.pkdrawing) and photo files (.jpg) ──

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let docs,
           let files = try? FileManager.default.contentsOfDirectory(
               at: docs, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for url in files {
                let name = url.lastPathComponent
                if name.hasSuffix(".pkdrawing") || name.hasPrefix("photo_") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
