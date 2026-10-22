import Foundation
import Observation

@Observable
@MainActor
final class KeyboardStatsViewModel {
    var selectedRange: TimeRange = .week
    var selectedDate: Date = Date()
    var chartData: [DailySummary] = []
    var keyboardEntries: [KeyboardEntry] = []
    var isLoading = true

    var topKeys: [(id: String, name: String, count: Int)] {
        let sorted = keyboardEntries.sorted { $0.count > $1.count }
        return Array(sorted.prefix(5)).map { ($0.compositeId, KeyCodeMapping.keyName(for: $0.keyCode), $0.count) }
    }

    func loadAll() {
        isLoading = true
        loadChartData()
        loadKeyboardData()
        isLoading = false
    }

    func onRangeChanged() {
        loadChartData()
    }

    func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        loadAll()
    }

    func nextDay() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        if next <= Date() {
            selectedDate = next
            loadAll()
        }
    }

    func loadChartData() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let daysBack: Int
        switch selectedRange {
        case .week: daysBack = 7
        case .month: daysBack = 30
        case .year: daysBack = 365
        }

        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: selectedDate) else { return }

        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: selectedDate)

        chartData = DatabaseManager.shared.getDailySummaries(from: startString, to: endString)

        if calendar.isDateInToday(selectedDate) {
            let todayStr = formatter.string(from: selectedDate)
            let liveKeystrokes = KeyboardTracker.shared.getCurrentKeystrokes()

            if let idx = chartData.firstIndex(where: { $0.date == todayStr }) {
                chartData[idx].keystrokes += liveKeystrokes
            } else {
                chartData.append(DailySummary(date: todayStr, keystrokes: liveKeystrokes))
            }
        }

        if selectedRange == .week || selectedRange == .month {
            chartData = chartData.fillingMissingDays(from: startDate, to: selectedDate)
        }

        if selectedRange == .year {
            chartData = aggregateByWeek(chartData)
        }
    }

    private func aggregateByWeek(_ data: [DailySummary]) -> [DailySummary] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var weekGroups: [String: [DailySummary]] = [:]

        for summary in data {
            guard let date = formatter.date(from: summary.date) else { continue }
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let weekKey = String(format: "%04d-W%02d", year, weekOfYear)
            weekGroups[weekKey, default: []].append(summary)
        }

        return weekGroups.sorted { $0.key < $1.key }.map { (_, summaries) in
            let firstDate = summaries.first?.date ?? ""
            return DailySummary(
                date: firstDate,
                keystrokes: summaries.reduce(0) { $0 + $1.keystrokes }
            )
        }
    }

    func loadKeyboardData() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: selectedDate)

        keyboardEntries = DatabaseManager.shared.getKeyboardEntries(date: dateStr)
    }
}
