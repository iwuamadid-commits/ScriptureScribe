//
//  AuthViewModel.swift
//  ScriptureScribe
//
//  Phase 0 stub — keeps the app compiling before Phase 6 (Firebase Auth + Sign in with Apple).
//  Full implementation added in Phase 6.
//

import Combine

final class AuthViewModel: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUserID: String? = nil

    // Phase 6 will add:
    //   func signInWithEmail(email:password:)
    //   func signUpWithEmail(email:password:displayName:)
    //   func signInWithApple()
    //   func signOut()
}
