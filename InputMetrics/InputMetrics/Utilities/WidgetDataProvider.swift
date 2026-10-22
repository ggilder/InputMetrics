import Foundation
import GRDB

struct WidgetDailySummary: Codable, FetchableRecord {
    var date: String
    var keystrokes: Int
    var activeMinutes: Int

    enum CodingKeys: String, CodingKey {
        case date
        case keystrokes
        case activeMinutes = "active_minutes"
    }
}

enum WidgetDataProvider {
    static var storageDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InputMetrics", isDirectory: true)
    }

    static func sharedDatabaseURL() -> URL? {
        storageDirectory.appendingPathComponent("metrics.db")
    }

    static func sharedDefaults() -> UserDefaults? {
        .standard
    }

    static func fetchTodaySummary() -> WidgetDailySummary? {
        guard let dbURL = sharedDatabaseURL(),
              FileManager.default.fileExists(atPath: dbURL.path) else {
            return nil
        }

        do {
            let dbQueue = try DatabaseQueue(path: dbURL.path)
            return try dbQueue.read { db in
                try WidgetDailySummary.fetchOne(
                    db,
                    sql: "SELECT * FROM daily_summary WHERE date = ?",
                    arguments: [todayString()]
                )
            }
        } catch {
            return nil
        }
    }

    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func formatActiveTime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        } else {
            return "\(minutes)m"
        }
    }

    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 10_000 {
            return String(format: "%.1fk", Double(count) / 1000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }
}
