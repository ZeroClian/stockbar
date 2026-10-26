import Foundation
import Testing
@testable import StockCore

private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
private func date(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: text)!
}
private let friday = date("2026-10-23T02:00:00Z")
private func quote(_ code: String = "600519", last: String = "1745", previous: String = "1728.49", percent: String = "0.96", at: Date = friday) throws -> Quote {
    Quote(symbol: try StockSymbol(code), name: "贵州茅台", last: dec(last), previousClose: dec(previous), percent: dec(percent), timestamp: at)
}
// Tencent assigns market ID at 0, name/code at 1/2, and security category at 61.
private func record(_ raw: String = "sh600519", changes: [Int: String] = [:]) -> String {
    var f = Array(repeating: "", count: 88)
    for (i, value) in [0:"1", 1:"贵州茅台", 2:"600519", 3:"1745.00", 4:"1728.49", 30:"20261023100000", 31:"16.51", 32:"0.96", 61:"GP-A"] { f[i] = value }
    for (i, value) in changes { f[i] = value }
    return "v_\(raw)=\"\(f.joined(separator: "~"))\";"
}

@Test func normalizesASharesAndRejectsUnsupportedCodes() throws {
    for (input, want) in [(" 600519 ", "sh600519"), ("SZ000001", "sz000001"), ("920002", "bj920002"), ("430047", "bj430047"), ("301001", "sz301001"), ("689009", "sh689009")] {
        #expect(try StockSymbol(input).rawValue == want)
    }
    for input in ["sh000001", "sz600519", "bj000001", "sh000300", "00700", "600519;sz000001", "123456", "９２０００２"] {
        #expect(throws: (any Error).self) { try StockSymbol(input) }
    }
}

@Test func calculatesMoneyUsingDecimalAndCurrentQuantity() throws {
    let q = try quote()
    let holding = Holding(quantity: 100, averageCost: 1700)
    #expect(holding.dailyProfit(q) == 1651)
    #expect(holding.floatingProfit(q) == 4500)
    #expect(abs(try #require(holding.profitPercent(q)) - dec("2.6470588235294117647")) < dec("0.0000000000000000001"))
    let down = try quote("000001", last: "10.1", previous: "10.3", percent: "-1.94")
    #expect(Holding(quantity: 1000, averageCost: 11).dailyProfit(down) == -200)
    #expect(Holding(quantity: 1000, averageCost: 11).floatingProfit(down) == -900)
    #expect(Holding(quantity: 3, averageCost: dec("0.1")).floatingProfit(try quote(last: "0.3", previous: "0.1", percent: "200")) == dec("0.6"))
    #expect(Holding(quantity: 100, averageCost: 0).profitPercent(q) == nil)
    #expect(Holding().dailyProfit(q) == 0)
}

@Test func rejectsInvalidHoldingsAndRules() {
    #expect(throws: (any Error).self) { try Holding(quantity: -1).validate() }
    #expect(throws: (any Error).self) { try Holding(averageCost: -1).validate() }
    #expect(throws: (any Error).self) { try Holding(averageCost: .nan).validate() }
    var rule = AlertRule()
    rule.upThreshold = 0
    #expect(throws: (any Error).self) { try rule.validate() }
    rule.upThreshold = 3; rule.downThreshold = .nan
    #expect(throws: (any Error).self) { try rule.validate() }
}

@Test func parsesTencentFieldsAndPreservesOtherSuccesses() throws {
    let text = record() + record("sz000001", changes: [0:"51",1:"平安银行",2:"000001",3:"10.1",4:"10.3",31:"-0.2",32:"-1.94"]) + record("bj920002", changes: [0:"62",1:"万达轴承",2:"920002",61:"GP"]) + "v_sh600000=\"bad\";"
    let parsed = QuoteParser.parse(text)
    #expect(parsed.count == 3)
    let sh = try #require(parsed["sh600519"])
    #expect(sh.last == 1745)
    #expect(sh.change == dec("16.51"))
    #expect(sh.percent == dec("0.96"))
    #expect(sh.timestamp == friday)
    #expect(parsed["bj920002"]?.name == "万达轴承")
}

