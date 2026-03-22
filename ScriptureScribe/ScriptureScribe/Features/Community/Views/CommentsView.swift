//
//  CommentsView.swift
//  ScriptureScribe
//
//  Sheet that shows the full post at the top with all replies below it.
//  A text field at the bottom lets the user add their own comment.
//  Supports liking, replying-to, editing, and deleting comments.
//

import SwiftUI

struct CommentsView: View {

    let post:          Post
    let currentUser:   AppUser?

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var appNav:       AppNavigation
    @Environment(\.dismiss) private var dismiss

    @State private var comments:           [Comment] = []
    @State private var commentText         = ""
    @State private var isLoading           = false
    @State private var isSending           = false
    @State private var likedCommentIds:    Set<String> = []
    @State private var replyingTo:         Comment? = nil
    @State private var editingComment:     Comment? = nil
    @State private var collapsedThreadIds: Set<String> = []
    @State private var showSendError      = false

    private let firestore = FirestoreService()

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Scrollable area ───────────────────────────────
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            // The original post
                            postHeader
                                .padding(.horizontal, 16)
                                .padding(.top, 16)

                            Divider()
                                .background(themeManager.currentTheme.border)
                                .padding(.horizontal, 16)

                            // Comments list
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else if comments.isEmpty {
                                Text("No replies yet. Be the first!")
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else {
                                let topLevel = comments.filter { $0.parentCommentId == nil }
                                ForEach(topLevel) { parent in
                                    VStack(alignment: .leading, spacing: 0) {
                                        // Parent comment
                                        CommentRowView(
                                            comment:       parent,
                                            currentUserId: currentUser?.id,
                                            isLiked:       likedCommentIds.contains(parent.id),
                                            onLike:        { Task { await toggleCommentLike(parent) } },
                                            onReply:       { replyingTo = parent },
                                            onEdit:        { editingComment = parent },
                                            onDelete:      { Task { await deleteComment(parent) } }
                                        )
                                        .padding(.horizontal, 16)

                                        // Child replies
                                        let children = comments.filter { $0.parentCommentId == parent.id }
                                        if !children.isEmpty {
                                            let isCollapsed = collapsedThreadIds.contains(parent.id)
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if isCollapsed { collapsedThreadIds.remove(parent.id) }
                                                    else           { collapsedThreadIds.insert(parent.id) }
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                                        .font(.caption2)
                                                    Text(isCollapsed
                                                        ? "Show \(children.count) \(children.count == 1 ? "reply" : "replies")"
                                                        : "Hide \(children.count == 1 ? "reply" : "replies")")
                                                        .font(.caption2.weight(.medium))
                                                }
                                                .foregroundStyle(themeManager.currentTheme.primary)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 54)
                                            .padding(.top, 2)

                                            if !isCollapsed {
                                                ForEach(children) { child in
                                                    CommentRowView(
                                                        comment:       child,
                                                        currentUserId: currentUser?.id,
                                                        isLiked:       likedCommentIds.contains(child.id),
                                                        isReply:       true,
                                                        onLike:        { Task { await toggleCommentLike(child) } },
                                                        onReply:       { replyingTo = parent },
                                                        onEdit:        { editingComment = child },
                                                        onDelete:      { Task { await deleteComment(child) } }
                                                    )
                                                    .padding(.horizontal, 16)
                                                    .transition(.opacity)
                                                }
                                            }
                                        }
                                    }
                                    .transition(.opacity)
                                }
                                .padding(.bottom, 8)
                            }
                        }
                    }

                    // ── Reply input ────────────────────────────────────
                    if currentUser != nil {
                        Divider().background(themeManager.currentTheme.border)

                        // Reply-to chip
                        if let replying = replyingTo {
                            HStack {
                                Text("Replying to @\(replying.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                Spacer()
                                Button { replyingTo = nil } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        }

                        HStack(spacing: 10) {
                            TextField(
                                replyingTo != nil
                                    ? "Reply to @\(replyingTo?.displayName ?? "")…"
                                    : "Add a reply…",
                                text: $commentText,
                                axis: .vertical
                            )
                                .lineLimit(1...4)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(themeManager.currentTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(themeManager.currentTheme.border, lineWidth: 1)
                                )

                            Button {
                                Task { await sendComment() }
                            } label: {
                                Group {
                                    if isSending {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .background(commentText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? themeManager.currentTheme.border
                                    : themeManager.currentTheme.primary)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                            }
                            .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(themeManager.currentTheme.surface)
                    }
                }
            }
            .navigationTitle("Replies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
            .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $editingComment) { comment in
                EditTextSheet(title: "Edit Reply", originalText: comment.text) { newText in
                    Task { await editComment(comment, newText: newText) }
                }
            }
        }
        .task { await loadComments() }
        .alert("Couldn't send comment", isPresented: $showSendError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please check your connection and try again.")
        }
    }

    // MARK: - Post Header

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                UserAvatarView(displayName: post.displayName, photoURL: post.photoURL, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            }
            if !post.verseRef.isEmpty {
                Button {
                    if let chId = BibleReferenceParser.chapterId(from: post.verseRef) {
                        dismiss()
                        appNav.pendingVerseNumber = BibleReferenceParser.verseNumber(from: post.verseRef)
                        appNav.pendingChapterId   = chId
                        appNav.selectedTab        = 0
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption)
                        Text(post.verseRef)
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(themeManager.currentTheme.primary)
                }
                .buttonStyle(.plain)
            }
            if !post.verseText.isEmpty {
                Text(post.verseText)
                    .font(.footnote.italic())
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            }
            Text(post.text)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.text)
        }
    }

    // MARK: - Actions

    private func loadComments() async {
        isLoading = true
        comments = (try? await firestore.fetchComments(postId: post.id)) ?? []
        if let uid = currentUser?.id {
            likedCommentIds = Set((try? await firestore.fetchLikedCommentIds(userId: uid)) ?? [])
        }
        isLoading = false
    }

    private func sendComment() async {
        guard let user = currentUser else { return }
        let trimmed = commentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSending = true
        let finalText = replyingTo != nil
            ? "@\(replyingTo?.displayName ?? "") \(trimmed)"
            : trimmed

        let comment = Comment(
            postId:          post.id,
            userId:          user.id,
            displayName:     user.displayName,
            photoURL:        user.photoURL,
            text:            finalText,
            parentCommentId: replyingTo?.id
        )
        do {
            try await firestore.addComment(comment)
            commentText = ""
            replyingTo  = nil
            comments.append(comment)
        } catch is CancellationError {
        } catch {
            showSendError = true
        }
        isSending = false
    }

    private func toggleCommentLike(_ comment: Comment) async {
        guard let uid = currentUser?.id else { return }
        let wasLiked = likedCommentIds.contains(comment.id)
        // Optimistic update
        if wasLiked { likedCommentIds.remove(comment.id) }
        else        { likedCommentIds.insert(comment.id) }
        if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[idx].likeCount += wasLiked ? -1 : 1
        }
        try? await firestore.toggleCommentLike(
            parentCollection: "posts", parentId: post.id,
            commentId: comment.id, userId: uid, isLiked: wasLiked
        )
    }

    private func editComment(_ comment: Comment, newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await firestore.updateComment(
            parentCollection: "posts", parentId: post.id,
            commentId: comment.id, text: trimmed
        )
        if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[idx].text = trimmed
        }
    }

    private func deleteComment(_ comment: Comment) async {
        try? await firestore.deleteComment(
            parentCollection: "posts", parentId: post.id,
            commentId: comment.id
        )
        withAnimation(.easeOut(duration: 0.35)) {
            comments.removeAll { $0.id == comment.id }
        }
    }
}
