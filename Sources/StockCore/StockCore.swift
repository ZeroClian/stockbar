import Foundation

public enum StockCoreError: LocalizedError {
    case invalidValue(String)
    public var errorDescription: String? {
        switch self { case .invalidValue(let message): return message }
    }
}

/// A normalized ordinary A-share code. A matching live provider response is still
/// required to establish that the security actually exists.
public struct StockSymbol: Codable, Hashable, Sendable {
    public let rawValue: String
    public var code: String { String(rawValue.suffix(6)) }
    public var marketName: String {
        switch rawValue.prefix(2) { case "sh": return "沪市"; case "sz": return "深市"; default: return "北交所" }
    }
    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suppliedMarket = value.count == 8 ? String(value.prefix(2)) : nil
        let code = suppliedMarket == nil ? value : String(value.dropFirst(2))
        guard code.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw StockCoreError.invalidValue("请输入六位普通 A 股代码")
        }
        let market: String
        if ["600", "601", "603", "605", "688", "689"].contains(where: code.hasPrefix) { market = "sh" }
        else if ["000", "001", "002", "003", "300", "301"].contains(where: code.hasPrefix) { market = "sz" }
        else if ["920", "43", "83", "87", "88"].contains(where: code.hasPrefix) { market = "bj" }
        else { throw StockCoreError.invalidValue("仅支持沪深北普通 A 股，不支持指数或 ETF") }
        guard suppliedMarket == nil || suppliedMarket == market else { throw StockCoreError.invalidValue("代码与交易所不匹配") }
        rawValue = market + code
    }
    private enum CodingKeys: String, CodingKey { case rawValue }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .rawValue)
        try self.init(raw)
        guard raw == rawValue else { throw StockCoreError.invalidValue("保存的股票代码格式无效") }
    }
}

public struct Quote: Codable, Equatable, Sendable {
    public var symbol: StockSymbol
    public var name: String
    public var last: Decimal
    public var previousClose: Decimal
    /// Percentage points, e.g. 3 means +3%.
    public var percent: Decimal
    public var timestamp: Date
    public var change: Decimal { last - previousClose }
    public init(symbol: StockSymbol, name: String, last: Decimal, previousClose: Decimal, percent: Decimal, timestamp: Date) {
        self.symbol = symbol; self.name = name; self.last = last; self.previousClose = previousClose; self.percent = percent; self.timestamp = timestamp
    }
    fileprivate var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !last.isNaN, last > 0, !previousClose.isNaN, previousClose > 0,
              !percent.isNaN, !change.isNaN, timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
        // Tencent displays percentage points to two decimal places. Accept at most
        // half of that display unit, including either tie rounding convention.
        // Apply this invariant here so direct Quote values cannot bypass parsing.
        let calculated = change / previousClose * 100
        guard !calculated.isNaN else { return false }
        let difference = abs(percent - calculated)
        return !difference.isNaN && difference <= Decimal(5) / 1000
    }
}

public struct Holding: Codable, Equatable, Sendable {
    public var quantity: Int
    public var averageCost: Decimal
    public init(quantity: Int = 0, averageCost: Decimal = 0) { self.quantity = quantity; self.averageCost = averageCost }
    public func validate() throws {
        guard quantity >= 0, !averageCost.isNaN, averageCost >= 0 else { throw StockCoreError.invalidValue("股数和平均成本必须为有限非负数") }
        guard !(averageCost * Decimal(quantity)).isNaN else { throw StockCoreError.invalidValue("持仓金额超出支持范围") }
    }
    public func dailyProfit(_ quote: Quote) -> Decimal { quote.change * Decimal(quantity) }
    public func floatingProfit(_ quote: Quote) -> Decimal { (quote.last - averageCost) * Decimal(quantity) }
    public func profitPercent(_ quote: Quote) -> Decimal? {
        guard quantity > 0, averageCost > 0 else { return nil }
        let value = (quote.last - averageCost) * 100 / averageCost
        return value.isNaN ? nil : value
    }
}

public enum AlertDelivery: String, Codable, Sendable { case silent, system }