@Test func persistsParsedDailyHighAndLow() throws {
    let parsed = try #require(QuoteParser.parse(record(changes: [33: "1750.25", 34: "1720.50"]))["sh600519"])
    let data = try JSONEncoder().encode(parsed)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((object["dayHigh"] as? NSNumber)?.stringValue == "1750.25")
    #expect((object["dayLow"] as? NSNumber)?.stringValue == "1720.5")
    #expect(try JSONDecoder().decode(Quote.self, from: data) == parsed)
}

@Test func missingOrInvalidExtremesDoNotDiscardCurrentPrice() throws {
    for value in ["", "0", "-1", "NaN", "Infinity", "bad"] {
        let parsed = try #require(QuoteParser.parse(record(changes: [33: value, 34: value]))["sh600519"])
        #expect(parsed.last == 1745)
        #expect(parsed.dayHigh == nil)
        #expect(parsed.dayLow == nil)
    }
    let reversed = try #require(QuoteParser.parse(record(changes: [33: "1700", 34: "1800"]))["sh600519"])
    #expect(reversed.dayHigh == nil && reversed.dayLow == nil)
    let partial = try #require(QuoteParser.parse(record(changes: [33: "1800", 34: "0"]))["sh600519"])
    #expect(partial.dayHigh == 1800 && partial.dayLow == nil)
    let flat = try #require(QuoteParser.parse(record(changes: [33: "1745", 34: "1745"]))["sh600519"])
    #expect(flat.dayHigh == flat.last && flat.dayLow == flat.last)
}

@Test func legacyQuoteCacheWithoutExtremesRemainsUsable() throws {
    let original = try quote()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object.removeValue(forKey: "dayHigh"); object.removeValue(forKey: "dayLow")
    let restored = try JSONDecoder().decode(Quote.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.isValid && restored.last == 1745)
    #expect(restored.dayHigh == nil && restored.dayLow == nil)
    var invalid = restored
    invalid.dayHigh = 1700
    #expect(!invalid.isValid)
    invalid.dayHigh = 1800; invalid.dayLow = 1800
    #expect(!invalid.isValid)
}

@Test func rejectsMalformedOrNonStockTencentRows() {
    for changes: [Int:String] in [[0:"51"], [2:"600000"], [3:"NaN"], [3:"Infinity"], [3:"1x"], [3:"-1"], [4:"0"], [32:"NaN"], [31:"bad"], [30:"20260230100000"], [30:"20261023250000"], [61:"ZS"], [61:"ETF"], [1:""]] {
        #expect(QuoteParser.parse(record(changes: changes)).isEmpty)
    }
    #expect(QuoteParser.parse(record("sz000001", changes: [0:"51",2:"000001",61:"ZS"])).isEmpty)
    #expect(QuoteParser.parse(record("sh510300", changes: [2:"510300",61:"LOF"])).isEmpty)
}

@Test func parsesCapturedChiNextAndStarMarketQuotes() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("docs/fixtures/quotes-20261024-boards.txt"), encoding: .utf8)
    let parsed = QuoteParser.parse(text)
    let expected = ["sz300750":"宁德时代", "sz300059":"东方财富", "sz301269":"华大九天", "sz301236":"软通动力", "sh688981":"中芯国际", "sh689009":"九号公司-WD", "sz000001":"平安银行", "sh600519":"贵州茅台", "sz159915":"创业板ETF易方达"]
    #expect(Set(parsed.keys) == Set(expected.keys))
    for (id, name) in expected { #expect(parsed[id]?.name == name) }
    #expect(parsed["sz300750"]?.change == dec("17.19"))
    #expect(parsed["sz301269"]?.percent == dec("10.97"))
    #expect(parsed["sz399006"] == nil)
    #expect(parsed["sz159915"]?.last == dec("2.702"))
}

