//
//  AuthService.swift
//  ScriptureScribe
//
//  Wraps Firebase Authentication.
//  Supports email/password and Sign in with Apple.
//
//  Sign in with Apple flow:
//    1. Call startAppleSignIn() to get a hashed nonce — pass this to ASAuthorizationAppleIDRequest.
//    2. After the system sheet completes, pass the returned credential to completeAppleSignIn(_:).
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import GoogleSignIn
import UIKit

final class AuthService {

    // Held between step 1 and step 2 of the Apple sign-in flow
    private var currentNonce: String?

    // MARK: - Email / Password

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    /// Creates a new account, sets the display name in Firebase Auth, and writes a Firestore user doc.
    func signUp(email: String, password: String, displayName: String) async throws -> AppUser {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let uid = result.user.uid

        // Store the display name in Firebase Auth (shows up in Firebase Console)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        let appUser = AppUser(id: uid, displayName: displayName, email: email, createdAt: Date())
        try await FirestoreService().createUser(appUser)
        return appUser
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Sign in with Google

    func signInWithGoogle(presenting viewController: UIViewController) async throws -> AppUser {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        let googleUser = result.user
        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthError.invalidToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken:  idToken,
            accessToken:  googleUser.accessToken.tokenString
        )
        let authResult    = try await Auth.auth().signIn(with: credential)
        let firebaseUser  = authResult.user
        let displayName   = firebaseUser.displayName ?? googleUser.profile?.name ?? "Scribe"
        let email         = firebaseUser.email ?? googleUser.profile?.email ?? ""
        // Google gives us a profile photo URL — grab a 200px version
        let googlePhotoURL = googleUser.profile?.imageURL(withDimension: 200)?.absoluteString

        // Return existing Firestore user doc if it already exists (returning user)
        let db  = Firestore.firestore()
        let doc = try await db.collection("users").document(firebaseUser.uid).getDocument()
        if doc.exists {
            // If the existing doc has no photo but Google provides one, save it
            let existingPhoto = doc.data()?["photoURL"] as? String
            if existingPhoto == nil, let newPhoto = googlePhotoURL {
                try? await db.collection("users").document(firebaseUser.uid).updateData(["photoURL": newPhoto])
            }
            return AppUser(
                id:          firebaseUser.uid,
                displayName: (doc.data()?["displayName"] as? String) ?? displayName,
                email:       email,
                createdAt:   (doc.data()?["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                photoURL:    existingPhoto ?? googlePhotoURL
            )
        }

        // New Google user — write a Firestore document
        let appUser = AppUser(id: firebaseUser.uid, displayName: displayName, email: email, createdAt: Date(), photoURL: googlePhotoURL)
        try await FirestoreService().createUser(appUser)
        return appUser
    }

    // MARK: - Upload Profile Photo

    /// Uploads image data to Firebase Storage and returns the public download URL.
    func uploadProfilePhoto(userId: String, imageData: Data) async throws -> String {
        let ref = Storage.storage().reference().child("profilePhotos/\(userId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Sign in with Apple (step 1 — call before presenting the system sheet)

    /// Returns the SHA-256 hashed nonce to pass to ASAuthorizationAppleIDRequest.nonce.
    func startAppleSignIn() -> String {
        let nonce = randomNonce()
        currentNonce = nonce
        return sha256(nonce)
    }

    // MARK: - Sign in with Apple (step 2 — call in the ASAuthorization delegate callback)

    func completeAppleSignIn(credential: ASAuthorizationAppleIDCredential) async throws -> AppUser {
        guard let nonce = currentNonce else { throw AuthError.missingNonce }
        guard let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8)
        else { throw AuthError.invalidToken }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        let user = result.user

        // Prefer the name Apple provided (only sent on first sign-in)
        let displayName: String
        if let given = credential.fullName?.givenName, !given.isEmpty {
            let parts = [given, credential.fullName?.familyName].compactMap { $0 }
            displayName = parts.joined(separator: " ")
        } else {
            displayName = user.displayName?.isEmpty == false ? user.displayName! : "Scribe"
        }

        // Check if this user already has a Firestore document (returning user)
        let db = Firestore.firestore()
        let doc = try await db.collection("users").document(user.uid).getDocument()
        if doc.exists {
            return AppUser(
                id:          user.uid,
                displayName: displayName,
                email:       user.email ?? "",
                createdAt:   (doc.data()?["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                photoURL:    doc.data()?["photoURL"] as? String
            )
        }

        // New Apple user — write a Firestore document
        let appUser = AppUser(id: user.uid, displayName: displayName, email: user.email ?? "", createdAt: Date())
        try await FirestoreService().createUser(appUser)
        return appUser
    }

    // MARK: - Delete Account

    /// Deletes all user data from Firestore, Firebase Storage, and Firebase Auth.
    /// Throws AuthErrorCode.requiresRecentLogin if the user needs to re-authenticate first.
    func deleteAccount(userId: String) async throws {
        let firestoreService = FirestoreService()

        // 1. Delete all Firestore user data (subcollections + user doc)
        try await firestoreService.deleteAllUserData(userId: userId)

        // 2. Delete Firebase Storage files (profile photo + annotations)
        let storage = Storage.storage().reference()
        // Profile photo
        let profileRef = storage.child("profilePhotos/\(userId).jpg")
        try? await profileRef.delete()
        // Annotations folder: list and delete all
        let annotationsRef = storage.child("annotations/\(userId)")
        if let listResult = try? await annotationsRef.listAll() {
            for item in listResult.items {
                try? await item.delete()
            }
        }

        // 3. Delete the Firebase Auth account (may throw requiresRecentLogin)
        guard let user = Auth.auth().currentUser else { return }
        try await user.delete()
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case missingNonce
        case invalidToken
        case requiresReSignIn

        var errorDescription: String? {
            switch self {
            case .missingNonce:     return "Sign-in nonce is missing. Please try again."
            case .invalidToken:     return "Could not read the Apple ID token. Please try again."
            case .requiresReSignIn: return "For security, please sign in again before deleting your account."
            }
        }
    }

    // MARK: - Private Cryptography Helpers

    private func randomNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
