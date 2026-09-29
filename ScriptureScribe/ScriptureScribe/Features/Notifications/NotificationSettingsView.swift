//
//  NotificationSettingsView.swift
//  ScriptureScribe
//
//  Lets the user turn Daily tab reminders on or off, choose which sections
//  remind them, and pick a time for each one. Opened from Profile and from the
//  bell button in the Daily tab.
//

import SwiftUI
import UIKit

struct NotificationSettingsView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var notifications = NotificationManager.shared

    /// Holds the main switch's new position while iOS asks for permission, so the
    /// switch doesn't jump back while the permission popup is showing.
    @State private var pendingEnabled: Bool?

    var body: some View {
        ZStack {
            themeManager.currentTheme.background
                .ignoresSafeArea()

            List {

                // ── Blocked in iOS Settings ──────────────────────────────
                if notifications.isBlocked {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.slash.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)
                                Text("Notifications Are Off")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.currentTheme.text)
                            }
                            Text("Scripture Scribe isn't allowed to send notifications. Turn them on in the Settings app to get your reminders.")
                                .font(.caption)
                                .foregroundStyle(themeManager.currentTheme.textSecondary)
                                .padding(.leading, 36)
                        }
                        .padding(.vertical, 4)

                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gear")
                                    .foregroundStyle(themeManager.currentTheme.primary)
                                    .frame(width: 24)
                                Text("Open Settings")
                                    .foregroundStyle(themeManager.currentTheme.text)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(themeManager.currentTheme.textSecondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .listRowBackground(themeManager.currentTheme.surface)
                }

                // ── Main switch ──────────────────────────────────────────
                Section {
                    Toggle(isOn: enabledBinding) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(themeManager.currentTheme.primary)
                                .frame(width: 24)
                            Text("Daily Reminders")
                                .foregroundStyle(themeManager.currentTheme.text)
                        }
                    }
                    .tint(themeManager.currentTheme.primary)
                    .disabled(pendingEnabled != nil)
                } footer: {
                    Text("Get reminders for the Daily tab at the times you choose.")
                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                }
                .listRowBackground(themeManager.currentTheme.surface)

                // ── Individual reminders ─────────────────────────────────
                if notifications.settings.isEnabled {
                    Section {
                        ForEach(DailySection.allCases) { section in
                            Toggle(isOn: reminderBinding(for: section)) {
                                HStack(spacing: 12) {
                                    Image(systemName: section.icon)
                                        .foregroundStyle(themeManager.currentTheme.primary)
                                        .frame(width: 24)
                                    Text(NotificationManager.reminderName(for: section))
                                        .foregroundStyle(themeManager.currentTheme.text)
                                }
                            }
                            .tint(themeManager.currentTheme.primary)

                            if notifications.reminder(for: section).isOn {
                                DatePicker(selection: timeBinding(for: section),
                                           displayedComponents: .hourAndMinute) {
                                    Text("Time")
                                        .foregroundStyle(themeManager.currentTheme.textSecondary)
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    } header: {
                        Text("Reminders")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    } footer: {
                        Text("Each reminder repeats every day at its time.")
                            .foregroundStyle(themeManager.currentTheme.textSecondary)
                    }
                    .listRowBackground(themeManager.currentTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(themeManager.currentTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await notifications.refreshAuthorizationStatus()
        }
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { pendingEnabled ?? notifications.settings.isEnabled },
            set: { newValue in
                pendingEnabled = newValue
                Task {
                    await notifications.setEnabled(newValue)
                    pendingEnabled = nil
                }
            }
        )
    }

    private func reminderBinding(for section: DailySection) -> Binding<Bool> {
        Binding(
            get: { notifications.reminder(for: section).isOn },
            set: { isOn in
                withAnimation { notifications.setReminder(section, isOn: isOn) }
            }
        )
    }

    private func timeBinding(for section: DailySection) -> Binding<Date> {
        Binding(
            get: { notifications.time(for: section) },
            set: { notifications.setTime($0, for: section) }
        )
    }
}