@Test func rejectsSecurityCategoriesThatDoNotMatchTheBoard() {
    for (raw, market, category) in [("sz300750", "51", "GP-A"), ("sz301269", "51", "GP-A-KCB"), ("sz000001", "51", "GP-A-CYB"), ("sh688981", "1", "GP-A-CYB"), ("sh600519", "1", "GP-A-KCB"), ("bj920002", "62", "GP-A-CYB"), ("sz300750", "51", "ETF")] {
        let input = record(raw, changes: [0:market, 2:String(raw.suffix(6)), 61:category])
        #expect(QuoteParser.parse(input).isEmpty)
    }
}

@Test func handlesTradingSessionBoundariesInShanghai() {
    for text in ["2026-10-23T01:30:00Z", "2026-10-23T03:30:00Z", "2026-10-23T05:00:00Z", "2026-10-23T07:00:00Z"] { #expect(MarketClock.isTradingTime(date(text))) }
    for text in ["2026-10-23T01:29:59Z", "2026-10-23T03:30:01Z", "2026-10-23T04:00:00Z", "2026-10-23T07:00:01Z", "2026-10-24T02:00:00Z"] { #expect(!MarketClock.isTradingTime(date(text))) }
    #expect(MarketClock.day(date("2026-10-22T16:30:00Z")) == "2026-10-23")
}

@Test func requiresFreshSameDayNonfutureSessionTimestamp() throws {
    #expect(MarketClock.isFresh(try quote(at: friday.addingTimeInterval(-180)), now: friday))
    for timestamp in [friday.addingTimeInterval(-181), friday.addingTimeInterval(1), date("2026-10-22T02:00:00Z")] { #expect(!MarketClock.isFresh(try quote(at: timestamp), now: friday)) }
    #expect(!MarketClock.isFresh(try quote(at: date("2026-10-23T01:29:59Z")), now: date("2026-10-23T01:30:01Z")))
    #expect(!MarketClock.isFresh(try quote(at: date("2026-10-23T03:30:00Z")), now: date("2026-10-23T03:30:01Z")))
}

@Test func alertEqualityDedupeDirectionAndThresholdIdentity() throws {
    var item = WatchItem(symbol: try StockSymbol("600519"), name: "贵州茅台")
    item.rule.upEnabled = true; item.rule.downEnabled = true
    let q = try quote(last: "103", previous: "100", percent: "3")
    let first = AlertEvaluator.candidates(items: [item], quotes: [item.id:q], delivered: [:], now: friday)
    let c = try #require(first.first)
    #expect(first.count == 1)
    #expect(c.day == "2026-10-23")
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id:q], delivered: [c.key:c.day], now: friday).isEmpty)
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id:q], delivered: [c.key:"2026-10-22"], now: friday).count == 1)
    item.rule.upThreshold = 2
    let changed = try #require(AlertEvaluator.candidates(items: [item], quotes: [item.id:q], delivered: [c.key:c.day], now: friday).first)
    #expect(changed.key != c.key)
    let down = try quote(last: "98", previous: "100", percent: "-2")
    let downward = try #require(AlertEvaluator.candidates(items: [item], quotes: [item.id:down], delivered: [:], now: friday).first)
    #expect(downward.key != c.key)
    #expect(AlertEvaluator.candidates(items: [item], quotes: [item.id:q], delivered: [:], now: friday.addingTimeInterval(181)).isEmpty)
}

