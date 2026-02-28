//
//  DailyAnswerCardView.swift
//  ScriptureScribe
//
//  One answer in the Daily Question section.
//  Shows the answer text with a ♥ like button and a 💬 comment count button.
//

import SwiftUI

struct DailyAnswerCardView: View {

    let answer:        DailyAnswer
    let currentUserId: String?
    let isLiked:       Bool        // whether the current user has liked this answer
    let onLike:        () -> Void
    let onEdit:        () -> Void
    let onComment:     () -> Void
    let onDelete:      () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @State private var showDeleteConfirm = false
    @State private var showHeartAnimation = false

    private var shareText: String {
        let link = "scripturescribe://answer/\(answer.id)"
        let limit = 200
        if answer.text.count > limit {
            let trimmed = String(answer.text.prefix(limit))
            let preview = trimmed.lastIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed
            return "\(preview)...\n\n— \(answer.displayName) on Scripture Scribe\n\nRead more in Scripture Scribe:\n\(link)"
        }
        return "\(answer.text)\n\n— \(answer.displayName) on Scripture Scribe\n\n\(link)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Author row ────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                UserAvatarView(displayName: answer.displayName, photoURL: answer.photoURL, size: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(answer.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.currentTheme.text)
                        Spacer()
                        Text(answer.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    Text(answer.text)
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ── Action row: ♥ Like + 💬 Comment ──────────────────────
            HStack(spacing: 16) {

                // ♥ Like button
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.subheadline)
                            .foregroundStyle(isLiked
                                ? Color.red
                                : themeManager.currentTheme.textSecondary)
                        if answer.likeCount > 0 {
                            Text("\(answer.likeCount)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isLiked
                                    ? Color.red
                                    : themeManager.currentTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(currentUserId == nil)

                // 💬 Comments button
                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.subheadline)
                        if answer.commentCount > 0 {
                            Text("\(answer.commentCount)")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)

                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(themeManager.currentTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
            ShareLink(item: shareText) {
                Label("Share Answer", systemImage: "square.and.arrow.up")
            }
            if currentUserId == answer.userId {
                Button { onEdit() } label: {
                    Label("Edit Answer", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Answer", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete your answer?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
