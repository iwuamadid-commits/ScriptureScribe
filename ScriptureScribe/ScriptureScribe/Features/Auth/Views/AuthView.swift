//
//  AuthView.swift
//  ScriptureScribe
//
//  Sign In / Sign Up sheet.
//  Presented whenever the user tries to access a feature that requires an account.
//
//  Layout:
//    ╔══════════════════════════════╗
//    ║  Scripture Scribe logo/title ║
//    ║  [Email]                     ║
//    ║  [Password]                  ║
//    ║  [Display Name] ← sign up   ║
//    ║  [Sign In / Sign Up button]  ║
//    ║  ─── or ───                  ║
//    ║  [Sign in with Apple]        ║
//    ║  Toggle: Already have acct? ║
//    ╚══════════════════════════════╝
//

import AuthenticationServices
import SwiftUI

struct AuthView: View {

    @EnvironmentObject var authVM:       AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUp      = false
    @State private var email         = ""
    @State private var password      = ""
    @State private var displayName   = ""

    // Controls whether the password field hides its text
    @State private var showPassword  = false

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // ── Logo area ─────────────────────────────────────
                        VStack(spacing: 6) {
                            Image(systemName: "book.pages.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(themeManager.currentTheme.primary)
                            Text("Scripture Scribe")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(themeManager.currentTheme.text)
                            Text(isSignUp ? "Create your account" : "Welcome back")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                        }
                        .padding(.top, 32)

                        // ── Form fields ───────────────────────────────────
                        VStack(spacing: 14) {

                            // Display name (sign-up only)
                            if isSignUp {
                                fieldRow(
                                    icon: "person.fill",
                                    placeholder: "Display name",
                                    text: $displayName
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .onChange(of: displayName) { _, newValue in
                                    if newValue.count > 40 { displayName = String(newValue.prefix(40)) }
                                }
                            }

                            fieldRow(
                                icon: "envelope.fill",
                                placeholder: "Email address",
                                text: $email
                            )
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)

                            // Password with show/hide toggle
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .frame(width: 20)
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textInputAutocapitalization(.never)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                }
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(themeManager.currentTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.currentTheme.border, lineWidth: 1)
                            )
                        }

                        // ── Error message ─────────────────────────────────
                        if let err = authVM.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // ── Primary action button ─────────────────────────
                        Button {
                            Task {
                                if isSignUp {
                                    await authVM.signUp(
                                        email: email,
                                        password: password,
                                        displayName: displayName
                                    )
                                } else {
                                    await authVM.signIn(email: email, password: password)
                                }
                                if authVM.isSignedIn { dismiss() }
                            }
                        } label: {
                            Group {
                                if authVM.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(formIsValid ? themeManager.currentTheme.primary : themeManager.currentTheme.border)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!formIsValid || authVM.isLoading)

                        // ── Forgot Password (sign-in only) ───────────────
                        if !isSignUp {
                            Button {
                                Task {
                                    await authVM.resetPassword(email: email)
                                }
                            } label: {
                                Text("Forgot Password?")
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.currentTheme.primary)
                            }
                            .disabled(authVM.isLoading || !email.contains("@"))
                        }

                        // ── Divider ───────────────────────────────────────
                        HStack {
                            Rectangle().frame(height: 1).foregroundStyle(themeManager.currentTheme.border)
                            Text("or").font(.caption).foregroundStyle(themeManager.currentTheme.textSecondary)
                            Rectangle().frame(height: 1).foregroundStyle(themeManager.currentTheme.border)
                        }

                        // ── Sign in with Google ───────────────────────────
                        Button {
                            Task {
                                await authVM.signInWithGoogle()
                                if authVM.isSignedIn { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                // Google "G" represented as a styled circle
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 24, height: 24)
                                    Text("G")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                                }
                                Text(isSignUp ? "Sign up with Google" : "Sign in with Google")
                                    .font(.body.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(authVM.isLoading)

                        // ── Sign in with Apple ────────────────────────────
                        SignInWithAppleButton(
                            isSignUp ? .signUp : .signIn,
                            onRequest: { request in
                                let hashedNonce = authVM.startAppleSignIn()
                                request.requestedScopes = [.fullName, .email]
                                request.nonce = hashedNonce
                            },
                            onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    guard let credential = authorization.credential
                                        as? ASAuthorizationAppleIDCredential else { return }
                                    Task {
                                        await authVM.completeAppleSignIn(credential: credential)
                                        if authVM.isSignedIn { dismiss() }
                                    }
                                case .failure(let error):
                                    // User tapped "X" on the Apple sheet — not a real error
                                    let nsError = error as NSError
                                    if nsError.code == ASAuthorizationError.canceled.rawValue { break }
                                    authVM.errorMessage = error.userMessage
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(
                            ["Midnight", "Forest", "Royal"].contains(themeManager.currentTheme.name)
                                ? .white : .black
                        )
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        // ── Toggle sign in / sign up ──────────────────────
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSignUp.toggle()
                                authVM.errorMessage = nil
                            }
                        } label: {
                            Text(isSignUp
                                 ? "Already have an account? Sign In"
                                 : "Don't have an account? Sign Up")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.primary)
                        }
                        // ── Legal links ──────────────────────────────
                        VStack(spacing: 4) {
                            Text("By continuing, you agree to our")
                                .font(.caption2)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                            HStack(spacing: 4) {
                                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                Text("and")
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                Link("Terms of Service", destination: AppConfig.termsOfServiceURL)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(themeManager.currentTheme.primary)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 28)
                    .animation(.easeInOut(duration: 0.2), value: isSignUp)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isSignUp ? "Sign Up" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { authVM.errorMessage = nil }
        .alert("Check Your Email", isPresented: $authVM.didSendResetEmail) {
            Button("OK") { }
        } message: {
            Text("If an account exists for \(email), a password reset link has been sent.")
        }
    }

    // MARK: - Helpers

    private var formIsValid: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passOK  = password.count >= 6
        let nameOK  = !isSignUp || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passOK && nameOK
    }

    @ViewBuilder
    private func fieldRow(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(themeManager.currentTheme.primary)
                .frame(width: 20)
            TextField(placeholder, text: text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.border, lineWidth: 1)
        )
    }
}