@Test func portfolioRequiresEveryHeldQuoteAndIgnoresZeroHoldings() throws {
    let a = try StockSymbol("600519"), b = try StockSymbol("000001"), c = try StockSymbol("300750")
    let items = [WatchItem(symbol:a,name:"A",holding:Holding(quantity:100,averageCost:1700)), WatchItem(symbol:b,name:"B",holding:Holding(quantity:1000,averageCost:11)), WatchItem(symbol:c,name:"C",holding:Holding(quantity:100,averageCost:100))]
    let quotes = [a.rawValue:try quote(), b.rawValue:try quote("000001",last:"10.1",previous:"10.3",percent:"-1.94"), c.rawValue:try quote("300750",last:"107.4",previous:"104.8",percent:"2.48")]
    let all = PortfolioSummary(items:items,quotes:quotes)
    #expect(all.daily == 1711)
    #expect(all.floating == 4340)
    let missing = PortfolioSummary(items:items,quotes:[a.rawValue:quotes[a.rawValue]!])
    #expect(missing.daily == nil && missing.floating == nil)
    #expect(missing.missingSymbols == [b.rawValue,c.rawValue])
    let empty = PortfolioSummary(items:[WatchItem(symbol:a,name:"A")],quotes:[:])
    #expect(empty.daily == 0 && empty.floating == 0)
}

@Test func stateRoundTripPreservesDeliveryAndRejectsDamage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("state.json")
    let file = StateFile(url:url)
    #expect(try file.load() == SavedState())
    var state = SavedState()
    state.items = [WatchItem(symbol:try StockSymbol("600519"),name:"贵州茅台",holding:Holding(quantity:100,averageCost:1700))]
    state.items[0].rule.upEnabled = true
    state.pinnedSymbol = "sh600519"
    let currentQuote = try quote(last: "103", previous: "100", percent: "3")
    let candidate = try #require(AlertEvaluator.candidates(items:state.items, quotes:["sh600519":currentQuote], delivered:[:], now:friday).first)
    state.delivered = [candidate.key:candidate.day]
    state.assignMissingAliases()
    try file.save(state)
    let reloaded = try file.load()
    #expect(reloaded == state)
    #expect(AlertEvaluator.candidates(items:reloaded.items, quotes:["sh600519":currentQuote], delivered:reloaded.delivered, now:friday).isEmpty)
    let damaged = Data("{broken".utf8)
    try damaged.write(to:url)
    #expect(throws: (any Error).self) { try file.load() }
    #expect(try Data(contentsOf:url) == damaged)
    #expect(throws: (any Error).self) { try file.save(state) }
    #expect(try Data(contentsOf:url) == damaged)
}

@Test func savedStateValidatesNestedAndDuplicateData() throws {
    let a = WatchItem(symbol:try StockSymbol("600519"),name:"贵州茅台")
    var state = SavedState()
    state.items = [a,a]
    #expect(throws: (any Error).self) { try state.validate() }
    state.items = [a]; state.items[0].holding.quantity = -1
    #expect(throws: (any Error).self) { try state.validate() }
    state.items = [a]; state.pinnedSymbol = "sz000001"
    #expect(throws: (any Error).self) { try state.validate() }
    let invalid = Data("{\"rawValue\":\"sh000001\"}".utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(StockSymbol.self,from:invalid) }
}

