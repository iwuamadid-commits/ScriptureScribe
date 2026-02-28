//
//  PostCardView.swift
//  ScriptureScribe
//
//  One card in the community feed.
//  Shows the author, verse (if any), reflection text, timestamp, and comment count.
//  Tap to open comments. The author can long-press to delete their own post.
//  The verse reference badge is a tappable link that opens that chapter in the Reader.
//

import SwiftUI

struct PostCardView: View {

    let post:          Post
    let currentUserId: String?
    let isLiked:       Bool
    let onLike:        () -> Void
    let onEdit:        () -> Void
    let onDelete:      () -> Void
    let onTap:         () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var appNav:       AppNavigation
    @State private var showDeleteConfirm = false
    @State private var showHeartAnimation = false

    private var postShareText: String {
        let link = "scripturescribe://post/\(post.id)"
        var parts: [String] = []
        if !post.verseRef.isEmpty { parts.append(post.verseRef) }
        if !post.verseText.isEmpty { parts.append("\"\(post.verseText)\"") }
        let limit = 200
        if post.text.count > limit {
            let trimmed = String(post.text.prefix(limit))
            let preview = trimmed.lastIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed
            parts.append("\(preview)...")
        } else {
            parts.append(post.text)
        }
        parts.append("— \(post.displayName) on Scripture Scribe")
        if post.text.count > limit {
            parts.append("Read more in Scripture Scribe:\n\(link)")
        } else {
            parts.append(link)
        }
        return parts.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Author row ────────────────────────────────────────────
            HStack {
                UserAvatarView(displayName: post.displayName, photoURL: post.photoURL, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text(post.createdAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                Spacer()
            }

            // ── Verse reference — tappable link to the Reader ─────────
            if !post.verseRef.isEmpty {
                Button {
                    if let chId = BibleReferenceParser.chapterId(from: post.verseRef) {
                        appNav.pendingVerseNumber = BibleReferenceParser.verseNumber(from: post.verseRef)
                        appNav.pendingChapterId   = chId
                        appNav.selectedTab        = 0
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption)
                        Text(post.verseRef)
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(themeManager.currentTheme.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // ── Verse text (optional) ─────────────────────────────────
            if !post.verseText.isEmpty {
                Text(post.verseText)
                    .font(.footnote.italic())
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                    .lineLimit(3)
            }

            // ── Reflection text ───────────────────────────────────────
            Text(post.text)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.text)
                .multilineTextAlignment(.leading)

            // ── Action row: ♥ Like + 💬 Comment ──────────────────────
            HStack(spacing: 16) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.subheadline)
                            .foregroundStyle(isLiked ? Color.red : themeManager.currentTheme.textSecondary)
                        if post.likeCount > 0 {
                            Text("\(post.likeCount)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isLiked ? Color.red : themeManager.currentTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(currentUserId == nil)

                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.subheadline)
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)

                ShareLink(item: postShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(themeManager.currentTheme.border, lineWidth: 1)
        )
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
                .font(.system(size: 45))
                .foregroundStyle(Color.red.opacity(0.85))
                .scaleEffect(showHeartAnimation ? 1.0 : 0.3)
                .opacity(showHeartAnimation ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showHeartAnimation)
                .allowsHitTesting(false)
        }
        .contextMenu {
            ShareLink(item: postShareText) {
                Label("Share Post", systemImage: "square.and.arrow.up")
            }
            if currentUserId == post.userId {
                Button { onEdit() } label: {
                    Label("Edit Post", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Date Formatter Helper

private extension Date {
    var relativeFormatted: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60         { return "just now" }
        if seconds < 3600       { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400      { return "\(Int(seconds / 3600))h ago" }
        if seconds < 86400 * 7  { return "\(Int(seconds / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
