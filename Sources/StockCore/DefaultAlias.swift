import Foundation

enum DefaultAlias {
    static func make(for item: WatchItem, reserved: Set<String>) -> String {
        // ICU transliteration reads some common security-name characters in isolation.
        // Keep these finance/place-name readings predictable without a network service.
        let readings = [("银行", "YH"), ("行业", "HY"), ("重庆", "CQ"), ("重工", "ZG"),
                        ("重机", "ZJ"), ("重装", "ZZ"), ("重汽", "ZQ"), ("重药", "CY"),
                        ("厦门", "XM"), ("长", "C")]
        var name = item.name
        for (word, initials) in readings { name = name.replacingOccurrences(of: word, with: " \(initials) ") }
        let source = name as NSString
        let pattern = try! NSRegularExpression(pattern: #"[\p{Han}]+|[A-Za-z0-9]+"#)
        var initials = ""
        for match in pattern.matches(in: name, range: NSRange(location: 0, length: source.length)) {
            let word = source.substring(with: match.range)
            if word.utf8.allSatisfy({ $0 < 128 }) { initials += word.uppercased() }
            else if let latin = word.applyingTransform(.mandarinToLatin, reverse: false)?
                .applyingTransform(.stripCombiningMarks, reverse: false) {
                initials += latin.split(whereSeparator: { $0.isWhitespace }).compactMap { $0.first }.map(String.init).joined().uppercased()
            }
        }
        initials = String(initials.unicodeScalars.filter { (65...90).contains($0.value) || (48...57).contains($0.value) })
        let base = String((initials.isEmpty ? item.symbol.code : initials).prefix(8))
        var candidate = base
        var suffix = 2
        while reserved.contains(candidate) {
            let number = String(suffix)
            candidate = String(base.prefix(max(0, 8 - number.count))) + number
            suffix += 1
        }
        return candidate
    }
}