@Test func parsesCapturedLiveAShareAndETFRowsAndRejectsIndex() throws {
    let captured = """
    v_sh600519="1~贵州茅台~600519~1335.00~1318.49~1311.84~57686~31159~26527~1333.00~6~1331.00~2~1330.00~2~1329.50~3~1329.02~1~1335.00~116~1335.01~2~1335.14~2~1335.19~1~1335.20~1~~20261023161458~16.51~1.25~1343.88~1310.00~1335.00/57686/7677216283~57686~767722~0.46~20.49~~1343.88~1310.00~2.57~16688.59~16688.59~6.64~1450.34~1186.64~1.53~-108~1330.86~18.74~20.27~~~0.02~767721.6283~120.1500~9~   A~GP-A~-1.05~0.45~3.90~32.41~27.30~1539.98~1151.01~5.70~5.37~3.33~1250081601~1250081601~-79.41~0.90~1250081601~~~-5.72~0.57~~CNY~0~___D__F__N~1335.41~-44~";
    v_sz000001="51~平安银行~000001~11.20~11.30~11.27~1448806~695504~753301~11.20~9557~11.19~12196~11.18~7747~11.17~8122~11.16~9094~11.21~554~11.22~2801~11.23~2036~11.24~2851~11.25~2394~~20261023161500~-0.10~-0.88~11.35~11.17~11.20/1448806/1628277173~1448806~162828~0.75~5.00~~11.35~11.17~1.59~2173.44~2173.46~0.46~12.43~10.17~1.26~36080~11.24~4.16~5.10~~~0.18~162827.7173~25.5360~228~   A~GP-A~3.69~-2.61~5.44~7.93~0.72~11.89~9.74~-3.36~-1.42~3.41~19405684991~19405918198~62.91~7.06~19405684991~~~1.62~0.09~~CNY~0~~11.11~16500~";
    v_bj920002="62~万达轴承~920002~52.64~48.99~47.10~26548~15183~11365~52.62~7~52.61~10~52.60~75~52.59~168~52.58~8~52.64~4~52.65~13~52.66~57~52.67~10~52.68~60~~20261023153600~3.65~7.45~53.00~47.10~52.64/26548/134220260~26548~13422.03~5.95~52.25~~53.00~47.10~12.04~23.48~33.53~4.41~63.68~34.30~1.68~124~50.56~47.33~53.50~~~~13422.0260~0.0000~0~ ~GP~-32.82~13.69~0.00~8.45~7.69~88.34~45.26~5.28~5.45~6.45~44597153~63704155~30.10~-31.93~44597153~~~-33.90~-0.08~~CNY~1~NBFND~0.00~0";
    v_bj430047="62~诺思兰德~430047~8.17~8.17~0.00~0~0~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~~20261023090000~0.00~0.00~0.00~0.00~8.17/0/0~0~0.00~0.00~-35.46~C~0.00~0.00~0.00~14.71~22.41~9.03~-1~-1~0.00~0~0.00~-38.40~-41.71~~~~0.0000~0.0000~0~ ~GP~0.00~0.00~0.00~-25.45~-12.62~~~0.00~0.00~0.00~180106427~274271974~~0.00~180106427~~~0.00~0.00~~CNY~4~~0.00~0";
    v_bj920047="62~诺思兰德~920047~13.28~13.31~13.18~47735~24745~22991~13.28~231~13.27~3~13.26~23~13.25~96~13.24~1~13.29~20~13.30~468~13.31~5~13.32~15~13.33~71~~20261023153600~-0.03~-0.23~13.48~12.96~13.28/47735/63082748~47735~6308.27~2.65~-57.64~~13.48~12.96~3.91~23.92~36.42~14.67~17.30~9.32~1.82~-225~13.22~-62.42~-67.80~~~~6308.2748~0.0000~0~ ~GP~-43.99~-4.46~0.00~-25.45~-12.62~35.20~12.96~-12.52~-9.10~-24.29~180106427~274271974~-24.12~-40.98~180106427~~~-47.51~0.08~~CNY~5~NBFND~0.00~0";
    v_sz399001="51~深证成指~399001~11673.83~11357.32~11187.55~690752095~0~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~~20261023161454~316.51~2.79~11707.15~11043.31~11673.83/690752095/1057616973533~690752095~105761697~2.79~35.89~~11707.15~11043.31~5.84~331537.29~389972.56~0.00~-1~-1~1.38~0~11317.89~~~~~~105761697.3533~0.0000~0~ ~ZS~-13.69~-1.09~~~~16374.02~11043.31~-7.66~-12.95~-17.34~2467091205926~~-2.58~-18.11~2467091205926~~~-10.38~0.06~~CNY~0~~0.00~0~";
    v_sh510300="1~沪深300ETF华泰柏瑞~510300~4.178~4.107~4.080~37556082~22353880~15202202~4.178~31015~4.177~39935~4.176~12886~4.175~8912~4.174~6044~4.179~6605~4.180~12856~4.181~1659~4.182~1973~4.183~5183~~20261023161441~0.071~1.73~4.186~4.031~4.178/37556082/15423238067~37556082~1542324~11.47~~~4.186~4.031~3.77~1367.45~1367.45~0.00~4.518~3.696~1.70~70516~4.107~~~~~~1542323.8067~359.1409~8596~   A~ETF~-9.76~-1.37~~~~5.095~4.031~-4.72~-7.81~-12.72~32729887700~32729887700~55.49~-11.67~32729887700~0.05~4.1759~-8.98~0.10~4.1093~CNY~0~___D__F__N~4.186~-14735~";
    """
    let parsed = QuoteParser.parse(captured)
    #expect(parsed.count == 6)
    #expect(parsed["sh600519"]?.last == 1335)
    #expect(parsed["sz000001"]?.percent == dec("-0.88"))
    #expect(parsed["bj920002"]?.last == dec("52.64"))
    #expect(parsed["bj430047"]?.timestamp == date("2026-10-23T01:00:00Z"))
    #expect(parsed["sz399001"] == nil)
    #expect(parsed["sh510300"]?.change == dec("0.071"))
    #expect(!MarketClock.isFresh(try #require(parsed["bj430047"]), now:friday))
}


