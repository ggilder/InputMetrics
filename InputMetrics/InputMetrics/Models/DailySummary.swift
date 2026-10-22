import Foundation
import GRDB

struct DailySummary: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "daily_summary"

    var date: String
    var keystrokes: Int
    var firstActiveAt: String?
    var lastActiveAt: String?
    var activeMinutes: Int = 0
    var peakWPM: Double = 0

    enum CodingKeys: String, CodingKey {
        case date
        case keystrokes
        case firstActiveAt = "first_active_at"
        case lastActiveAt = "last_active_at"
        case activeMinutes = "active_minutes"
        case peakWPM = "peak_wpm"
    }

    enum Columns {
        static let date = Column(CodingKeys.date)
        static let keystrokes = Column(CodingKeys.keystrokes)
        static let firstActiveAt = Column(CodingKeys.firstActiveAt)
        static let lastActiveAt = Column(CodingKeys.lastActiveAt)
        static let activeMinutes = Column(CodingKeys.activeMinutes)
        static let peakWPM = Column(CodingKeys.peakWPM)
    }

    static func zero(for date: String) -> DailySummary {
        DailySummary(date: date, keystrokes: 0)
    }
}

extension [DailySummary] {
    func fillingMissingDays(from start: Date, to end: Date) -> [DailySummary] {
        let calendar = Calendar.current
        let formatter = DateHelper.self
        let existing = Dictionary(uniqueKeysWithValues: self.map { ($0.date, $0) })
        var result: [DailySummary] = []
        var current = start
        while current <= end {
            let key = formatter.string(from: current)
            result.append(existing[key] ?? .zero(for: key))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return result
    }
}
