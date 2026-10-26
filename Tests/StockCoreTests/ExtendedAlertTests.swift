import Foundation
import Testing
@testable import StockCore

private let alertTime = ISO8601DateFormatter().date(from: "2026-10-26T02:00:00Z")!
private func extendedItem(unit: String = "amount", quantity: Int = 100, cost: Decimal = 100) throws -> WatchItem {
    let item = WatchItem(symbol: try StockSymbol("300750"), name: "宁德时代", holding: Holding(quantity: quantity, averageCost: cost))
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    var rule = try #require(object["rule"] as? [String: Any])
    rule["price"] = ["aboveEnabled": true, "belowEnabled": true, "above": 110, "below": 90]
    rule["holding"] = ["profitEnabled": true, "lossEnabled": true, "profit": unit == "amount" ? 1000 : 10, "loss": unit == "amount" ? 1000 : 10, "unit": unit]
    object["rule"] = rule
    return try JSONDecoder().decode(WatchItem.self, from: JSONSerialization.data(withJSONObject: object))
}
private func extendedQuote(_ last: Decimal, at: Date = alertTime) throws -> Quote {
    Quote(symbol: try StockSymbol("300750"), name: "宁德时代", last: last, previousClose: 100, percent: last - 100, timestamp: at)
}

@Test func priceAndHoldingAmountAlertsTriggerAtEqualityInBothDirections() throws {
    let item = try extendedItem()
    for (price, expected): (Decimal, Set<String>) in [(110, ["sz300750|priceAbove|110", "sz300750|profitAmount|1000"]), (90, ["sz300750|priceBelow|90", "sz300750|lossAmount|1000"])] {
        let q = try extendedQuote(price)
        let alerts = AlertEvaluator.candidates(items: [item], quotes: [item.id: q], delivered: [:], now: alertTime)
        #expect(Set(alerts.map(\.key)) == expected)
        let receipts = Dictionary(uniqueKeysWithValues: alerts.map { ($0.key, $0.day) })
        #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id: q], delivered: receipts, now: alertTime).isEmpty)
    }
}

@Test func holdingPercentUsesAverageCostAndSkipsMissingPositions() throws {
    let item = try extendedItem(unit: "percent")
    let q = try extendedQuote(110)
    #expect(Set(AlertEvaluator.candidates(items: [item], quotes: [item.id: q], delivered: [:], now: alertTime).map(\.key)) == ["sz300750|priceAbove|110", "sz300750|profitPercent|10"])
    for inactive in [try extendedItem(quantity: 0), try extendedItem(cost: 0)] {
        #expect(AlertEvaluator.candidates(items: [inactive], quotes: [inactive.id: q], delivered: [:], now: alertTime).map(\.key) == ["sz300750|priceAbove|110"])
    }
}

@Test func extendedAlertsUseFloatingProfitAndRequireFreshTradingQuotes() throws {
    let item = try extendedItem()
    let flatDay = Quote(symbol: item.symbol, name: item.name, last: 110, previousClose: 110, percent: 0, timestamp: alertTime)
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id: flatDay], delivered: [:], now: alertTime).count == 2)
    let below = try extendedQuote(Decimal(string: "109.99")!)
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id: below], delivered: [:], now: alertTime).isEmpty)
    let loss = try extendedItem(unit: "percent")
    #expect(AlertEvaluator.candidates(items: [loss], quotes: [loss.id: try extendedQuote(90)], delivered: [:], now: alertTime).map(\.key).contains("sz300750|lossPercent|10"))
    for timestamp in [alertTime.addingTimeInterval(-181), alertTime.addingTimeInterval(1)] {
        #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id: try extendedQuote(110, at: timestamp)], delivered: [:], now: alertTime).isEmpty)
    }
    let lunch = ISO8601DateFormatter().date(from: "2026-10-26T04:00:00Z")!
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id: try extendedQuote(110, at: lunch)], delivered: [:], now: lunch).isEmpty)
}

@Test func extendedUnreadAlertsRetainTheirActualMetricAndSurviveRestart() throws {
    let item = try extendedItem(), q = try extendedQuote(110)
    let candidates = AlertEvaluator.candidates(items: [item], quotes: [item.id: q], delivered: [:], now: alertTime)
    var state = SavedState(items: [item])
    for c in candidates {
        state.delivered[c.key] = c.day
        state.unreadAlerts.append(PendingAlert(key: c.key, day: c.day, symbol: c.symbol, percent: q.percent, triggerValue: c.value))
    }
    try state.validate()
    let loaded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
    #expect(loaded == state)
    #expect(loaded.unreadAlerts.map(\.value) == [110, 1000])
    #expect(loaded.unreadAlerts.map(\.kind) == [.priceAbove, .profitAmount])
    #expect(AlertEvaluator.candidates(items: loaded.items, quotes: [item.id: q], delivered: loaded.delivered, now: alertTime).isEmpty)
    for value: Decimal? in [nil, .nan, 999] {
        let bad = PendingAlert(key: "sz300750|profitAmount|1000", day: "2026-10-26", symbol: item.symbol, percent: 10, triggerValue: value)
        #expect(throws: (any Error).self) { try bad.validate() }
    }
}

@Test func oldRulesDefaultNewAlertsOffAndCorruptNewRulesFailClosed() throws {
    let old = #"{"upEnabled":true,"downEnabled":false,"upThreshold":3,"downThreshold":2}"#
    let rule = try JSONDecoder().decode(AlertRule.self, from: Data(old.utf8))
    #expect(rule.upEnabled && !rule.price.aboveEnabled && !rule.holding.profitEnabled)
    #expect(rule.price == PriceAlertRule() && rule.holding == HoldingAlertRule())
    for key in ["price", "holding"] {
        var object = try #require(JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any])
        object[key] = NSNull()
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AlertRule.self, from: JSONSerialization.data(withJSONObject: object)) }
    }
    var bad = rule
    bad.price.above = 0
    #expect(throws: (any Error).self) { try bad.validate() }
    bad = rule; bad.holding.loss = -1
    #expect(throws: (any Error).self) { try bad.validate() }
}