@Test func percentConsistencyRejectsCorruptRowsWithoutDroppingValidRows() {
    let corrupt = record(changes:[3:"100",4:"100",31:"0",32:"99"])
    #expect(QuoteParser.parse(corrupt).isEmpty)
    let valid = record("sz000001",changes:[0:"51",1:"平安银行",2:"000001",3:"10.1",4:"10.3",31:"-0.2",32:"-1.94"])
    let partial = QuoteParser.parse(corrupt + valid)
    #expect(partial.count == 1 && partial["sz000001"] != nil)
}

@Test func percentConsistencyAcceptsOnlyHalfOfTwoDecimalDisplayUnit() {
    // Price differences below are independent literal arithmetic against previous=100.
    for (last, change, percent, accepted) in [
        ("101.2345","1.2345","1.23",true),
        ("101.2345","1.2345","1.24",false),
        ("101.235","1.235","1.23",true),
        ("101.235","1.235","1.24",true),
        ("101.235","1.235","1.229999",false),
        ("101.235","1.235","1.240001",false),
        ("98.765","-1.235","-1.23",true),
        ("98.765","-1.235","-1.24",true),
        ("98.765","-1.235","-1.229999",false),
        ("98.765","-1.235","-1.240001",false)
    ] {
        #expect(!QuoteParser.parse(record(changes:[3:last,4:"100",31:change,32:percent])).isEmpty == accepted)
    }
}

@Test func percentConsistencyBlocksDirectQuoteInjectionBeforeAlertsAndSummary() throws {
    var item = WatchItem(symbol:try StockSymbol("600519"),name:"贵州茅台",holding:Holding(quantity:100,averageCost:100))
    item.rule.upEnabled = true
    let corrupt = try quote(last:"100",previous:"100",percent:"99")
    #expect(!MarketClock.isFresh(corrupt,now:friday))
    #expect(AlertEvaluator.candidates(items:[item],quotes:[item.id:corrupt],delivered:[:],now:friday).isEmpty)
    let summary = PortfolioSummary(items:[item],quotes:[item.id:corrupt])
    #expect(summary.daily == nil && summary.floating == nil)
    let rounded = try quote(last:"103.004",previous:"100",percent:"3.00")
    #expect(AlertEvaluator.candidates(items:[item],quotes:[item.id:rounded],delivered:[:],now:friday).count == 1)
}

