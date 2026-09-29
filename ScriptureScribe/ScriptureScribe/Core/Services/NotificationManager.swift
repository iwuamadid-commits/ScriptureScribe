//
//  NotificationManager.swift
//  ScriptureScribe
//
//  Daily tab reminders. These are local notifications the app schedules itself
//  (no server): one per Daily section (verse, affirmation, prayer, devotion,
//  reflection), each repeating every day at a time the user picks.
//
//  The reminder text is general on purpose. Each day's content is generated on
//  that day, so it doesn't exist yet when the reminders are scheduled.
//
//  Settings are device-local (UserDefaults), like the app's other preferences.
//
//  Tapping a reminder sets `tappedSection`. ScriptureScribeApp turns that into a
//  switch to the Daily tab, which then scrolls to the matching section.
//

import Combine
import Foundation
import UIKit
import UserNotifications

/// One section's reminder: whether it's on, and the time of day it fires.
struct DailyReminder: Codable, Equatable {
    var isOn:   Bool
    var hour:   Int
    var minute: Int
}

/// Everything the user has chosen on the Notifications screen.
struct DailyReminderSettings: Codable, Equatable {
    /// The main on/off switch.
    var isEnabled = false
    /// Per-section reminders keyed by DailySection.rawValue. Sections the user
    /// hasn't changed are missing and use their defaults.
    var reminders: [String: DailyReminder] = [:]
}

