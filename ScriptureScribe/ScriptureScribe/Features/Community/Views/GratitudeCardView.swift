//
//  GratitudeCardView.swift
//  ScriptureScribe
//
//  One card in the Gratitude feed.
//  Shows: author name, date, text, optional gratitude photo.
//

import SwiftUI

struct GratitudeCardView: View {

    let post:          GratitudePost
    let currentUserId: String?
    let isLiked:       Bool
    let onLike:        () -> Void
    let onEdit:        () -> Void
    let onComment:     () -> Void
    let onDelete:      () -> Void
    let onReport:      () -> Void

    @EnvironmentObject var themeManager: ThemeManager
    @State private var showDeleteConfirm  = false
    @State private var showReportConfirm  = false
    @State private var showFullImage      = false
    @State private var showHeartAnimation = false

    private var shareText: String {
        let link = "scripturescribe://gratitude/\(post.id)"
        let limit = 200
        if post.text.count > limit {
            let trimmed = String(post.text.prefix(limit))
            let preview = trimmed.lastIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed
            return "\(preview)...\n\nShared by \(post.displayName) on Scripture Scribe\n\nRead more in Scripture Scribe:\n\(link)"
        }
        return "\(post.text)\n\nShared by \(post.displayName) on Scripture Scribe\n\n\(link)"
    }

    /// Decodes the inline base64 image (if present).
    private var decodedImage: UIImage? {
        guard let base64 = post.imageBase64,
              let data = Data(base64Encoded: base64),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Author row ────────────────────────────────────────────
            HStack(spacing: 10) {
                UserAvatarView(displayName: post.displayName, photoURL: post.photoURL, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                Spacer()
                // Gratitude leaf icon
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(Color.green.opacity(0.7))
            }

            // ── Text ──────────────────────────────────────────────────
            Text(post.text)
                .font(.body)
                .foregroundStyle(themeManager.currentTheme.text)
                .multilineTextAlignment(.leading)

            // ── Optional gratitude photo (small thumbnail) ─────────────
            if let uiImage = decodedImage {
                Button { showFullImage = true } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 90)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

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

                Button(action: onComment) {
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
            ShareLink(item: shareText) {
                Label("Share Post", systemImage: "square.and.arrow.up")
            }
            if currentUserId != nil && currentUserId != post.userId {
                Button { showReportConfirm = true } label: {
                    Label("Report Post", systemImage: "flag")
                }
            }
            if currentUserId == post.userId || AdminManager.isAdmin(currentUserId) {
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
            "Delete this gratitude post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Report this gratitude post?",
            isPresented: $showReportConfirm,
            titleVisibility: .visible
        ) {
            Button("Report", role: .destructive) { onReport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This post will be reviewed by our team and hidden from your feed.")
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let uiImage = decodedImage {
                GratitudePhotoViewer(image: uiImage)
            }
        }
    }
}

// MARK: - Fullscreen Photo Viewer with Pinch-to-Zoom

private struct GratitudePhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let newScale = lastScale * value.magnification

                                // Shift offset toward the pinch anchor so zoom
                                // feels like it originates under the fingers.
                                let anchor = value.startAnchor
                                let anchorPt = CGPoint(
                                    x: anchor.x * geo.size.width,
                                    y: anchor.y * geo.size.height
                                )
                                let center = CGPoint(
                                    x: geo.size.width / 2,
                                    y: geo.size.height / 2
                                )
                                let delta = newScale - scale
                                let shiftX = (center.x - anchorPt.x) * delta
                                let shiftY = (center.y - anchorPt.y) * delta

                                scale = newScale
                                offset = CGSize(
                                    width: offset.width + shiftX,
                                    height: offset.height + shiftY
                                )
                            }
                            .onEnded { _ in
                                lastScale = max(scale, 1.0)
                                scale = lastScale
                                if scale <= 1.0 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                } else {
                                    lastOffset = offset
                                }
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1.0 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    )
                    .onTapGesture(count: 2) { location in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                let targetScale: CGFloat = 3.0
                                let center = CGPoint(
                                    x: geo.size.width / 2,
                                    y: geo.size.height / 2
                                )
                                let newOffset = CGSize(
                                    width: (center.x - location.x) * (targetScale - 1),
                                    height: (center.y - location.y) * (targetScale - 1)
                                )
                                scale = targetScale
                                lastScale = targetScale
                                offset = newOffset
                                lastOffset = newOffset
                            }
                        }
                    }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
    }
}