public struct AlertRule: Codable, Equatable, Sendable {
    public var delivery: AlertDelivery
    public var upEnabled: Bool
    public var downEnabled: Bool
    public var upThreshold: Decimal
    public var downThreshold: Decimal
    public init(upEnabled: Bool = false, downEnabled: Bool = false, upThreshold: Decimal = 3, downThreshold: Decimal = 2, delivery: AlertDelivery = .silent) {
        self.delivery = delivery
        self.upEnabled = upEnabled; self.downEnabled = downEnabled; self.upThreshold = upThreshold; self.downThreshold = downThreshold
    }
    private enum CodingKeys: String, CodingKey { case upEnabled, downEnabled, upThreshold, downThreshold, delivery }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upEnabled = try c.decode(Bool.self, forKey: .upEnabled)
        downEnabled = try c.decode(Bool.self, forKey: .downEnabled)
        upThreshold = try c.decode(Decimal.self, forKey: .upThreshold)
        downThreshold = try c.decode(Decimal.self, forKey: .downThreshold)
        delivery = c.contains(.delivery) ? try c.decode(AlertDelivery.self, forKey: .delivery) : .silent
        try validate()
    }
    public func validate() throws {
        guard !upThreshold.isNaN, upThreshold > 0, !downThreshold.isNaN, downThreshold > 0 else { throw StockCoreError.invalidValue("提醒阈值必须是有限且大于零的数值") }
    }
}

public struct WatchItem: Codable, Equatable, Identifiable, Sendable {
    public var symbol: StockSymbol
    public var name: String
    public var holding: Holding
    public var rule: AlertRule
    public var id: String { symbol.rawValue }
    public init(symbol: StockSymbol, name: String, holding: Holding = Holding(), rule: AlertRule = AlertRule()) { self.symbol = symbol; self.name = name; self.holding = holding; self.rule = rule }
}

public enum MenuMode: String, Codable, Sendable { case icon, stock, dailyProfit }

public struct SavedState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var aliases: [String: String]
    public var nextAliasIndex: Int
    public var unreadAlerts: [PendingAlert]
    public var items: [WatchItem]
    public var pinnedSymbol: String?
    public var menuMode: MenuMode
    public var compactRows: Bool
    /// Rule identity -> Shanghai calendar date. Committed atomically with silent unread alerts or after successful system submission.
    public var delivered: [String: String]
    public init(items: [WatchItem] = [], pinnedSymbol: String? = nil, menuMode: MenuMode = .icon, compactRows: Bool = false, delivered: [String: String] = [:], schemaVersion: Int = 2, aliases: [String: String] = [:], nextAliasIndex: Int = 1, unreadAlerts: [PendingAlert] = []) {
        self.schemaVersion = schemaVersion; self.aliases = aliases; self.nextAliasIndex = nextAliasIndex; self.unreadAlerts = unreadAlerts
        self.items = items; self.pinnedSymbol = pinnedSymbol; self.menuMode = menuMode; self.compactRows = compactRows; self.delivered = delivered
        assignMissingAliases()
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, items, pinnedSymbol, menuMode, compactRows, delivered, aliases, nextAliasIndex, unreadAlerts }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = c.contains(.schemaVersion) ? try c.decode(Int.self, forKey: .schemaVersion) : 1
        guard version == 1 || version == 2 else { throw StockCoreError.invalidValue("保存的数据版本不受支持") }
        schemaVersion = 2
        items = try c.decode([WatchItem].self, forKey: .items)
        pinnedSymbol = try c.decodeIfPresent(String.self, forKey: .pinnedSymbol)
        let savedMode = try c.decode(MenuMode.self, forKey: .menuMode)
        menuMode = version < 2 ? .icon : savedMode
        compactRows = try c.decode(Bool.self, forKey: .compactRows)
        delivered = try c.decode([String:String].self, forKey: .delivered)
        aliases = c.contains(.aliases) ? try c.decode([String:String].self, forKey: .aliases) : [:]
        nextAliasIndex = c.contains(.nextAliasIndex) ? try c.decode(Int.self, forKey: .nextAliasIndex) : 1
        unreadAlerts = c.contains(.unreadAlerts) ? try c.decode([PendingAlert].self, forKey: .unreadAlerts) : []
        guard nextAliasIndex > 0 else { throw StockCoreError.invalidValue("代号序号无效") }
        assignMissingAliases()
        try validate()
    }
    /// Stable, monotonically allocated names; stale aliases also reserve their values.
    public mutating func assignMissingAliases() {
        guard nextAliasIndex > 0 else { return }
        var used = Set(aliases.values)
        for item in items where aliases[item.id] == nil {
            while nextAliasIndex < Int.max && used.contains(String(format: "A%02lld", nextAliasIndex)) { nextAliasIndex += 1 }
            guard nextAliasIndex < Int.max else { return }
            let alias = String(format: "A%02lld", nextAliasIndex)
            aliases[item.id] = alias; used.insert(alias); nextAliasIndex += 1
        }
        while nextAliasIndex < Int.max && used.contains(String(format: "A%02lld", nextAliasIndex)) { nextAliasIndex += 1 }
    }
    public func validate() throws {
        guard schemaVersion == 2, nextAliasIndex > 0, nextAliasIndex < Int.max else { throw StockCoreError.invalidValue("保存的数据版本或代号序号无效") }
        var usedAliases = Set<String>()
        for (symbol, alias) in aliases {
            guard (try? StockSymbol(symbol).rawValue) == symbol, (1...8).contains(alias.count),
                  !alias.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
                  usedAliases.insert(alias).inserted else { throw StockCoreError.invalidValue("代号应为1–8个字符，不含空白且不能重复") }
        }
        var unreadIDs = Set<String>()
        for alert in unreadAlerts {
            try alert.validate()
            guard unreadIDs.insert(alert.id).inserted, let receiptDay = delivered[alert.key], receiptDay >= alert.day else { throw StockCoreError.invalidValue("未读提醒缺少去重记录或存在重复") }
        }
        var ids = Set<String>()
        for item in items {
            guard try StockSymbol(item.id).rawValue == item.id,
                  !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(item.id).inserted else { throw StockCoreError.invalidValue("自选股数据无效或存在重复代码") }
            try item.holding.validate()
            try item.rule.validate()
        }
        if let pinnedSymbol, !ids.contains(pinnedSymbol) { throw StockCoreError.invalidValue("状态栏股票不在自选列表内") }
        for (key, day) in delivered {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let symbol = try? StockSymbol(parts[0]), symbol.rawValue == parts[0],
                  ["up", "down"].contains(parts[1]), let threshold = strictDecimal(parts[2]), threshold > 0,
                  validDay(day) else { throw StockCoreError.invalidValue("提醒去重记录无效") }
        }
    }
}

