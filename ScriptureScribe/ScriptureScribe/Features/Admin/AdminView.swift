//
//  AdminView.swift
//  ScriptureScribe
//
//  Admin dashboard for content moderation.
//  Only accessible to users listed in AdminManager.
//  Shows flagged content across all community sections with actions to
//  remove content or dismiss reports.
//

import FirebaseFirestore
import SwiftUI

struct AdminView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = AdminViewModel()

    @State private var itemToDelete: FlaggedItem?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            themeManager.currentTheme.background
                .ignoresSafeArea()

            if vm.isLoading && vm.flaggedItems.isEmpty {
                ProgressView("Loading flagged content...")
                    .foregroundStyle(themeManager.currentTheme.textSecondary)
            } else if vm.flaggedItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("All Clear")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(themeManager.currentTheme.text)
                    Text("No flagged content to review.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
            } else {
                List {
                    // Stats bar
                    Section {
                        HStack(spacing: 0) {
                            statCell(
                                count: vm.flaggedItems.count,
                                label: "Flagged",
                                color: .orange
                            )
                            Divider().frame(height: 36)
                            statCell(
                                count: vm.flaggedItems.filter { $0.reportCount >= 5 }.count,
                                label: "Auto-Hidden",
                                color: .red
                            )
                            Divider().frame(height: 36)
                            statCell(
                                count: vm.totalUsers,
                                label: "Users",
                                color: themeManager.currentTheme.primary
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)

                    // Flagged items
                    Section {
                        ForEach(vm.flaggedItems) { item in
                            flaggedRow(item)
                        }
                    } header: {
                        HStack {
                            Text("Flagged Content")
                            Spacer()
                            Button {
                                Task { await vm.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)
                }
                .scrollContentBackground(.hidden)
                .refreshable { await vm.refresh() }
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await vm.refresh() }
        .alert("Remove Content?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    Task { await vm.deleteItem(item) }
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("This will permanently delete this \(item.contentType) by \(item.authorName). This cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statCell(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func flaggedRow(_ item: FlaggedItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: type badge + author + report count
            HStack {
                Text(item.contentType.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor(for: item)))

                Text(item.authorName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(themeManager.currentTheme.text)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                    Text("\(item.reportCount)")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(item.reportCount >= 5 ? .red : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((item.reportCount >= 5 ? Color.red : Color.orange).opacity(0.12))
                )
            }

            // Content preview
            Text(item.textPreview)
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.text)
                .lineLimit(4)

            // Timestamp
            Text(item.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(themeManager.currentTheme.textSecondary)
            + Text(" ago")
                .font(.caption2)
                .foregroundStyle(themeManager.currentTheme.textSecondary)

            // Actions
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    itemToDelete = item
                    showDeleteConfirm = true
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    Task { await vm.dismissReports(item) }
                } label: {
                    Label("Dismiss", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(themeManager.currentTheme.textSecondary)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private func badgeColor(for item: FlaggedItem) -> Color {
        switch item.contentType {
        case "post":      return .blue
        case "gratitude": return .purple
        case "prayer":    return .green
        case "answer":    return .orange
        case "comment":   return .gray
        default:          return .secondary
        }
    }
}
