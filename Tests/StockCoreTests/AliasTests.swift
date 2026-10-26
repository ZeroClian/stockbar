import Foundation
import Testing
@testable import StockCore

@Test func defaultAliasesUsePinyinInitialsAndKeepLatinAndDigits() throws {
    let items = try [("600519", "贵州茅台"), ("300750", "宁德时代"), ("000001", "平安银行"),
                     ("510300", "沪深300ETF华泰柏瑞"), ("600221", "*ST海航"), ("600900", "长江电力")]
        .map { WatchItem(symbol: try StockSymbol($0.0), name: $0.1) }
    let state = SavedState(items: items)
    #expect(state.aliases == ["sh600519": "GZMT", "sz300750": "NDSD", "sz000001": "PAYH",
                              "sh510300": "HS300ETF", "sh600221": "STHH", "sh600900": "CJDL"])
    try state.validate()
}

@Test func generatedAliasesAvoidCustomNamesAndStayStableAfterReordering() throws {
    let items = try [("600519", "贵州茅台"), ("000001", "平安银行"), ("600036", "平安银行"), ("300750", "宁德时代")]
        .map { WatchItem(symbol: try StockSymbol($0.0), name: $0.1) }
    var state = SavedState(items: items, aliases: ["sz300750": "PAYH"])
    #expect(state.aliases["sz000001"] == "PAYH2")
    #expect(state.aliases["sh600036"] == "PAYH3")
    let original = state.aliases
    state.items.reverse()
    state.assignMissingAliases()
    #expect(state.aliases == original)
    #expect(try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)) == state)
}

@Test func migratesOnlyLegacyAllocatedNumberAliasesAndPreservesHoldings() throws {
    let items = try [("600519", "贵州茅台"), ("000001", "平安银行"), ("300750", "宁德时代")]
        .map { WatchItem(symbol: try StockSymbol($0.0), name: $0.1, holding: Holding(quantity: 100, averageCost: 99), rule: AlertRule(upEnabled: true)) }
    let old = SavedState(items: items, pinnedSymbol: "sh600519",
                         aliases: ["sh600519": "A01", "sz000001": "银行", "sz300750": "GZMT"], nextAliasIndex: 4)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    json.removeValue(forKey: "aliasNamingVersion")
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.aliases == ["sh600519": "GZMT2", "sz000001": "银行", "sz300750": "GZMT"])
    #expect(restored.items == old.items)
    #expect(restored.pinnedSymbol == old.pinnedSymbol)
    // A numbered alias explicitly saved by the new version must never be remigrated.
    var customized = restored
    customized.aliases["sh600519"] = "A01"
    let reloaded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(customized))
    #expect(reloaded.aliases["sh600519"] == "A01")
}

@Test func longOrNonTransliterableNamesHaveValidDistinctAliases() throws {
    let items = try [("600519", "沪深300ETF华泰柏瑞"), ("000001", "沪深300ETF易方达"), ("300750", "——")]
        .map { WatchItem(symbol: try StockSymbol($0.0), name: $0.1) }
    let state = SavedState(items: items)
    #expect(state.aliases["sh600519"] == "HS300ETF")
    #expect(state.aliases["sz000001"] == "HS300ET2")
    #expect(state.aliases["sz300750"] == "300750")
    try state.validate()
}
