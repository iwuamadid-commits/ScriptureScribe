//
//  CommunityViewModel.swift
//  ScriptureScribe
//
//  Manages the community feed and post creation.
//  Uses a Firestore real-time listener so new posts appear instantly.
//

import Combine
import FirebaseFirestore
import SwiftUI

@MainActor
final class CommunityViewModel: ObservableObject {

    @Published var posts:         [Post]       = []
    @Published var likedPostIds:  Set<String>  = []
    @Published var isLoading:     Bool         = false
    @Published var errorMessage:  String?      = nil

    private let firestore         = FirestoreService()
    private var feedListener:     ListenerRegistration?

    // MARK: - Feed

    func startListening(userId: String? = nil) {
        guard feedListener == nil else { return }
        isLoading = true
        feedListener = firestore.listenToFeed { [weak self] posts in
            guard let self else { return }
            self.posts     = posts
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
        let ids = (try? await firestore.fetchLikedPostIds(userId: userId)) ?? []
        likedPostIds = Set(ids)
    }

    func toggleLike(post: Post, userId: String) async {
        let alreadyLiked = likedPostIds.contains(post.id)
        if alreadyLiked { likedPostIds.remove(post.id) }
        else             { likedPostIds.insert(post.id) }

        do {
            try await firestore.togglePostLike(postId: post.id, userId: userId, isLiked: alreadyLiked)
        } catch {
            // Revert on failure
            if alreadyLiked { likedPostIds.insert(post.id) }
            else             { likedPostIds.remove(post.id) }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Post

    func createPost(userId: String, displayName: String, photoURL: String?, text: String, verseRef: String, verseText: String) async {
        let post = Post(
            userId:      userId,
            displayName: displayName,
            photoURL:    photoURL,
            text:        text.trimmingCharacters(in: .whitespacesAndNewlines),
            verseRef:    verseRef,
            verseText:   verseText
        )
        do {
            try await firestore.createPost(post)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit Post

    func editPost(_ post: Post, newText: String) async {
        do {
            try await firestore.updatePost(postId: post.id, text: newText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Post

    func deletePost(_ post: Post) async {
        withAnimation(.easeOut(duration: 0.35)) {
            posts.removeAll { $0.id == post.id }
        }
        do {
            try await firestore.deletePost(postId: post.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
