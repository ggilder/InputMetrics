import Foundation
import Observation

@Observable
@MainActor
final class MenuBarViewModel {
    var keystrokes: Int = 0
    var chartData: [DailySummary] = []
    var keyboardEntries: [KeyboardEntry] = []
    var hourlySummaries: [HourlySummary] = []
    var currentStreak: Int = 0
    var keystrokeProgress: Double = 0
    var appUsageEntries: [AppUsageEntry] = []
    var activeMinutes: Int = 0
    var peakWPM: Double = 0
    var allTimeKeystrokes: Int = 0
    var firstActiveAt: String?
    var lastActiveAt: String?
    private var cachedKeystrokes: Int = 0
    private var lastCacheTime: Date = .distantPast
    private let cacheInterval: TimeInterval = 30

    var formattedActiveTimeRange: String? {
        guard let first = firstActiveAt, let last = lastActiveAt else { return nil }

        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let legacyFormatter = DateFormatter()
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.dateFormat = "HH:mm"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateTimeFormatter.dateFormat = "MMM d, HH:mm"

        func parse(_ value: String) -> Date? {
            isoFormatter.date(from: value) ?? legacyFormatter.date(from: value)
        }

        guard let firstDate = parse(first), let lastDate = parse(last) else {
            return "\(first) - \(last)"
        }

        let firstIsISO = isoFormatter.date(from: first) != nil
        let lastIsISO = isoFormatter.date(from: last) != nil

        // Only show dates if both values carry date info and they span different days
        if firstIsISO && lastIsISO {
            let calendar = Calendar.current
            if calendar.startOfDay(for: firstDate) != calendar.startOfDay(for: lastDate) {
                return "\(dateTimeFormatter.string(from: firstDate)) - \(dateTimeFormatter.string(from: lastDate))"
            }
        }

        return "\(timeFormatter.string(from: firstDate)) - \(timeFormatter.string(from: lastDate))"
    }

    var topKeys: [KeyboardEntry] {
        Array(keyboardEntries.sorted { $0.count > $1.count }.prefix(5))
    }

    func loadAll() {
        updateStats()
        loadChartData()
        loadKeyboardData()
        loadHourlySummaries()
        loadAppUsage()
        refreshCachedTotals()
        updateAllTimeStats()
    }

    func updateStats() {
        let keyboardStats = KeyboardTracker.shared.getCurrentKeystrokes()
        let today = todayString()

        let liveActivity = EventMonitor.shared.getActivityTimes()

        if let summary = DatabaseManager.shared.getDailySummary(date: today) {
            keystrokes = summary.keystrokes + keyboardStats
            firstActiveAt = summary.firstActiveAt ?? liveActivity.first
            lastActiveAt = liveActivity.last ?? summary.lastActiveAt
            activeMinutes = summary.activeMinutes
            peakWPM = summary.peakWPM
        } else {
            keystrokes = keyboardStats
            firstActiveAt = liveActivity.first
            lastActiveAt = liveActivity.last
            peakWPM = 0
        }

        calculateGoalProgress()
    }

    func calculateGoalProgress() {
        let config = UserPreferences.shared.goalConfig
        guard config.enabled else { return }

        keystrokeProgress = min(1.0, Double(keystrokes) / Double(config.keystrokesDaily))

        calculateStreak(config: config)
    }

    private func calculateStreak(config: GoalConfig) {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var streak = 0
        var checkDate = calendar.date(byAdding: .day, value: -1, to: Date())!

        for _ in 0..<365 {
            let dateStr = formatter.string(from: checkDate)
            guard let summary = DatabaseManager.shared.getDailySummary(date: dateStr) else { break }

            if summary.keystrokes >= config.keystrokesDaily {
                streak += 1
            } else {
                break
            }
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        currentStreak = streak
    }

    func refreshCachedTotals() {
        cachedKeystrokes = DatabaseManager.shared.getAllTimeKeystrokes()
        lastCacheTime = Date()
    }

    func refreshAllTimeTotalsIfNeeded() {
        guard Date().timeIntervalSince(lastCacheTime) >= cacheInterval else { return }
        refreshCachedTotals()
    }

    func updateAllTimeStats() {
        allTimeKeystrokes = cachedKeystrokes + KeyboardTracker.shared.getCurrentKeystrokes()
    }

    func loadChartData() {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let startDate = calendar.date(byAdding: .day, value: -6, to: today) else { return }

        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: today)

        chartData = DatabaseManager.shared.getDailySummaries(from: startString, to: endString)

        let todayStr = formatter.string(from: today)
        let keyboardStats = KeyboardTracker.shared.getCurrentKeystrokes()

        if let idx = chartData.firstIndex(where: { $0.date == todayStr }) {
            chartData[idx].keystrokes += keyboardStats
        } else {
            chartData.append(DailySummary(date: todayStr, keystrokes: keyboardStats))
        }
    }

    func loadKeyboardData() {
        let today = todayString()
        keyboardEntries = DatabaseManager.shared.getKeyboardEntries(date: today)
    }

    func loadHourlySummaries() {
        let today = todayString()
        hourlySummaries = DatabaseManager.shared.getHourlySummaries(date: today)
    }

    func loadAppUsage() {
        let today = todayString()
        var entries = DatabaseManager.shared.getAppUsage(date: today)

        for (bundleId, live) in EventMonitor.shared.getAppUsageSnapshot() {
            if let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) {
                entries[idx].keystrokes += live.keystrokes
            } else {
                entries.append(AppUsageEntry(
                    date: today,
                    bundleId: bundleId,
                    appName: live.name,
                    keystrokes: live.keystrokes,
                    activeSeconds: 0
                ))
            }
        }

        appUsageEntries = entries.sorted { $0.keystrokes > $1.keystrokes }
    }

    func shortDay(from dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return "" }

        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
