import SwiftUI
import StockCore

// Explicit alias avoids the new SDK State macro when building with Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

enum UI {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondary = Color.secondary
    static func color(_ value: Decimal) -> Color {
        .primary
    }
    static func number(_ value: Decimal, signed: Bool = false, digits: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.roundingMode = .halfUp
        let negative = value < 0
        let absolute = negative ? -value : value
        let text = f.string(from: NSDecimalNumber(decimal: absolute)) ?? "—"
        // Avoid displaying a negative or positive zero after rounding.
        let roundedZero = NSDecimalNumber(string: text.replacingOccurrences(of: ",", with: "")).compare(NSDecimalNumber.zero) == .orderedSame
        return (negative && !roundedZero ? "−" : signed && value > 0 && !roundedZero ? "+" : "") + text
    }
    static func input(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func decimal(_ text: String) -> Decimal? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: #"^\d+(\.\d{1,4})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
        return value
    }
    static func time(_ date: Date, full: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = full ? "MM-dd HH:mm:ss" : "HH:mm:ss"
        return f.string(from: date)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 22, height: 24)
                .foregroundColor(active ? .primary : .secondary)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct SignedNumber: View {
    let value: Decimal?
    var suffix = ""
    var size: CGFloat = 12
    var body: some View {
        Text(value.map { UI.number($0, signed: true) + suffix } ?? "—")
            .font(.system(size: size, weight: .regular)).monospacedDigit()
            .foregroundColor(value.map(UI.color) ?? .secondary).lineLimit(1).minimumScaleFactor(0.75)
    }
}
