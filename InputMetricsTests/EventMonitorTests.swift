import XCTest
import CoreGraphics
@testable import InputMetrics

final class EventMonitorTests: XCTestCase {
    func testInitialKeyDownIsCounted() {
        XCTAssertTrue(EventMonitor.isCountedKeystroke(type: .keyDown, isAutoRepeat: false))
    }

    func testAutoRepeatKeyDownIsNotCounted() {
        XCTAssertFalse(EventMonitor.isCountedKeystroke(type: .keyDown, isAutoRepeat: true))
    }

    func testNonKeyDownEventsAreNotCounted() {
        XCTAssertFalse(EventMonitor.isCountedKeystroke(type: .flagsChanged, isAutoRepeat: false))
        XCTAssertFalse(EventMonitor.isCountedKeystroke(type: .leftMouseDown, isAutoRepeat: false))
    }
}
