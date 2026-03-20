//
//  PrayerViewModel.swift
//  ScriptureScribe
//
//  Manages the Prayer Requests section of the Community tab.
//  Tracks which requests the current user has prayed for so the 🙏
//  button state is correct even after the app is relaunched.
//

import Combine
import FirebaseFirestore
import SwiftUI

@MainActor
final class PrayerViewModel: ObservableObject {

    @Published var requests:     [PrayerRequest] = []
    @Published var prayingIds:   Set<String>     = []   // request IDs this user has prayed for
    @Published var reportedIds:  Set<String>     = []
    @Published var isLoading:    Bool            = false
    @Published var errorMessage: String?         = nil

    private let firestore     = FirestoreService()
    private var feedListener: ListenerRegistration?

    // MARK: - Feed

    func startListening(userId: String?) {
        guard feedListener == nil else { return }
        isLoading    = true
        feedListener = firestore.listenToPrayerFeed { [weak self] requests in
            guard let self else { return }
            let isAdmin = AdminManager.isAdmin(userId)
            self.requests = isAdmin ? requests : requests.filter { req in
                let reported = req.reportedBy
                if reported.count >= 5 { return false }
                if let uid = userId, reported.contains(uid) { return false }
                return true
            }
            self.isLoading = false
        }
        // Load which requests this user has already prayed for
        if let uid = userId {
            Task {
                let ids = (try? await firestore.fetchPrayingIds(userId: uid)) ?? []
                prayingIds = Set(ids)
            }
        }
    }

    func stopListening() {
        feedListener?.remove()
        feedListener = nil
    }

    // MARK: - Create Request

    func createRequest(
        userId:      String,
        displayName: String,
        photoURL:    String?,
        text:        String
    ) async {
        let request = PrayerRequest(
            userId:      userId,
            displayName: displayName,
            photoURL:    photoURL,
            text:        text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try await firestore.createPrayerRequest(request)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Edit Request

    func editRequest(_ request: PrayerRequest, newText: String) async {
        do {
            try await firestore.updatePrayerRequest(id: request.id, text: newText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.userMessage
        }
    }

    func adminEditRequest(_ request: PrayerRequest, text: String, displayName: String) async {
        var fields: [String: Any] = [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != request.text              { fields["text"]        = trimmed }
        if displayName != request.displayName   { fields["displayName"] = displayName }
        guard !fields.isEmpty else { return }
        do {
            try await firestore.updatePrayerRequestFields(id: request.id, fields: fields)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Report Request

    func reportRequest(id: String, userId: String) async {
        reportedIds.insert(id)
        withAnimation(.easeOut(duration: 0.35)) {
            requests.removeAll { $0.id == id }
        }
        do {
            try await firestore.reportContent(collection: "prayerRequests", documentId: id, userId: userId)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Delete Request

    func deleteRequest(_ request: PrayerRequest) async {
        withAnimation(.easeOut(duration: 0.35)) {
            requests.removeAll { $0.id == request.id }
        }
        do {
            try await firestore.deletePrayerRequest(id: request.id)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Toggle 🙏

    func togglePraying(request: PrayerRequest, userId: String) async {
        let alreadyPraying = prayingIds.contains(request.id)
        // Optimistically update local state so the button feels instant
        if alreadyPraying {
            prayingIds.remove(request.id)
        } else {
            prayingIds.insert(request.id)
        }
        do {
            try await firestore.togglePraying(
                requestId:  request.id,
                userId:     userId,
                isPraying:  alreadyPraying
            )
        } catch {
            // Revert the optimistic update if the server call failed
            if alreadyPraying {
                prayingIds.insert(request.id)
            } else {
                prayingIds.remove(request.id)
            }
            errorMessage = error.userMessage
        }
    }
}
