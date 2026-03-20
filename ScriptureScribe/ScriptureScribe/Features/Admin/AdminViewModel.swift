//
//  AdminViewModel.swift
//  ScriptureScribe
//
//  Fetches all community content that has been reported (reportedBy is non-empty)
//  across posts, gratitude posts, prayer requests, and daily answers.
//  Provides actions to remove content or clear its reports.
//

import Combine
import FirebaseFirestore
import SwiftUI

/// Represents one piece of flagged content, regardless of its source collection.
struct FlaggedItem: Identifiable {
    let id: String
    let collection: String   // Firestore collection name
    let contentType: String  // Display label: "post", "gratitude", "prayer", "answer"
    let authorId: String
    let authorName: String
    let textPreview: String
    let reportCount: Int
    let reportedBy: [String]
    let createdAt: Date
}

@MainActor
final class AdminViewModel: ObservableObject {

    @Published var flaggedItems: [FlaggedItem] = []
    @Published var isLoading = false
    @Published var totalUsers = 0

    private let db = Firestore.firestore()

    // MARK: - Fetch

    func refresh() async {
        isLoading = true
        async let posts      = fetchFlagged(collection: "posts",           type: "post")
        async let gratitude   = fetchFlagged(collection: "gratitudePosts", type: "gratitude")
        async let prayers     = fetchFlagged(collection: "prayerRequests", type: "prayer")
        async let answers     = fetchFlagged(collection: "dailyAnswers",   type: "answer")
        async let userCount   = fetchUserCount()

        let all = await (posts + gratitude + prayers + answers)
        // Sort by report count descending, then by most recent
        flaggedItems = all.sorted {
            if $0.reportCount != $1.reportCount { return $0.reportCount > $1.reportCount }
            return $0.createdAt > $1.createdAt
        }
        totalUsers = await userCount
        isLoading = false
    }

    // MARK: - Actions

    /// Permanently deletes the flagged content from Firestore.
    func deleteItem(_ item: FlaggedItem) async {
        do {
            try await db.collection(item.collection).document(item.id).delete()
            flaggedItems.removeAll { $0.id == item.id }
        } catch {
            print("[Admin] Failed to delete \(item.collection)/\(item.id): \(error)")
        }
    }

    /// Marks the content as reviewed by an admin. The reportedBy array stays
    /// intact so reporters never see the content again, but it leaves the
    /// admin queue since it's been reviewed and deemed acceptable.
    func dismissReports(_ item: FlaggedItem) async {
        do {
            try await db.collection(item.collection).document(item.id).updateData([
                "adminReviewed": true
            ])
            flaggedItems.removeAll { $0.id == item.id }
        } catch {
            print("[Admin] Failed to dismiss reports for \(item.collection)/\(item.id): \(error)")
        }
    }

    // MARK: - Private

    private func fetchFlagged(collection: String, type: String) async -> [FlaggedItem] {
        do {
            // Firestore: "where reportedBy array is not empty" isn't directly supported,
            // so we fetch docs where reportedBy exists and filter client-side.
            // For small-to-medium apps this is fine. At scale, use a Cloud Function
            // to maintain a separate "flagged" collection.
            let snapshot = try await db.collection(collection)
                .order(by: "createdAt", descending: true)
                .limit(to: 500)
                .getDocuments()

            return snapshot.documents.compactMap { doc -> FlaggedItem? in
                let data = doc.data()
                guard let reported = data["reportedBy"] as? [String],
                      !reported.isEmpty else { return nil }

                // Skip items already reviewed by admin, unless they've
                // crossed the 5-report threshold (those always need attention).
                let reviewed = data["adminReviewed"] as? Bool ?? false
                if reviewed && reported.count < 5 { return nil }

                let text = (data["text"] as? String) ?? (data["body"] as? String) ?? ""
                let name = (data["displayName"] as? String) ?? "Unknown"
                let userId = (data["userId"] as? String) ?? ""
                let created = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

                return FlaggedItem(
                    id: doc.documentID,
                    collection: collection,
                    contentType: type,
                    authorId: userId,
                    authorName: name,
                    textPreview: String(text.prefix(200)),
                    reportCount: reported.count,
                    reportedBy: reported,
                    createdAt: created
                )
            }
        } catch {
            print("[Admin] Failed to fetch \(collection): \(error)")
            return []
        }
    }

    private func fetchUserCount() async -> Int {
        do {
            let snapshot = try await db.collection("users").getDocuments()
            return snapshot.count
        } catch {
            print("[Admin] Failed to fetch user count: \(error)")
            return 0
        }
    }
}
