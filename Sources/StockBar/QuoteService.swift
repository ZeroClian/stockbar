import Foundation
import CoreFoundation
import StockCore

enum QuoteServiceError: LocalizedError {
    case response(Int), encoding, empty
    var errorDescription: String? {
        switch self {
        case .response(let code): return "行情服务返回 HTTP \(code)，请稍后重试。"
        case .encoding: return "行情内容无法解码。"
        case .empty: return "没有取得有效 A 股或 ETF 行情，请检查交易代码。"
        }
    }
}

protocol QuoteProviding {
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote]
}

struct QuoteService: QuoteProviding {
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] {
        guard !symbols.isEmpty else { return [:] }
        // Symbol validation keeps requests restricted to supported security identifiers.
        let ids = Array(Set(symbols.map(\.rawValue))).sorted()
        var all: [String: Quote] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = Array(ids[start..<min(start + 50, ids.count)])
            var components = URLComponents(string: "https://qt.gtimg.cn/")!
            components.queryItems = [URLQueryItem(name: "q", value: batch.joined(separator: ","))]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw QuoteServiceError.response(status) }
            let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            guard let text = String(data: data, encoding: gb) else { throw QuoteServiceError.encoding }
            for (id, quote) in QuoteParser.parse(text) where batch.contains(id) { all[id] = quote }
        }
        return all
    }
}
