//
//  PrayerCardView.swift
//  ScriptureScribe
//
//  One card in the Prayer Requests feed.
//  Shows the prayer request text, a 🙏 praying count button, and a comment count button.
//

import SwiftUI

struct PrayerCardView: View {

    let request:      PrayerRequest
    let currentUser:  AppUser?
    let isPraying:    Bool       // whether the current user has already tapped 🙏
    let onPray:       () -> Void
    let onEdit:       () -> Void
    let onComment:    () -> Void
    let onDelete:     () -> Void
    let onReport:     () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @State private var showDeleteConfirm  = false
    @State private var showReportConfirm  = false
    @State private var showPrayAnimation  = false

    private var shareText: String {
        let link = "https://apps.apple.com/us/app/the-scripture-scribe/id6761033279"
        let limit = 200
        if request.text.count > limit {
            let trimmed = String(request.text.prefix(limit))
            let preview = trimmed.lastIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed
            return "Prayer Request from \(request.displayName):\n\n\(preview)...\n\nRead more in Scripture Scribe:\n\(link)"
        }
        return "Prayer Request from \(request.displayName):\n\n\(request.text)\n\nShared from Scripture Scribe\n\n\(link)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Author row ────────────────────────────────────────────
            HStack(spacing: 10) {
                UserAvatarView(displayName: request.displayName, photoURL: request.photoURL, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(request.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text(request.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "hands.and.sparkles")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.primary.opacity(0.6))
            }

            // ── Request text ──────────────────────────────────────────
            Text(request.text)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.text)
                .multilineTextAlignment(.leading)

            // ── Action row: 🙏 Praying + 💬 Comments ─────────────────
            HStack(spacing: 16) {

                // 🙏 Praying button
                Button(action: onPray) {
                    HStack(spacing: 5) {
                        Text("🙏")
                            .font(.body)
                        if request.prayingCount > 0 {
                            Text("\(request.prayingCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isPraying
                                    ? themeManager.currentTheme.primary
                                    : themeManager.currentTheme.textSecondary)
                        }
                        Text(isPraying ? "Praying" : "Pray")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isPraying
                                ? themeManager.currentTheme.primary
                                : themeManager.currentTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isPraying
                            ? themeManager.currentTheme.primary.opacity(0.12)
                            : themeManager.currentTheme.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isPraying
                                    ? themeManager.currentTheme.primary.opacity(0.4)
                                    : themeManager.currentTheme.border,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(currentUser == nil)

                // 💬 Comments button
                Button(action: onComment) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.subheadline)
                        if request.commentCount > 0 {
                            Text("\(request.commentCount)")
                                .font(.subheadline.weight(.medium))
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
            guard currentUser != nil else { return }
            if !isPraying { onPray() }
            showPrayAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showPrayAnimation = false
            }
        }
        .overlay {
            Text("\u{1F64F}")
                .font(.system(size: 45))
                .scaleEffect(showPrayAnimation ? 1.0 : 0.3)
                .opacity(showPrayAnimation ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showPrayAnimation)
                .allowsHitTesting(false)
        }
        .contextMenu {
            ShareLink(item: shareText) {
                Label("Share Request", systemImage: "square.and.arrow.up")
            }
            if currentUser != nil && currentUser?.id != request.userId {
                Button(role: .destructive) { showReportConfirm = true } label: {
                    Label("Report Request", systemImage: "flag")
                }
            }
            if currentUser?.id == request.userId || AdminManager.isAdmin(currentUser?.id) {
                Button { onEdit() } label: {
                    Label("Edit Request", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Request", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this prayer request?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Report this prayer request?",
            isPresented: $showReportConfirm,
            titleVisibility: .visible
        ) {
            Button("Report", role: .destructive) { onReport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This request will be reviewed by our team and hidden from your feed.")
        }
    }
}
