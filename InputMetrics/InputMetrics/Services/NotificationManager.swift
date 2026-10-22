import Foundation
import os
import UserNotifications

@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.general.error("Notification permission error: \(error)")
            }
        }
    }

    private func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func sendDailySummaryNotification(keystrokes: Int) async {
        guard UserPreferences.shared.notificationsEnabled else { return }
        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Daily Summary"
        content.body = "Today: \(keystrokes) keystrokes"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "daily-summary-\(DateHelper.todayString())", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func sendMilestoneNotification(title: String, body: String) async {
        guard UserPreferences.shared.notificationsEnabled else { return }
        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: "milestone-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func scheduleDailySummary() async {
        guard UserPreferences.shared.notificationsEnabled else { return }
        guard await isAuthorized() else { return }

        // Schedule for end of day (6 PM)
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Daily Summary Ready"
        content.body = "Check your InputMetrics stats for today!"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "daily-summary-reminder", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func checkMilestones() async {
        guard UserPreferences.shared.notificationsEnabled else { return }
        guard await isAuthorized() else { return }

        let totalKeystrokes = DatabaseManager.shared.getAllTimeKeystrokes()

        let keystrokeMilestones = [10_000, 50_000, 100_000, 500_000, 1_000_000]

        let lastKeystrokeMilestone = UserDefaults.standard.integer(forKey: "lastKeystrokeMilestone")

        if let milestone = keystrokeMilestones.first(where: { $0 > lastKeystrokeMilestone && totalKeystrokes >= $0 }) {
            await sendMilestoneNotification(title: "Keystroke Milestone!", body: "You've reached \(milestone) total keystrokes!")
            UserDefaults.standard.set(milestone, forKey: "lastKeystrokeMilestone")
        }
    }
}