public struct PendingAlert: Codable, Equatable, Identifiable, Sendable {
    public var key: String
    public var day: String
    public var symbol: StockSymbol
    public var percent: Decimal
    public var id: String { day + "|" + key }
    public init(key: String, day: String, symbol: StockSymbol, percent: Decimal) {
        self.key = key; self.day = day; self.symbol = symbol; self.percent = percent
    }
    private enum CodingKeys: String, CodingKey { case key, day, symbol, percent }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        day = try c.decode(String.self, forKey: .day)
        symbol = try c.decode(StockSymbol.self, forKey: .symbol)
        percent = try c.decode(Decimal.self, forKey: .percent)
        try validate()
    }
    public func validate() throws {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == symbol.rawValue, ["up", "down"].contains(parts[1]),
              let threshold = strictDecimal(parts[2]), threshold > 0, validDay(day), !percent.isNaN,
              (parts[1] == "up" ? percent >= threshold : percent <= -threshold) else { throw StockCoreError.invalidValue("未读提醒无效") }
    }
}

public enum QuoteParser {
    public static func parse(_ text: String) -> [String: Quote] {
        // Leave the separator semicolon unconsumed, so adjacent assignments also match.
        let pattern = #"(?:^|[;\r\n])\s*v_([a-z]{2}[0-9]{6})\s*=\s*"([^"\r\n]*)"(?=\s*(?:;|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var quotes: [String: Quote] = [:]
        let string = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let raw = string.substring(with: match.range(at: 1))
            let fields = string.substring(with: match.range(at: 2)).components(separatedBy: "~")
            guard let symbol = try? StockSymbol(raw), fields.count > 61,
                  fields[2] == symbol.code,
                  fields[0] == ["sh":"1", "sz":"51", "bj":"62"][String(raw.prefix(2))],
                  fields[61] == securityCategory(for: symbol),
                  let last = strictDecimal(fields[3]), let previous = strictDecimal(fields[4]),
                  let change = strictDecimal(fields[31]), let percent = strictDecimal(fields[32]),
                  let timestamp = parseTimestamp(fields[30]) else { continue }
            let quote = Quote(symbol: symbol, name: fields[1].trimmingCharacters(in: .whitespacesAndNewlines), last: last, previousClose: previous, percent: percent, timestamp: timestamp)
            guard quote.isValid, quote.change == change else { continue }
            // If a provider repeats a symbol, retain its most recent valid row.
            if let old = quotes[raw], old.timestamp > timestamp { continue }
            quotes[raw] = quote
        }
        return quotes
    }

    private static func securityCategory(for symbol: StockSymbol) -> String {
        if symbol.rawValue.hasPrefix("bj") { return "GP" }
        // Tencent identifies ChiNext and STAR with separate A-share categories.
        // Match the code's board explicitly instead of accepting arbitrary GP-* types.
        if symbol.code.hasPrefix("300") || symbol.code.hasPrefix("301") { return "GP-A-CYB" }
        if symbol.code.hasPrefix("688") || symbol.code.hasPrefix("689") { return "GP-A-KCB" }
        return "GP-A"
    }
}

