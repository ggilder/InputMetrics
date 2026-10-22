import XCTest
import GRDB
@testable import InputMetrics

final class DatabaseManagerTests: XCTestCase {

    // DatabaseManager is a singleton with a file-based DB, so these tests run
    // its migrations and exercise the models against an in-memory DB.

    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
    }

    // MARK: - Migration

    func testMigrationDropsMouseSchemaAndKeepsKeyboardData() async throws {
        let legacyDb = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(legacyDb, upTo: "v9")

        try await legacyDb.write { db in
            try db.execute(
                sql: """
                    INSERT INTO daily_summary (date, mouse_distance_px, mouse_clicks_left, keystrokes, scroll_distance_vertical, first_active_at, active_minutes, peak_mouse_speed, peak_wpm)
                    VALUES ('2025-06-01', 100, 5, 200, 10, '2025-06-01T08:00', 30, 99, 80)
                    """
            )
            try db.execute(sql: "INSERT INTO hourly_summary (date, hour, mouse_distance_px, mouse_clicks, keystrokes) VALUES ('2025-06-01', 9, 50, 3, 70)")
            try db.execute(sql: "INSERT INTO app_usage (date, bundle_id, app_name, keystrokes, mouse_clicks, active_seconds) VALUES ('2025-06-01', 'com.test', 'Test', 40, 6, 60)")
            try db.execute(sql: "INSERT INTO keyboard_heatmap (date, key_code, modifier_flags, count) VALUES ('2025-06-01', 49, 0, 12)")
            try db.execute(sql: "INSERT INTO mouse_heatmap (date, screen_id, bucket_x, bucket_y, click_count) VALUES ('2025-06-01', '1', 0, 0, 1)")
        }

        try DatabaseManager.migrator.migrate(legacyDb)

        try await legacyDb.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertFalse(tables.contains("mouse_heatmap"))

            let dailyColumns = try db.columns(in: "daily_summary").map(\.name)
            XCTAssertEqual(Set(dailyColumns), ["date", "keystrokes", "first_active_at", "last_active_at", "active_minutes", "peak_wpm"])
            XCTAssertEqual(Set(try db.columns(in: "hourly_summary").map(\.name)), ["date", "hour", "keystrokes"])
            XCTAssertEqual(Set(try db.columns(in: "app_usage").map(\.name)), ["date", "bundle_id", "app_name", "keystrokes", "active_seconds"])

            let summary = try DailySummary.fetchOne(db, key: "2025-06-01")
            XCTAssertEqual(summary?.keystrokes, 200)
            XCTAssertEqual(summary?.activeMinutes, 30)
            XCTAssertEqual(summary?.peakWPM, 80)
            XCTAssertEqual(try HourlySummary.fetchOne(db)?.keystrokes, 70)
            XCTAssertEqual(try AppUsageEntry.fetchOne(db)?.keystrokes, 40)
            XCTAssertEqual(try KeyboardEntry.fetchOne(db)?.count, 12)
        }
    }

    // MARK: - DailySummary CRUD

    func testInsertAndFetchDailySummary() async throws {
        let summary = DailySummary(date: "2025-01-15", keystrokes: 500)

        try await dbQueue.write { db in
            try summary.insert(db)
        }

        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-01-15")
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.date, "2025-01-15")
        XCTAssertEqual(fetched?.keystrokes, 500)
    }

    func testUpdateDailySummary() async throws {
        let summary = DailySummary(date: "2025-01-15", keystrokes: 500)

        try await dbQueue.write { db in
            try summary.insert(db)
        }

        var modified = summary
        modified.keystrokes = 1000
        let updated = modified

        try await dbQueue.write { db in
            try updated.update(db)
        }

        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-01-15")
        }

        XCTAssertEqual(fetched?.keystrokes, 1000)
    }

    func testFetchNonExistentSummary() async throws {
        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2099-01-01")
        }
        XCTAssertNil(fetched)
    }

    // MARK: - KeyboardEntry CRUD

    func testInsertAndFetchKeyboardEntry() async throws {
        let entry = KeyboardEntry(date: "2025-01-15", keyCode: 0, modifierFlags: 0, count: 42)

        try await dbQueue.write { db in
            try entry.insert(db)
        }

        let entries = try await dbQueue.read { db in
            try KeyboardEntry.filter(KeyboardEntry.Columns.date == "2025-01-15").fetchAll(db)
        }

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.keyCode, 0)
        XCTAssertEqual(entries.first?.count, 42)
    }

    func testKeyboardEntryCompositeId() {
        let entry = KeyboardEntry(date: "2025-01-15", keyCode: 49, modifierFlags: 256, count: 10)
        XCTAssertEqual(entry.compositeId, "49-256")
    }

    // MARK: - HourlySummary CRUD

    func testInsertAndFetchHourlySummary() async throws {
        let summary = HourlySummary(date: "2025-01-15", hour: 14, keystrokes: 100)

        try await dbQueue.write { db in
            try summary.insert(db)
        }

        let summaries = try await dbQueue.read { db in
            try HourlySummary
                .filter(HourlySummary.Columns.date == "2025-01-15")
                .order(HourlySummary.Columns.hour)
                .fetchAll(db)
        }

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.hour, 14)
    }

    // MARK: - Backup & Restore

    func testBackupCreatesValidFile() async throws {
        try await dbQueue.write { db in
            try DailySummary(date: "2025-06-01", keystrokes: 200).insert(db)
        }

        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_backup_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let backupDb = try DatabaseQueue(path: backupURL.path)
        try dbQueue.backup(to: backupDb)

        let fetched = try await backupDb.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.keystrokes, 200)
    }

    func testRestoreFromValidBackup() async throws {
        try await dbQueue.write { db in
            try DailySummary(date: "2025-06-01", keystrokes: 300).insert(db)
        }

        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_restore_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let backupDb = try DatabaseQueue(path: backupURL.path)
        try dbQueue.backup(to: backupDb)

        let restoredDb = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(restoredDb)

        try backupDb.backup(to: restoredDb)

        let fetched = try await restoredDb.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.date, "2025-06-01")
        XCTAssertEqual(fetched?.keystrokes, 300)
    }

    // MARK: - Data Retention (Pruning)

    func testPruneRemovesOldData() async throws {
        let oldDate = "2020-01-01"
        let recentDate = "2099-12-31"

        try await dbQueue.write { db in
            try DailySummary(date: oldDate, keystrokes: 50).insert(db)
            try DailySummary(date: recentDate, keystrokes: 100).insert(db)

            try HourlySummary(date: oldDate, hour: 10, keystrokes: 10).insert(db)
            try HourlySummary(date: recentDate, hour: 10, keystrokes: 10).insert(db)

            try KeyboardEntry(date: oldDate, keyCode: 0, modifierFlags: 0, count: 5).insert(db)
            try KeyboardEntry(date: recentDate, keyCode: 0, modifierFlags: 0, count: 5).insert(db)

            try AppUsageEntry(date: oldDate, bundleId: "com.test", appName: "Test", keystrokes: 10, activeSeconds: 60).insert(db)
            try AppUsageEntry(date: recentDate, bundleId: "com.test", appName: "Test", keystrokes: 10, activeSeconds: 60).insert(db)
        }

        // Prune with a cutoff that removes oldDate but keeps recentDate
        let cutoffString = "2025-01-01"
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM daily_summary WHERE date < ?", arguments: [cutoffString])
            try db.execute(sql: "DELETE FROM keyboard_heatmap WHERE date < ?", arguments: [cutoffString])
            try db.execute(sql: "DELETE FROM hourly_summary WHERE date < ?", arguments: [cutoffString])
            try db.execute(sql: "DELETE FROM app_usage WHERE date < ?", arguments: [cutoffString])
        }

        let dailyCount = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_summary") }
        let hourlyCount = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hourly_summary") }
        let keyboardCount = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keyboard_heatmap") }
        let appUsageCount = try await dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM app_usage") }

        XCTAssertEqual(dailyCount, 1)
        XCTAssertEqual(hourlyCount, 1)
        XCTAssertEqual(keyboardCount, 1)
        XCTAssertEqual(appUsageCount, 1)
    }

    func testPrunePreservesDataAtCutoff() async throws {
        let cutoffDate = "2025-01-01"
        let afterCutoff = "2025-01-02"

        try await dbQueue.write { db in
            try DailySummary(date: cutoffDate, keystrokes: 50).insert(db)
            try DailySummary(date: afterCutoff, keystrokes: 100).insert(db)
        }

        // DELETE WHERE date < cutoff preserves cutoff date itself
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM daily_summary WHERE date < ?", arguments: [cutoffDate])
        }

        let remaining = try await dbQueue.read { db in
            try DailySummary.order(DailySummary.Columns.date).fetchAll(db)
        }

        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].date, cutoffDate)
        XCTAssertEqual(remaining[1].date, afterCutoff)
    }

    // MARK: - Upsert Edge Cases

    private func upsertDailySummary(
        date: String,
        keystrokes: Int,
        firstActiveAt: String? = nil,
        lastActiveAt: String? = nil,
        activeMinutes: Int = 0,
        peakWPM: Double = 0
    ) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO daily_summary (date, keystrokes, first_active_at, last_active_at, active_minutes, peak_wpm)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(date) DO UPDATE SET
                        keystrokes = keystrokes + excluded.keystrokes,
                        first_active_at = COALESCE(daily_summary.first_active_at, excluded.first_active_at),
                        last_active_at = COALESCE(daily_summary.last_active_at, excluded.last_active_at),
                        active_minutes = active_minutes + excluded.active_minutes,
                        peak_wpm = CASE WHEN excluded.peak_wpm > daily_summary.peak_wpm THEN excluded.peak_wpm ELSE daily_summary.peak_wpm END
                    """,
                arguments: [date, keystrokes, firstActiveAt, lastActiveAt, activeMinutes, peakWPM]
            )
        }
    }

    func testDailySummaryUpsertAccumulatesValues() async throws {
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 200, firstActiveAt: "08:00", lastActiveAt: "09:00", activeMinutes: 30, peakWPM: 80)
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 100, firstActiveAt: "10:00", lastActiveAt: "11:00", activeMinutes: 15, peakWPM: 90)

        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }

        XCTAssertEqual(fetched?.keystrokes, 300)
        XCTAssertEqual(fetched?.activeMinutes, 45)
    }

    func testUpsertPreservesPeakWPM() async throws {
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 0, peakWPM: 150)

        // Lower peak -- existing peak should be preserved
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 5, peakWPM: 30)

        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }
        XCTAssertEqual(fetched?.peakWPM, 150)

        // Higher peak -- new peak should win
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 0, peakWPM: 250)

        let updated = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }
        XCTAssertEqual(updated?.peakWPM, 250)
    }

    func testUpsertPreservesFirstActiveAt() async throws {
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 0, firstActiveAt: "08:00", lastActiveAt: "09:00")

        // first_active_at/last_active_at keep existing values (COALESCE)
        try await upsertDailySummary(date: "2025-06-01", keystrokes: 0, firstActiveAt: "14:00", lastActiveAt: "15:00")

        let fetched = try await dbQueue.read { db in
            try DailySummary.fetchOne(db, key: "2025-06-01")
        }

        XCTAssertEqual(fetched?.firstActiveAt, "08:00")
        XCTAssertEqual(fetched?.lastActiveAt, "09:00")
    }

    // MARK: - Empty Database Queries

    func testEmptyDatabaseDailySummariesReturnsEmpty() async throws {
        let summaries = try await dbQueue.read { db in
            try DailySummary
                .filter(DailySummary.Columns.date >= "2025-01-01" && DailySummary.Columns.date <= "2025-12-31")
                .order(DailySummary.Columns.date)
                .fetchAll(db)
        }
        XCTAssertTrue(summaries.isEmpty)
    }

    func testEmptyDatabaseHourlySummariesReturnsEmpty() async throws {
        let summaries = try await dbQueue.read { db in
            try HourlySummary
                .filter(HourlySummary.Columns.date == "2025-01-15")
                .order(HourlySummary.Columns.hour)
                .fetchAll(db)
        }
        XCTAssertTrue(summaries.isEmpty)
    }

    func testEmptyDatabaseKeyboardEntriesReturnsEmpty() async throws {
        let entries = try await dbQueue.read { db in
            try KeyboardEntry.filter(KeyboardEntry.Columns.date == "2025-01-15").fetchAll(db)
        }
        XCTAssertTrue(entries.isEmpty)
    }

    func testKeyboardHeatmapUpsertAccumulatesCount() async throws {
        for _ in 0..<2 {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO keyboard_heatmap (date, key_code, modifier_flags, count)
                        VALUES (?, ?, ?, 1)
                        ON CONFLICT(date, key_code, modifier_flags) DO UPDATE SET
                            count = count + 1
                        """,
                    arguments: ["2025-06-01", 49, 0]
                )
            }
        }

        let entry = try await dbQueue.read { db in
            try KeyboardEntry
                .filter(KeyboardEntry.Columns.date == "2025-06-01")
                .filter(KeyboardEntry.Columns.keyCode == 49)
                .filter(KeyboardEntry.Columns.modifierFlags == 0)
                .fetchOne(db)
        }

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.count, 2)
    }
}
