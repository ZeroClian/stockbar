import Foundation
import Testing
@testable import StockCore

@Test func normalizesShanghaiAndShenzhenETFCodes() throws {
    for (input, expected) in [(" 510300 ", "sh510300"), ("SZ159915", "sz159915"), ("588000", "sh588000"),
                              ("520900", "sh520900"), ("530060", "sh530060"), ("551000", "sh551000"),
                              ("563300", "sh563300"), ("526001", "sh526001"), ("565001", "sh565001"),
                              ("566001", "sh566001"), ("567001", "sh567001"), ("581001", "sh581001"),
                              ("587001", "sh587001"), ("589001", "sh589001"), ("158001", "sz158001")] {
        #expect(try StockSymbol(input).rawValue == expected)
    }
    for input in ["sz510300", "sh159915", "bj588000", "501018", "161725", "508000", "sh000300", "159915;sh510300"] {
        #expect(throws: (any Error).self) { try StockSymbol(input) }
    }
}

private func etfFixture() throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("docs/fixtures/quotes-20261026-etf.txt"), encoding: .utf8)
}

@Test func parsesCapturedETFsWithoutLosingThreeDecimalChanges() throws {
    let quotes = QuoteParser.parse(try etfFixture())
    #expect(Set(quotes.keys) == Set(["sh510300", "sz159915", "sh588000", "sh513100", "sh518880", "sh511010", "sh511990", "sh520900", "sh530060", "sh551000", "sh563300"]))
    #expect(quotes["sh510300"]?.change == Decimal(string: "0.001"))
    #expect(quotes["sz159915"]?.last == Decimal(string: "2.651"))
    #expect(quotes["sz159915"]?.dayHigh == Decimal(string: "2.690"))
    #expect(quotes["sz159915"]?.dayLow == Decimal(string: "2.618"))
    #expect(quotes["sz159915"]?.change == Decimal(string: "-0.051"))
    #expect(quotes["sh511990"]?.change == Decimal(string: "-0.001"))
    #expect(quotes["sh511990"]?.percent == 0)
}

@Test func rejectsETFCategoriesAndMarketIdentityMismatches() throws {
    let fixture = try etfFixture()
    for category in ["GP-A", "LOF", "ZS", "FUND", ""] {
        let invalid = fixture.replacingOccurrences(of: "~ETF~", with: "~\(category)~")
        #expect(QuoteParser.parse(invalid).isEmpty)
    }
    let wrongMarket = fixture.replacingOccurrences(of: "v_sh510300=\"1~", with: "v_sh510300=\"51~")
    #expect(QuoteParser.parse(wrongMarket)["sh510300"] == nil)
    let wrongCode = fixture.replacingOccurrences(of: "~510300~", with: "~510301~")
    #expect(QuoteParser.parse(wrongCode)["sh510300"] == nil)
}

@Test func etfHoldingsUseUnitsAndKeepDecimalProfitAfterSaving() throws {
    let q = try #require(QuoteParser.parse(try etfFixture())["sh510300"])
    let holding = Holding(quantity: 1000, averageCost: Decimal(string: "4.123")!)
    #expect(holding.dailyProfit(q) == 1)
    #expect(holding.floatingProfit(q) == 56)
    let state = SavedState(items: [WatchItem(symbol: q.symbol, name: q.name, holding: holding)], pinnedSymbol: q.symbol.rawValue)
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
    try restored.validate()
    #expect(restored == state)
}
