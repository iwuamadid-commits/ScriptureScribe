//
//  Error+UserFriendly.swift
//  ScriptureScribe
//
//  Maps raw system/Firebase/StoreKit errors to clean, user-friendly messages.
//  The original error is logged to the console for developer debugging.
//

import Foundation

extension Error {

    /// Returns a short, user-friendly message suitable for display.
    /// Logs the raw error to the console so developers can still diagnose issues.
    var userMessage: String {
        let nsError = self as NSError

        // Log the raw error for developers
        print("[Error] \(nsError.domain) code=\(nsError.code): \(localizedDescription)")

        // ── Firebase Auth ──────────────────────────────────────────────
        if nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17008:  // invalidEmail
                return "That email address doesn't look right. Please check and try again."
            case 17009:  // wrongPassword
                return "Incorrect password. Please try again."
            case 17011:  // userNotFound
                return "No account found with that email."
            case 17007:  // emailAlreadyInUse
                return "That email is already in use. Try signing in instead."
            case 17026:  // weakPassword
                return "Password is too weak. Use at least 6 characters."
            case 17010:  // userDisabled
                return "This account has been disabled. Please contact support."
            case 17014:  // requiresRecentLogin
                return "For security, please sign in again before making this change."
            case 17020:  // networkError
                return "No internet connection. Please check your network and try again."
            case 17995:  // tooManyRequests
                return "Too many attempts. Please wait a moment and try again."
            case 17999:  // internalError
                return "Something went wrong. Please try again."
            default:
                return "Sign-in failed. Please try again."
            }
        }

        // ── Firebase Firestore ─────────────────────────────────────────
        if nsError.domain == "FIRFirestoreErrorDomain" {
            switch nsError.code {
            case 7:   // permissionDenied
                return "You don't have permission for this action."
            case 14:  // unavailable
                return "No internet connection. Please check your network and try again."
            case 4:   // deadlineExceeded
                return "Request timed out. Please try again."
            default:
                return "Something went wrong. Please try again."
            }
        }

        // ── Firebase Storage ───────────────────────────────────────────
        if nsError.domain == "FIRStorageErrorDomain" {
            switch nsError.code {
            case -13010: // objectNotFound
                return "File not found."
            case -13000: // unknown
                return "Upload failed. Please try again."
            case -13013: // quotaExceeded
                return "Storage is full. Please try again later."
            case -13030: // cancelled (user-initiated)
                return "Upload cancelled."
            case -13040: // retryLimitExceeded, likely network
                return "No internet connection. Please check your network and try again."
            default:
                return "Upload failed. Please try again."
            }
        }

        // ── StoreKit ───────────────────────────────────────────────────
        if nsError.domain == "SKErrorDomain" || nsError.domain == "StoreKitError" {
            switch nsError.code {
            case 0:  // unknown
                return "Purchase failed. Please try again."
            case 1:  // paymentCancelled (shouldn't reach here, but just in case)
                return "Purchase cancelled."
            case 2:  // paymentInvalid
                return "This purchase couldn't be completed. Please try again."
            case 3:  // paymentNotAllowed
                return "Purchases are not allowed on this device."
            default:
                return "Purchase failed. Please try again."
            }
        }

        // ── Network / URL errors ───────────────────────────────────────
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Please check your network and try again."
            case NSURLErrorTimedOut:
                return "Request timed out. Please try again."
            case NSURLErrorCancelled:
                // Shouldn't show, but guard just in case
                return "Request cancelled."
            default:
                return "Network error. Please try again."
            }
        }

        // ── Fallback ───────────────────────────────────────────────────
        return "Something went wrong. Please try again."
    }
}
