import Foundation

/// Only non-secret preferences are stored with the portfolio. Device keys live in Keychain.
public struct BarkConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var server = "https://api.day.app"
    public var title = "自选提醒" // Legacy preference retained for saved-state compatibility; notification titles follow the rule.
    public var note = "打开 Tickfin 查看。"
    public var includeValues = true // Legacy field retained for decoding; formal notifications always include values.
    public init() {}

    public var endpoint: URL? {
        guard let parts = URLComponents(string: server), parts.scheme == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !server.contains(where: { $0.isWhitespace }), let url = parts.url else { return nil }
        return url.appendingPathComponent("push")
    }
    public func validate() throws {
        guard endpoint != nil, server.utf8.count <= 512 else {
            throw StockCoreError.invalidValue("Bark 服务地址需为 HTTPS 地址，不含密钥、查询参数或登录信息。")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 40,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              note.count <= 120,
              !note.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }) else {
            throw StockCoreError.invalidValue("标题需为 1–40 字单行文字，补充说明最多 120 字。")
        }
    }
}

public struct BarkMessage: Equatable, Sendable {
    public let title: String
    public let facts: String
    public let note: String
    public var body: String { note.isEmpty ? facts : facts + "\n\n补充说明：\n" + note }

    public init(configuration: BarkConfiguration, candidate: AlertCandidate, quote: Quote, test: Bool = false) throws {
        try configuration.validate()
        guard let key = AlertKey(candidate.key), key.symbol == quote.symbol, candidate.symbol == quote.symbol,
              let value = candidate.value, key.kind.reached(value, threshold: key.threshold) else {
            throw StockCoreError.invalidValue("提醒数据无效，未发送 Bark 通知。")
        }
        title = test ? "测试 · " + key.kind.label : key.kind.label
        note = configuration.note
        var lines = ["股票名称：\(quote.name)", "触发规则：\(key.kind.label)"]
        if test { lines.insert("测试通知 · 示例数据，非真实触发", at: 0) }
        let digits = key.kind.isPrice ? quote.symbol.priceFractionDigits : 2
        let unit = key.kind.usesPercent ? "%" : "元"
        let negative = [AlertKind.down, .lossAmount, .lossPercent].contains(key.kind)
        let threshold = negative ? -key.threshold : key.threshold
        lines += ["设置阈值：\(Self.number(threshold, digits: digits))\(unit)",
                  "触发数值：\(Self.number(value, digits: digits))\(unit)"]
        if !key.kind.isPrice {
            lines.append("当前价格：\(Self.number(quote.last, digits: quote.symbol.priceFractionDigits))元")
        }
        facts = lines.joined(separator: "\n")
    }

    /// Test messages deliberately show the selected public quote, never portfolio values.
    public init(testConfiguration configuration: BarkConfiguration, symbol: StockSymbol?, quote: Quote?, name: String? = nil) throws {
        try configuration.validate()
        title = "测试 · 推送测试"
        note = configuration.note
        let matching = quote.flatMap { $0.symbol == symbol && $0.isValid ? $0 : nil }
        let price = matching.map { Self.number($0.last, digits: $0.symbol.priceFractionDigits) } ?? "xxxx"
        let stockName = matching?.name ?? name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "xxxx"
        facts = "测试通知 · 当前关注项，非真实触发\n股票名称：\(stockName)\n股票代码：\(symbol?.code ?? "xxxx")\n当前价格：\(price)"

    }

    private static func number(_ value: Decimal, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = max(digits, 4) // Preserve configured threshold precision.
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
}

/// Imports Bark's standard /device-key/title/body link; never stores sample text or query parameters.
public struct BarkConnection: Equatable, Sendable {
    public let server: String
    public let key: String

    public init(pushURL: String) throws {
        let input = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.utf8.count <= 8192,
              var parts = URLComponents(string: input), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              !input.contains(where: { $0.isWhitespace }),
              let encodedKey = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst().first,
              let key = String(encodedKey).removingPercentEncoding,
              (1...256).contains(key.utf8.count),
              key.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw StockCoreError.invalidValue("请粘贴完整的 HTTPS Bark 推送网址，例如 https://api.day.app/设备密钥。")
        }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let server = parts.url?.absoluteString else {
            throw StockCoreError.invalidValue("Bark 推送网址无效。")
        }
        var configuration = BarkConfiguration(); configuration.server = server
        try configuration.validate()
        self.server = server; self.key = key
    }
}
