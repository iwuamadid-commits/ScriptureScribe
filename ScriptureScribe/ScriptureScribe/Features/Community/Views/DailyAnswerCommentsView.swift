//
//  DailyAnswerCommentsView.swift
//  ScriptureScribe
//
//  Sheet showing a daily answer at the top with community comments below.
//  Users can read comments without an account; posting a comment requires sign-in.
//  Supports liking, replying-to, editing, and deleting comments.
//

import SwiftUI

struct DailyAnswerCommentsView: View {

    let answer:      DailyAnswer
    let currentUser: AppUser?

    @EnvironmentObject var themeManager: ThemeManager
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
    @State private var showActionError     = false

    private let firestore = FirestoreService()

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Scrollable area ───────────────────────────────
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            // The original answer
                            answerHeader
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

                    // ── Reply input (signed-in users only) ────────────
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
                                    ? "Reply to @\(replyingTo?.displayName ?? "")\u{2026}"
                                    : "Add a reply\u{2026}",
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
                                .onChange(of: commentText) { _, newValue in
                                    if newValue.count > 2000 { commentText = String(newValue.prefix(2000)) }
                                }

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
        .alert("Something went wrong", isPresented: $showActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please check your connection and try again.")
        }
    }

    // MARK: - Answer Header

    private var answerHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatarView(displayName: answer.displayName, photoURL: answer.photoURL, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(answer.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Spacer()
                    Text(answer.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                Text(answer.text)
                    .font(.body)
                    .foregroundStyle(themeManager.currentTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                // Like count badge
                if answer.likeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.red.opacity(0.8))
                        Text("\(answer.likeCount)")
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadComments() async {
        isLoading = true
        comments  = (try? await firestore.fetchAnswerComments(answerId: answer.id)) ?? []
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
            postId:          answer.id,
            userId:          user.id,
            displayName:     user.displayName,
            photoURL:        user.photoURL,
            text:            finalText,
            parentCommentId: replyingTo?.id
        )
        do {
            try await firestore.addAnswerComment(comment, answerId: answer.id)
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
        if wasLiked { likedCommentIds.remove(comment.id) }
        else        { likedCommentIds.insert(comment.id) }
        if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[idx].likeCount += wasLiked ? -1 : 1
        }
        do {
            try await firestore.toggleCommentLike(
                parentCollection: "dailyAnswers", parentId: answer.id,
                commentId: comment.id, userId: uid, isLiked: wasLiked
            )
        } catch is CancellationError {
        } catch {
            if wasLiked { likedCommentIds.insert(comment.id) }
            else        { likedCommentIds.remove(comment.id) }
            if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[idx].likeCount += wasLiked ? 1 : -1
            }
        }
    }

    private func editComment(_ comment: Comment, newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let originalText = comment.text
        if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[idx].text = trimmed
        }
        do {
            try await firestore.updateComment(
                parentCollection: "dailyAnswers", parentId: answer.id,
                commentId: comment.id, text: trimmed
            )
        } catch is CancellationError {
        } catch {
            if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[idx].text = originalText
            }
            showActionError = true
        }
    }

    private func deleteComment(_ comment: Comment) async {
        let snapshot = comment
        let originalIndex = comments.firstIndex(where: { $0.id == comment.id })
        withAnimation(.easeOut(duration: 0.35)) {
            comments.removeAll { $0.id == comment.id }
        }
        do {
            try await firestore.deleteComment(
                parentCollection: "dailyAnswers", parentId: answer.id,
                commentId: comment.id
            )
        } catch is CancellationError {
        } catch {
            if let idx = originalIndex, idx <= comments.count {
                comments.insert(snapshot, at: idx)
            } else {
                comments.append(snapshot)
            }
            showActionError = true
        }
    }
}