public enum MarketClock {
    fileprivate static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    public static func isTradingTime(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        let c = calendar.dateComponents([.weekday, .hour, .minute, .second, .nanosecond], from: date)
        guard let weekday = c.weekday, (2...6).contains(weekday), let h = c.hour, let m = c.minute, let s = c.second else { return false }
        let seconds = h * 3600 + m * 60 + s
        // Include exactly 11:30:00 and 15:00:00, not the rest of those seconds.
        if seconds == 11 * 3600 + 30 * 60 || seconds == 15 * 3600 { return (c.nanosecond ?? 0) == 0 }
        return (seconds >= 9 * 3600 + 30 * 60 && seconds < 11 * 3600 + 30 * 60) || (seconds >= 13 * 3600 && seconds < 15 * 3600)
    }
    public static func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func isFresh(_ quote: Quote, now: Date) -> Bool {
        guard quote.isValid, isTradingTime(now), isTradingTime(quote.timestamp), day(now) == day(quote.timestamp) else { return false }
        let age = now.timeIntervalSince(quote.timestamp)
        return age >= 0 && age <= 180
    }
}

public struct AlertCandidate: Equatable, Sendable {
    public var key: String
    public var day: String
    public var symbol: StockSymbol
    public var title: String
    public var body: String
    public init(key: String, day: String, symbol: StockSymbol, title: String, body: String) { self.key = key; self.day = day; self.symbol = symbol; self.title = title; self.body = body }
}

public enum AlertEvaluator {
    /// Pure evaluation only; the app commits delivered[key] after notification submission succeeds.
    public static func candidates(items: [WatchItem], quotes: [String: Quote], delivered: [String: String], now: Date) -> [AlertCandidate] {
        var result: [AlertCandidate] = []
        var seen = Set<String>()
        let day = MarketClock.day(now)
        for item in items {
            guard (try? item.rule.validate()) != nil, let quote = quotes[item.id], quote.symbol == item.symbol, MarketClock.isFresh(quote, now: now) else { continue }
            let checks: [(String, Bool, Decimal, Bool)] = [
                ("up", item.rule.upEnabled, item.rule.upThreshold, quote.percent >= item.rule.upThreshold),
                ("down", item.rule.downEnabled, item.rule.downThreshold, quote.percent <= -item.rule.downThreshold)
            ]
            for (direction, enabled, threshold, reached) in checks where enabled && reached {
                let thresholdText = NSDecimalNumber(decimal: threshold).stringValue
                let key = "\(item.id)|\(direction)|\(thresholdText)"
                guard delivered[key] != day, seen.insert(key).inserted else { continue }
                let label = direction == "up" ? "上涨" : "下跌"
                let sign = direction == "up" ? "+" : "−"
                let percent = NSDecimalNumber(decimal: quote.percent).stringValue
                result.append(AlertCandidate(key: key, day: day, symbol: item.symbol, title: "\(item.name)\(label)提醒", body: "涨跌幅 \(quote.percent >= 0 ? "+" : "")\(percent)%，已达到 \(sign)\(thresholdText)% 阈值"))
            }
        }
        return result
    }
}

public struct PortfolioSummary: Sendable {
    public var daily: Decimal?
    public var floating: Decimal?
    public var missingSymbols: [String]
    /// The caller supplies only quotes suitable for the UI's current freshness policy.
    public init(items: [WatchItem], quotes: [String: Quote]) {
        var daily: Decimal = 0
        var floating: Decimal = 0
        var missing: [String] = []
        for item in items where item.holding.quantity > 0 {
            guard (try? item.holding.validate()) != nil, let quote = quotes[item.id], quote.symbol == item.symbol, quote.isValid else { missing.append(item.id); continue }
            let d = item.holding.dailyProfit(quote), f = item.holding.floatingProfit(quote)
            guard !d.isNaN, !f.isNaN, !(daily + d).isNaN, !(floating + f).isNaN else { missing.append(item.id); continue }
            daily += d; floating += f
        }
        self.missingSymbols = missing
        self.daily = missing.isEmpty ? daily : nil
        self.floating = missing.isEmpty ? floating : nil
    }
}

public struct StateFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> SavedState {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return SavedState() }
        let state = try JSONDecoder().decode(SavedState.self, from: data)
        try state.validate()
        return state
    }
    public func save(_ state: SavedState) throws {
        try state.validate()
        // An invalid on-disk file must remain available for recovery, even if a caller
        // accidentally attempts to save default state after a failed load.
        _ = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private func strictDecimal(_ text: String) -> Decimal? {
    guard text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
          let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
    return value
}

private func parseTimestamp(_ text: String) -> Date? {
    guard text.count == 14, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = MarketClock.calendar
    formatter.timeZone = MarketClock.calendar.timeZone
    formatter.dateFormat = "yyyyMMddHHmmss"
    formatter.isLenient = false
    guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
    return value
}

private func validDay(_ text: String) -> Bool {
    guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
    return parseTimestamp(text.replacingOccurrences(of: "-", with: "") + "100000") != nil
}
