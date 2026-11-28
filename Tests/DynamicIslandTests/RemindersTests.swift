import XCTest
@testable import DynamicIsland

final class RemindersTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Bangkok")!; return c }()
    func at(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }

    func testLaterTodayStaysToday() {
        XCTAssertEqual(Reminders.nextOccurrence(of: at(1, 15, 30), after: at(28, 9, 0), calendar: cal), at(28, 15, 30))
    }
    func testPassedTimeRollsToTomorrow() {
        XCTAssertEqual(Reminders.nextOccurrence(of: at(1, 8, 0), after: at(28, 9, 0), calendar: cal), at(29, 8, 0))
    }
    func testFormat() {
        XCTAssertEqual(Reminders.format(299.2), "5:00")
        XCTAssertEqual(Reminders.format(3725), "1:02:05")
        XCTAssertEqual(Reminders.format(-3), "0:00")
    }
}
