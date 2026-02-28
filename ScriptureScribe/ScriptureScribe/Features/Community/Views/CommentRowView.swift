//
//  CommentRowView.swift
//  ScriptureScribe
//
//  Shared comment row used across all 4 comment sheets.
//  Shows avatar, author name, text, like button, reply button,
//  and a context menu to edit/delete your own comments.
//

import SwiftUI

struct CommentRowView: View {

    let comment:       Comment
    let currentUserId: String?
    let isLiked:       Bool
    let isReply:       Bool          // true = child comment (indented)
    let onLike:        () -> Void
    let onReply:       () -> Void
    let onEdit:        () -> Void
    let onDelete:      () -> Void

    init(
        comment:       Comment,
        currentUserId: String?,
        isLiked:       Bool,
        isReply:       Bool = false,
        onLike:        @escaping () -> Void,
        onReply:       @escaping () -> Void,
        onEdit:        @escaping () -> Void,
        onDelete:      @escaping () -> Void
    ) {
        self.comment       = comment
        self.currentUserId = currentUserId
        self.isLiked       = isLiked
        self.isReply       = isReply
        self.onLike        = onLike
        self.onReply       = onReply
        self.onEdit        = onEdit
        self.onDelete      = onDelete
    }

    @EnvironmentObject var themeManager: ThemeManager
    @State private var showDeleteConfirm = false
    @State private var showHeartAnimation = false

    private var shareText: String {
        "\(comment.text)\n\n— \(comment.displayName) on Scripture Scribe\n\nscripturescribe://comment/\(comment.postId)"
    }

    private var avatarSize: CGFloat { isReply ? 22 : 28 }
    private var actionLeading: CGFloat { isReply ? 32 : 38 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Author row ──────────────────────────────────────
            HStack(alignment: .top, spacing: isReply ? 8 : 10) {
                UserAvatarView(displayName: comment.displayName, photoURL: comment.photoURL, size: avatarSize)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(comment.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.currentTheme.text)
                        Spacer()
                        Text(comment.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    Text(comment.text)
                        .font(isReply ? .caption : .subheadline)
                        .foregroundStyle(themeManager.currentTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ── Action row: Like + Reply ────────────────────────
            HStack(spacing: 16) {

                // Like button
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(isLiked
                                ? Color.red
                                : themeManager.currentTheme.textSecondary)
                        if comment.likeCount > 0 {
                            Text("\(comment.likeCount)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(isLiked
                                    ? Color.red
                                    : themeManager.currentTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(currentUserId == nil)

                // Reply button
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(currentUserId == nil)

                Spacer()
            }
            .padding(.leading, actionLeading)
        }
        .padding(.leading, isReply ? 36 : 0)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard currentUserId != nil else { return }
            if !isLiked { onLike() }
            showHeartAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showHeartAnimation = false
            }
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 35))
                .foregroundStyle(Color.red.opacity(0.85))
                .scaleEffect(showHeartAnimation ? 1.0 : 0.3)
                .opacity(showHeartAnimation ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showHeartAnimation)
                .allowsHitTesting(false)
        }
        .contextMenu {
            ShareLink(item: shareText) {
                Label("Share Reply", systemImage: "square.and.arrow.up")
            }
            if currentUserId == comment.userId {
                Button { onEdit() } label: {
                    Label("Edit Reply", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Reply", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete your reply?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
