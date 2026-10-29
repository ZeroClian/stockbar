import Foundation

/// Only non-secret preferences are stored with the portfolio. Device keys live in Keychain.
public struct BarkConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var server = "https://api.day.app"
    public var title = "自选提醒"
    public var note = "打开 Tickfin 查看。"
    public var includeValues = false
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

    public init(configuration: BarkConfiguration, alias: String, candidate: AlertCandidate, quote: Quote, test: Bool = false) throws {
        try configuration.validate()
        guard let key = AlertKey(candidate.key), key.symbol == quote.symbol, candidate.symbol == quote.symbol,
              let value = candidate.value, key.kind.reached(value, threshold: key.threshold) else {
            throw StockCoreError.invalidValue("提醒数据无效，未发送 Bark 通知。")
        }
        title = test ? "测试 · " + configuration.title : configuration.title
        note = configuration.note
        var lines = ["证券代号：\(alias)", "触发规则：\(key.kind.label)"]
        if test { lines.insert("测试通知 · 示例数据，非真实触发", at: 0) }
        if configuration.includeValues {
            let digits = key.kind.isPrice ? quote.symbol.priceFractionDigits : 2
            let unit = key.kind.usesPercent ? "%" : "元"
            let negative = [AlertKind.down, .lossAmount, .lossPercent].contains(key.kind)
            let threshold = negative ? -key.threshold : key.threshold
            lines += ["设置阈值：\(Self.number(threshold, digits: digits))\(unit)",
                      "触发数值：\(Self.number(value, digits: digits))\(unit)"]
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("行情时间：\(formatter.string(from: quote.timestamp))（上海）")
        facts = lines.joined(separator: "\n")
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