@Test func migratesLegacyStateWithoutLosingFinancialData() throws {
    let json = #"{"items":[{"symbol":{"rawValue":"sh600519"},"name":"贵州茅台","holding":{"quantity":100,"averageCost":1700},"rule":{"upEnabled":true,"downEnabled":true,"upThreshold":5,"downThreshold":2}}],"pinnedSymbol":"sh600519","menuMode":"dailyProfit","compactRows":true,"delivered":{"sh600519|up|5":"2026-10-23"}}"#
    let state = try JSONDecoder().decode(SavedState.self, from: Data(json.utf8))
    #expect(state.schemaVersion == 2 && state.menuMode == .icon)
    #expect(state.items[0].holding == Holding(quantity:100, averageCost:1700))
    #expect(state.items[0].rule.upThreshold == 5 && state.items[0].rule.delivery == .silent)
    #expect(state.delivered == ["sh600519|up|5":"2026-10-23"])
    #expect(state.pinnedSymbol == "sh600519" && state.compactRows)
    #expect(state.aliases == ["sh600519":"GZMT"] && state.nextAliasIndex == 1)
    #expect(state.unreadAlerts.isEmpty)
}

@Test func newStateRoundTripsModesAliasesAndUnreadReceipts() throws {
    let symbol = try StockSymbol("600519")
    let pending = PendingAlert(key:"sh600519|up|3",day:"2026-10-23",symbol:symbol,percent:3)
    var state = SavedState(items:[WatchItem(symbol:symbol,name:"A",rule:AlertRule(delivery:.system))], menuMode:.stock, delivered:[pending.key:pending.day], aliases:[symbol.rawValue:"观察一"], nextAliasIndex:7, unreadAlerts:[pending])
    try state.validate()
    let decoded = try JSONDecoder().decode(SavedState.self,from:JSONEncoder().encode(state))
    #expect(decoded == state)
    #expect(pending.id != PendingAlert(key:pending.key,day:"2026-10-24",symbol:symbol,percent:3).id)
    state.unreadAlerts.removeAll()
    #expect(state.delivered[pending.key] == pending.day)
    #expect(SavedState().menuMode == .icon)
}

@Test func aliasesRemainStableAcrossRemovalAndSkipReservedValues() throws {
    let a = WatchItem(symbol:try StockSymbol("600519"),name:"A")
    let b = WatchItem(symbol:try StockSymbol("000001"),name:"B")
    let c = WatchItem(symbol:try StockSymbol("300750"),name:"C")
    var state = SavedState(items:[a,b], aliases:[a.id:"A02"])
    #expect(state.aliases[b.id] == "B" && state.nextAliasIndex == 1)
    state.items.removeAll { $0.id == b.id }; state.aliases.removeValue(forKey:b.id)
    state.items.append(c); state.assignMissingAliases()
    #expect(state.aliases[a.id] == "A02" && state.aliases[c.id] == "C")
    state.assignMissingAliases()
    #expect(state.nextAliasIndex == 1)
}

@Test func rejectsDamagedNewFieldsAndInvalidAliases() throws {
    let item = WatchItem(symbol:try StockSymbol("600519"),name:"A")
    let base = try JSONEncoder().encode(SavedState(items:[item]))
    let object = try #require(JSONSerialization.jsonObject(with:base) as? [String:Any])
    for (key,value): (String,Any) in [("aliasNamingVersion",2),("aliasNamingVersion",NSNull()),("schemaVersion",3),("schemaVersion",NSNull()),("aliases",NSNull()),("aliases",[item.id:""]), ("aliases",[item.id:"a b"]),("aliases",[item.id:"a\nb"]),("aliases",[item.id:"123456789"]),("nextAliasIndex",0),("nextAliasIndex","2"),("unreadAlerts",NSNull()),("unreadAlerts",[["key":"broken","day":"2026-02-30","symbol":["rawValue":item.id],"percent":3]])] {
        var changed = object; changed[key] = value
        #expect(throws:(any Error).self) { try JSONDecoder().decode(SavedState.self,from:JSONSerialization.data(withJSONObject:changed)) }
    }
    var duplicate = SavedState(items:[item,WatchItem(symbol:try StockSymbol("000001"),name:"B")])
    duplicate.aliases = [item.id:"same","sz000001":"same"]
    #expect(throws:(any Error).self) { try duplicate.validate() }
    for delivery in [#""loud""#, "null", "7"] {
        let json = "{\"upEnabled\":true,\"downEnabled\":false,\"upThreshold\":3,\"downThreshold\":2,\"delivery\":\(delivery)}"
        #expect(throws:(any Error).self) { try JSONDecoder().decode(AlertRule.self,from:Data(json.utf8)) }
    }
}