final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    /// userInfo key holding the DailySection a reminder belongs to.
    nonisolated static let sectionKey = "dailySection"

    // MARK: - Published State

    @Published private(set) var settings: DailyReminderSettings
    /// Whether iOS currently allows this app to show notifications.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Set when the user taps a reminder. Cleared by the app once it has navigated there.
    @Published var tappedSection: DailySection?

    /// True when the user has blocked notifications for this app in iOS Settings.
    var isBlocked: Bool { authorizationStatus == .denied }

    /// True when reminders are turned on and iOS is allowed to deliver them.
    var isDelivering: Bool { settings.isEnabled && isAuthorized(authorizationStatus) }

    // MARK: - Private

    private let center     = UNUserNotificationCenter.current()
    private let tapHandler = NotificationTapHandler()
    private var cancellables = Set<AnyCancellable>()
    private static let settingsKey = "dailyReminderSettings"

    private init() {
        settings = Self.loadSettings()

        // The user can change notification permission in iOS Settings while the
        // app is in the background, so re-check whenever the app becomes active.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.refreshAuthorizationStatus() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    /// Call once at launch, before the app finishes launching, so that tapping a
    /// reminder while the app is closed still opens the right section.
    func setUp() {
        center.delegate = tapHandler
        Task {
            await refreshAuthorizationStatus()
            // Re-adding the reminders keeps their text current after an app update.
            reschedule()
        }
    }

    @discardableResult
    func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        let status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        return status
    }

    // MARK: - Main Switch

    /// Turns Daily reminders on or off. The first time they're turned on, iOS asks
    /// the user for permission. Returns false if permission wasn't given.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            settings.isEnabled = false
            saveAndReschedule()
            return true
        }

        var status = await refreshAuthorizationStatus()
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await refreshAuthorizationStatus()
        }
        guard isAuthorized(status) else { return false }

        settings.isEnabled = true
        // Start with just the verse reminder so nobody gets five reminders on day one.
        if !DailySection.allCases.contains(where: { reminder(for: $0).isOn }) {
            var verse = reminder(for: .verse)
            verse.isOn = true
            settings.reminders[DailySection.verse.rawValue] = verse
        }
        saveAndReschedule()
        return true
    }

    // MARK: - Per-Section Reminders

    /// The reminder for a section, falling back to its default if never changed.
    func reminder(for section: DailySection) -> DailyReminder {
        settings.reminders[section.rawValue] ?? Self.defaultReminder(for: section)
    }

    func setReminder(_ section: DailySection, isOn: Bool) {
        var updated = reminder(for: section)
        updated.isOn = isOn
        settings.reminders[section.rawValue] = updated
        saveAndReschedule()
    }

    /// The reminder's time as a Date (today at that time), for use with a DatePicker.
    func time(for section: DailySection) -> Date {
        let current = reminder(for: section)
        return Calendar.current.date(bySettingHour: current.hour, minute: current.minute,
                                     second: 0, of: Date()) ?? Date()
    }

    func setTime(_ time: Date, for section: DailySection) {
        let parts   = Calendar.current.dateComponents([.hour, .minute], from: time)
        let current = reminder(for: section)
        var updated = current
        updated.hour   = parts.hour   ?? current.hour
        updated.minute = parts.minute ?? current.minute
        guard updated != current else { return }
        settings.reminders[section.rawValue] = updated
        saveAndReschedule()
    }

    /// Name shown for each reminder on the Notifications screen.
    static func reminderName(for section: DailySection) -> String {
        section == .verse ? "Verse of the Day" : section.label
    }

    // MARK: - Taps

    /// Called by NotificationTapHandler when the user taps a reminder.
    func handleTap(sectionRawValue: String?) {
        guard let raw = sectionRawValue, let section = DailySection(rawValue: raw) else { return }
        tappedSection = section
    }

    // MARK: - Account Deletion

    /// Turns reminders off and forgets the saved settings.
    func resetAll() {
        center.removePendingNotificationRequests(withIdentifiers: allRequestIds)
        center.removeDeliveredNotifications(withIdentifiers: allRequestIds)
        settings = DailyReminderSettings()
        UserDefaults.standard.removeObject(forKey: Self.settingsKey)
    }

    // MARK: - Scheduling

    private func saveAndReschedule() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        reschedule()
    }

    /// Replaces the scheduled reminders with the current settings. Each one repeats
    /// daily at a local time of day, so it follows the user across time zones.
    private func reschedule() {
        center.removePendingNotificationRequests(withIdentifiers: allRequestIds)
        guard settings.isEnabled else { return }

        for section in DailySection.allCases {
            let current = reminder(for: section)
            guard current.isOn else { continue }

            let message = Self.message(for: section)
            let content = UNMutableNotificationContent()
            content.title            = message.title
            content.body             = message.body
            content.sound            = .default
            content.threadIdentifier = "daily-reminders"
            content.userInfo         = [Self.sectionKey: section.rawValue]

            var time    = DateComponents()
            time.hour   = current.hour
            time.minute = current.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)

            center.add(UNNotificationRequest(identifier: Self.requestId(section),
                                             content: content, trigger: trigger))
        }
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private static func requestId(_ section: DailySection) -> String {
        "daily-reminder-\(section.rawValue)"
    }

    private var allRequestIds: [String] {
        DailySection.allCases.map { Self.requestId($0) }
    }

    private static func defaultReminder(for section: DailySection) -> DailyReminder {
        switch section {
        case .affirmation: return DailyReminder(isOn: false, hour: 7,  minute: 0)
        case .verse:       return DailyReminder(isOn: false, hour: 8,  minute: 0)
        case .devotion:    return DailyReminder(isOn: false, hour: 12, minute: 0)
        case .prayer:      return DailyReminder(isOn: false, hour: 18, minute: 0)
        case .reflection:  return DailyReminder(isOn: false, hour: 20, minute: 30)
        }
    }

    private static func message(for section: DailySection) -> (title: String, body: String) {
        switch section {
        case .verse:       return ("Verse of the Day", "Your verse for today is ready. Take a moment with God's Word.")
        case .affirmation: return ("Today's Affirmation", "Start your day with a word of encouragement.")
        case .prayer:      return ("Time to Pray", "Today's prayer is ready whenever you are.")
        case .devotion:    return ("Today's Devotion", "Spend a few quiet minutes with today's devotion.")
        case .reflection:  return ("Time to Reflect", "Take a moment with today's reflection question.")
        }
    }

    private static func loadSettings() -> DailyReminderSettings {
        guard
            let data    = UserDefaults.standard.data(forKey: settingsKey),
            let decoded = try? JSONDecoder().decode(DailyReminderSettings.self, from: data)
        else { return DailyReminderSettings() }
        return decoded
    }
}

// MARK: - Notification Delegate

/// Receives notification callbacks from iOS. Kept separate from NotificationManager
/// because iOS can call these methods off the main thread.
nonisolated final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {

    /// Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping a reminder opens the Daily tab at that reminder's section.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let section = response.notification.request.content.userInfo[NotificationManager.sectionKey] as? String
        Task { @MainActor in
            NotificationManager.shared.handleTap(sectionRawValue: section)
        }
        completionHandler()
    }
}
