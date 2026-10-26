import Foundation
import Testing
import StockCore
@testable import StockBar

private func hint(_ rows: [String]) throws -> String {
    "v_hint=" + String(decoding: try JSONEncoder().encode(rows.joined(separator: "^")), as: UTF8.self) + ";"
}

@Test func decodesSearchUnicodeAndFiltersUnsupportedSecurities() throws {
    let text = #"v_hint="sz~300750~\u5b81\u5fb7\u65f6\u4ee3~ndsd~GP-A^hk~03750~\u5b81\u5fb7\u65f6\u4ee3~ndsd~GP""#
    let found = try StockSearchParser.parse(text, query: "NDSD")
    #expect(found.map(\.id) == ["sz300750"])
    #expect(found.first?.name == "宁德时代")
    let mixed = try hint([
        "sh~000300~沪深300~hs300~ZS", "sh~510300~沪深300ETF~hs300etf~ETF",
        "sz~160706~沪深300LOF~hs300lof~LOF", "jj~000001~基金~hs300~KJ",
        "sz~510300~错误市场~hs300~ETF", "sh~600519~错误类型~hs300~ETF",
        "sh~510310~错误类型~hs300~GP-A", "sh~510330~~hs300~ETF"])
    #expect(try StockSearchParser.parse(mixed, query: "hs300").map(\.id) == ["sh510300"])
    #expect(try StockSearchParser.parse(hint(["bj~920002~万达轴承~wdzc~GP"]), query: "wdzc").first?.id == "bj920002")
}

@Test func searchRanksExactThenPrefixThenContainsAndLimitsAfterDeduplication() throws {
    let text = try hint([
        "sz~002204~大连重工~dlzg~GP-A", "sh~600001~完整匹配~zg~GP-A",
        "sh~600001~重复条目~zg~GP-A", "sh~601857~中国石油~zgsy~GP-A",
        "sh~601988~中国银行~zgyh~GP-A", "sh~601766~中国中车~zgzc~GP-A",
        "sh~600028~中国石化~zgsh~GP-A", "sh~600050~中国联通~zglt~GP-A",
        "sh~600519~贵州茅台~gzmt~GP-A"])
    #expect(try StockSearchParser.parse(text, query: " ZG ").map(\.id) == ["sh600001", "sh601857", "sh601988", "sh601766", "sh600028"])
    #expect(try StockSearchParser.parse(text, query: "2204").map(\.id) == ["sz002204"])
    #expect(try StockSearchParser.parse(text, query: "").isEmpty)
}

@Test func malformedSearchResponsesAreNotShownAsEmptySuccess() throws {
    #expect(try StockSearchParser.parse(#"v_hint="N";"#, query: "none").isEmpty)
    for text in ["<html>error</html>", #"v_hint="bad\uXYZ""#, #"v_hint="N";run()"#] {
        #expect(throws: (any Error).self) { try StockSearchParser.parse(text, query: "abc") }
    }
}

private struct CodeQuotes: QuoteProviding {
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] {
        let symbol = try StockSymbol("300750")
        guard symbols == [symbol] else { return [:] }
        return [symbol.rawValue: Quote(symbol: symbol, name: "宁德时代", last: 100, previousClose: 100, percent: 0, timestamp: Date())]
    }
}

@Test func fullCodeSearchUsesValidatedQuotesWithoutSuggestions() async throws {
    let service = StockSearchService(quotes: CodeQuotes())
    #expect(try await service.search(" SZ300750 ").map(\.id) == ["sz300750"])
    #expect(try await service.search("600519").isEmpty)
    for query in ["", "nd sd", "abc&x=1", String(repeating: "a", count: 33)] {
        await #expect(throws: (any Error).self) { try await service.search(query) }
    }
}

private actor DelayedSearch: StockSearching {
    var pending: [String: CheckedContinuation<[StockSearchResult], Error>] = [:]
    func search(_ query: String) async throws -> [StockSearchResult] {
        try await withCheckedThrowingContinuation { pending[query] = $0 }
    }
    func has(_ query: String) -> Bool { pending[query] != nil }
    func complete(_ query: String, results: [StockSearchResult]) { pending.removeValue(forKey: query)?.resume(returning: results) }
    func fail(_ query: String) { pending.removeValue(forKey: query)?.resume(throwing: StockSearchError.response) }
}

private enum SearchTestError: Error { case timeout }
@MainActor private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<500 {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
    throw SearchTestError.timeout
}

@MainActor @Test func newerSearchWinsWhenOlderResponseArrivesLast() async throws {
    let service = DelayedSearch()
    let subject = StockSearchModel(service: service)
    subject.updateQuery("gzmt", immediately: true)
    try await waitUntil { await service.has("gzmt") }
    subject.updateQuery("ndsd", immediately: true)
    try await waitUntil { await service.has("ndsd") }
    let latest = StockSearchResult(symbol: try StockSymbol("300750"), name: "宁德时代", initials: "ndsd")
    await service.complete("ndsd", results: [latest])
    try await waitUntil { !subject.isSearching }
    await service.complete("gzmt", results: [StockSearchResult(symbol: try StockSymbol("600519"), name: "贵州茅台", initials: "gzmt")])
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(subject.results == [latest])
    #expect(subject.message == nil)
}

@MainActor @Test func clearingAndClosingDiscardInFlightSearchResults() async throws {
    for clear in [true, false] {
        let service = DelayedSearch()
        let subject = StockSearchModel(service: service)
        subject.updateQuery("gzmt", immediately: true)
        try await waitUntil { await service.has("gzmt") }
        if clear { subject.updateQuery("") } else { subject.cancel() }
        await service.complete("gzmt", results: [StockSearchResult(symbol: try StockSymbol("600519"), name: "贵州茅台", initials: "gzmt")])
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(subject.results.isEmpty && !subject.isSearching && subject.message == nil)
    }
}

@MainActor @Test func searchFailureCanBeRetriedWithoutKeepingOldResults() async throws {
    let service = DelayedSearch()
    let model = StockSearchModel(service: service)
    model.updateQuery("ndsd", immediately: true)
    try await waitUntil { await service.has("ndsd") }
    await service.fail("ndsd")
    try await waitUntil { !model.isSearching }
    #expect(model.message != nil && model.results.isEmpty)
    model.updateQuery("ndsd", immediately: true)
    try await waitUntil { await service.has("ndsd") }
    await service.complete("ndsd", results: [StockSearchResult(symbol: try StockSymbol("300750"), name: "宁德时代", initials: "ndsd")])
    try await waitUntil { !model.isSearching }
    #expect(model.results.first?.id == "sz300750" && model.message == nil)
}