@Test func unreadAlertsValidateIdentityReceiptsAndCrossDayRetention() throws {
    let symbol = try StockSymbol("600519")
    let first = PendingAlert(key:"sh600519|up|3",day:"2026-10-23",symbol:symbol,percent:4)
    let next = PendingAlert(key:first.key,day:"2026-10-24",symbol:symbol,percent:3)
    var state = SavedState(delivered:[first.key:next.day],unreadAlerts:[first,next])
    try state.validate()
    #expect(try JSONDecoder().decode(SavedState.self,from:JSONEncoder().encode(state)) == state)
    state.unreadAlerts = [first,first]
    #expect(throws:(any Error).self) { try state.validate() }
    state.unreadAlerts = [first]; state.delivered = [:]
    #expect(throws:(any Error).self) { try state.validate() }
    for alert in [PendingAlert(key:first.key,day:first.day,symbol:try StockSymbol("000001"),percent:4),PendingAlert(key:first.key,day:first.day,symbol:symbol,percent:2),PendingAlert(key:first.key,day:"2026-02-30",symbol:symbol,percent:4)] {
        #expect(throws:(any Error).self) { try JSONDecoder().decode(PendingAlert.self,from:JSONEncoder().encode(alert)) }
    }
}

@Test func damagedNewStateFileRemainsUntouchedAndCannotBeOverwritten() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let url = folder.appendingPathComponent("state.json")
    var json = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(SavedState())) as? [String:Any])
    json["nextAliasIndex"] = -1
    let damaged = try JSONSerialization.data(withJSONObject:json)
    try damaged.write(to:url)
    let file = StateFile(url:url)
    #expect(throws:(any Error).self) { try file.load() }
    #expect(throws:(any Error).self) { try file.save(SavedState()) }
    #expect(try Data(contentsOf:url) == damaged)
}

@Test func oldSettingsDefaultToNoShortcutWithoutLosingHoldings() throws {
    let original = SavedState(items: [WatchItem(symbol: try StockSymbol("300750"), name: "宁德时代", holding: Holding(quantity: 200, averageCost: 180))])
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    json.removeValue(forKey: "globalShortcut")
    let decoded = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.globalShortcut == nil)
    #expect(decoded.items == original.items)
}

@Test func shortcutRoundTripAndInvalidCombinationsAreRejected() throws {
    var state = SavedState()
    state.globalShortcut = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    let file = StateFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.save(state)
    #expect(try file.load().globalShortcut == GlobalShortcut(keyCode: 49, modifiers: [.control, .option]))
    for shortcut in [GlobalShortcut(keyCode: 49, modifiers: []), GlobalShortcut(keyCode: 0, modifiers: [.command]), GlobalShortcut(keyCode: 53, modifiers: [.control, .option]), GlobalShortcut(keyCode: 999, modifiers: [.control, .option]), GlobalShortcut(keyCode: 49, modifiers: .init(rawValue: 255))] {
        state.globalShortcut = shortcut
        #expect(throws: (any Error).self) { try file.save(state) }
    }
    #expect(try file.load().globalShortcut?.keyCode == 49)
}
