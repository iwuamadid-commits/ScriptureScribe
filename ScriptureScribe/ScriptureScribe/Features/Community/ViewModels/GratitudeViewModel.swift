//
//  GratitudeViewModel.swift
//  ScriptureScribe
//
//  Manages the Gratitude section of the Community tab.
//  Handles real-time feed loading and photo upload + post creation.
//

import Combine
import FirebaseFirestore
import SwiftUI

@MainActor
final class GratitudeViewModel: ObservableObject {

    @Published var posts:              [GratitudePost] = []
    @Published var likedGratitudeIds: Set<String>     = []
    @Published var reportedIds:       Set<String>     = []
    @Published var isLoading:         Bool            = false
    @Published var isUploading:       Bool            = false
    @Published var errorMessage:      String?         = nil

    private let firestore     = FirestoreService()
    private var feedListener: ListenerRegistration?

    // MARK: - Feed

    func startListening(userId: String? = nil) {
        guard feedListener == nil else { return }
        isLoading    = true
        feedListener = firestore.listenToGratitudeFeed { [weak self] posts, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.userMessage
                self.isLoading = false
                return
            }
            let isAdmin = AdminManager.isAdmin(userId)
            self.posts = isAdmin ? posts : posts.filter { post in
                let reported = post.reportedBy
                if reported.count >= 5 { return false }
                if let uid = userId, reported.contains(uid) { return false }
                return true
            }
            self.isLoading = false
        }
        if let uid = userId {
            Task { await loadLikedIds(userId: uid) }
        }
    }

    func stopListening() {
        feedListener?.remove()
        feedListener = nil
    }

    // MARK: - Likes

    private func loadLikedIds(userId: String) async {
        let ids = (try? await firestore.fetchLikedGratitudeIds(userId: userId)) ?? []
        likedGratitudeIds = Set(ids)
    }

    func toggleLike(post: GratitudePost, userId: String) async {
        let alreadyLiked = likedGratitudeIds.contains(post.id)
        if alreadyLiked { likedGratitudeIds.remove(post.id) }
        else             { likedGratitudeIds.insert(post.id) }

        do {
            try await firestore.toggleGratitudeLike(postId: post.id, userId: userId, isLiked: alreadyLiked)
        } catch {
            if alreadyLiked { likedGratitudeIds.insert(post.id) }
            else             { likedGratitudeIds.remove(post.id) }
            errorMessage = error.userMessage
        }
    }

    // MARK: - Create Post

    /// Creates a gratitude post. If `imageData` is provided, the photo is resized,
    /// compressed, and stored as base64 directly in the Firestore document.
    func createPost(
        userId:      String,
        displayName: String,
        photoURL:    String?,
        text:        String,
        imageData:   Data?
    ) async {
        var base64: String? = nil

        if let data = imageData, let uiImage = UIImage(data: data) {
            base64 = compressForFirestore(uiImage)
        }

        let post = GratitudePost(
            userId:      userId,
            displayName: displayName,
            photoURL:    photoURL,
            imageBase64: base64,
            text:        text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try await firestore.createGratitudePost(post)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Edit Post

    func editPost(_ post: GratitudePost, newText: String) async {
        do {
            try await firestore.updateGratitudePost(id: post.id, text: newText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.userMessage
        }
    }

    func adminEditPost(_ post: GratitudePost, text: String, displayName: String) async {
        var fields: [String: Any] = [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != post.text              { fields["text"]        = trimmed }
        if displayName != post.displayName   { fields["displayName"] = displayName }
        guard !fields.isEmpty else { return }
        do {
            try await firestore.updateGratitudePostFields(id: post.id, fields: fields)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Report Post

    func reportPost(id: String, userId: String) async {
        reportedIds.insert(id)
        withAnimation(.easeOut(duration: 0.35)) {
            posts.removeAll { $0.id == id }
        }
        do {
            try await firestore.reportContent(collection: "gratitudePosts", documentId: id, userId: userId)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Delete Post

    func deletePost(_ post: GratitudePost) async {
        withAnimation(.easeOut(duration: 0.35)) {
            posts.removeAll { $0.id == post.id }
        }
        do {
            try await firestore.deleteGratitudePost(id: post.id)
        } catch {
            errorMessage = error.userMessage
        }
    }

    // MARK: - Image Compression

    /// Resizes and compresses a UIImage to a small JPEG base64 string
    /// suitable for storing directly in a Firestore document.
    private func compressForFirestore(_ image: UIImage) -> String? {
        let maxDimension: CGFloat = 600
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        guard let jpegData = resized.jpegData(compressionQuality: 0.45) else { return nil }
        return jpegData.base64EncodedString()
    }
}
