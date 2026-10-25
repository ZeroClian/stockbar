import Foundation
import Testing
import StockCore

private func moment(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func refreshCalendarStopsOnHolidayWeekendAndSessionClose() {
    for text in ["2026-01-01T02:00:00Z", "2026-02-23T02:00:00Z", "2026-04-06T02:00:00Z", "2026-05-05T02:00:00Z", "2026-06-19T02:00:00Z", "2026-09-25T02:00:00Z", "2026-10-07T02:00:00Z", "2026-10-10T02:00:00Z", "2026-10-23T03:30:00Z", "2026-10-23T07:00:00Z"] {
        #expect(!TradingSchedule.isOpen(moment(text)))
    }
    #expect(TradingSchedule.isOpen(moment("2026-10-08T01:30:00Z")))
    #expect(TradingSchedule.isOpen(moment("2026-10-23T05:00:00Z")))
    #expect(!MarketClock.isTradingTime(moment("2026-10-07T02:00:00Z")))
}

@Test func nextRefreshHonorsIntervalAndResumesAtOpen() {
    for (input, interval, expected) in [
        ("2026-10-23T02:00:00Z", 37, "2026-10-23T02:00:37Z"),
        ("2026-10-23T03:29:50Z", 60, "2026-10-23T03:30:00Z"),
        ("2026-10-23T03:30:00Z", 15, "2026-10-23T05:00:00Z"),
        ("2026-10-23T07:00:00Z", 15, "2026-10-26T01:30:00Z"),
        ("2026-09-30T07:00:00Z", 15, "2026-10-08T01:30:00Z"),
        ("2026-10-26T01:29:59Z", 15, "2026-10-26T01:30:00Z")
    ] {
        #expect(TradingSchedule.nextWake(after: moment(input), interval: interval) == moment(expected))
    }
    #expect(!TradingSchedule.isCalendarSupported(moment("2027-01-04T02:00:00Z")))
    #expect(TradingSchedule.nextWake(after: moment("2027-01-04T02:00:00Z"), interval: 15) == nil)
}

@Test func refreshIntervalMigratesAndRejectsInvalidPersistedValues() throws {
    let encoded = try JSONEncoder().encode(SavedState())
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "refreshIntervalSeconds")
    #expect(try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: json)).refreshIntervalSeconds == 15)
    for seconds in [0, 4, 301, -1] {
        json["refreshIntervalSeconds"] = seconds
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: json)) }
    }
    var state = SavedState(); state.refreshIntervalSeconds = 37
    #expect(try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)) == state)
}
