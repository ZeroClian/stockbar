import Foundation

public struct PriceAlertRule: Codable, Equatable, Sendable {
    public var aboveEnabled = false
    public var belowEnabled = false
    public var above: Decimal = 100
    public var below: Decimal = 100
    public init() {}
    public func validate() throws {
        guard !above.isNaN, above > 0, !below.isNaN, below > 0 else {
            throw StockCoreError.invalidValue("目标价格必须是大于零的有效数值")
        }
    }
}

public enum HoldingAlertUnit: String, Codable, Sendable { case amount, percent }

public struct HoldingAlertRule: Codable, Equatable, Sendable {
    public var profitEnabled = false
    public var lossEnabled = false
    public var profit: Decimal = 1000
    public var loss: Decimal = 1000
    public var unit: HoldingAlertUnit = .amount
    public init() {}
    public func validate() throws {
        guard !profit.isNaN, profit > 0, !loss.isNaN, loss > 0 else {
            throw StockCoreError.invalidValue("盈亏阈值必须是大于零的有效数值")
        }
    }
}

public enum AlertKind: String, Sendable {
    case up, down, priceAbove, priceBelow, profitAmount, lossAmount, profitPercent, lossPercent
    public var isHolding: Bool { [.profitAmount, .lossAmount, .profitPercent, .lossPercent].contains(self) }
    public var isPrice: Bool { self == .priceAbove || self == .priceBelow }
    public var usesPercent: Bool { [.up, .down, .profitPercent, .lossPercent].contains(self) }
    public var label: String {
        switch self {
        case .up: return "涨幅提醒"
        case .down: return "跌幅提醒"
        case .priceAbove: return "涨到价格"
        case .priceBelow: return "跌到价格"
        case .profitAmount, .profitPercent: return "持仓盈利"
        case .lossAmount, .lossPercent: return "持仓亏损"
        }
    }
    func reached(_ value: Decimal, threshold: Decimal) -> Bool {
        guard !value.isNaN, !threshold.isNaN, threshold > 0 else { return false }
        switch self {
        case .down, .lossAmount, .lossPercent: return value <= -threshold
        case .priceBelow: return value > 0 && value <= threshold
        default: return value >= threshold
        }
    }
}

struct AlertKey {
    let symbol: StockSymbol
    let kind: AlertKind
    let threshold: Decimal
    init?(_ key: String) {
        let parts = key.components(separatedBy: "|")
        guard parts.count == 3, let symbol = try? StockSymbol(parts[0]), symbol.rawValue == parts[0],
              let kind = AlertKind(rawValue: parts[1]),
              parts[2].range(of: #"^[+]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let threshold = Decimal(string: parts[2], locale: Locale(identifier: "en_US_POSIX")), !threshold.isNaN, threshold > 0 else { return nil }
        self.symbol = symbol; self.kind = kind; self.threshold = threshold
    }
}
