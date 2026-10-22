import Foundation

struct GoalConfig: Codable {
    var keystrokesDaily: Int
    var enabled: Bool

    static let `default` = GoalConfig(keystrokesDaily: 5000, enabled: false)
}
