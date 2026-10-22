import GRDB

struct HourlySummary: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hourly_summary"

    var date: String
    var hour: Int
    var keystrokes: Int

    enum CodingKeys: String, CodingKey {
        case date
        case hour
        case keystrokes
    }

    enum Columns {
        static let date = Column(CodingKeys.date)
        static let hour = Column(CodingKeys.hour)
        static let keystrokes = Column(CodingKeys.keystrokes)
    }
}
