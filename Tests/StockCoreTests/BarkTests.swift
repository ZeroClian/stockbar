import Foundation
import Testing
@testable import StockCore

@Test func barkDeliverySurvivesSavedStateRoundTrip() throws {
    let channel = try #require(AlertDelivery(rawValue: "bark"))
    let item = WatchItem(symbol: try StockSymbol("159915"), name: "创业板ETF", rule: AlertRule(upEnabled: true, delivery: channel))
    let state = SavedState(items: [item])
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
    #expect(restored.items[0].rule.delivery.rawValue == "bark")
}

@Test func barkTemplateKeepsFactsIndependentOfEditableText() throws {
    let symbol = try StockSymbol("159915")
    let quote = Quote(symbol: symbol, name: "创业板ETF", last: Decimal(string: "2.651")!, previousClose: Decimal(string: "2.678")!, percent: -1.01, timestamp: Date(timeIntervalSince1970: 1792717200))
    let candidate = AlertCandidate(key: "sz159915|priceBelow|2.66", day: "2026-10-23", symbol: symbol, title: "", body: "", value: quote.last)
    var config = BarkConfiguration(); config.includeValues = true
    let first = try BarkMessage(configuration: config, alias: "CYBETF", candidate: candidate, quote: quote)
    config.title = "喝杯水"; config.note = "检查一下。{价格}"
    let second = try BarkMessage(configuration: config, alias: "CYBETF", candidate: candidate, quote: quote)
    #expect(first.facts == second.facts)
    #expect(second.title == "喝杯水")
    #expect(second.body.hasPrefix("证券代号：CYBETF\n触发规则：跌到价格\n设置阈值：2.660元\n触发数值：2.651元"))
    #expect(second.body.hasSuffix("检查一下。{价格}"))
    config.includeValues = false
    let hidden = try BarkMessage(configuration: config, alias: "CYBETF", candidate: candidate, quote: quote)
    #expect(!hidden.facts.contains("2.66") && !hidden.facts.contains("2.651"))
    #expect(hidden.facts.contains("行情时间") && !hidden.body.contains("创业板ETF"))
}

@Test func barkPreferencesRoundTripAndOldStateDefaultsToDisabled() throws {
    var state = SavedState()
    state.bark.enabled = true; state.bark.title = "看看"; state.bark.includeValues = true
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(SavedState.self, from: data).bark == state.bark)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "bark")
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(restored.bark == BarkConfiguration())
    #expect(!String(decoding: data, as: UTF8.self).contains("device_key"))
}

@Test func barkConfigurationRejectsUnsafeURLsAndOversizeTemplate() throws {
    for server in ["http://api.day.app", "https://user:password@api.day.app", "https://api.day.app?key=secret", "https://api.day.app#secret"] {
        var config = BarkConfiguration(); config.server = server
        #expect(throws: (any Error).self) { try config.validate() }
    }
    var config = BarkConfiguration(); config.server = "https://example.com/bark/"
    try config.validate()
    #expect(config.endpoint?.absoluteString == "https://example.com/bark/push")
    config.note = String(repeating: "字", count: 121)
    #expect(throws: (any Error).self) { try config.validate() }
}
