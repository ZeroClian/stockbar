import Foundation
import Combine
import CoreFoundation
import StockCore

struct StockSearchResult: Equatable, Identifiable, Sendable {
    let symbol: StockSymbol
    let name: String
    let initials: String
    var id: String { symbol.rawValue }
}

enum StockSearchError: LocalizedError {
    case invalidQuery, response, format
    var errorDescription: String? {
        switch self {
        case .invalidQuery: return "请输入证券代码或拼音首字母，如 NDSD。"
        case .response: return "搜索服务暂时不可用，请重试；也可输入完整代码。"
        case .format: return "搜索结果无法读取，请稍后重试。"
        }
    }
}

protocol StockSearching {
    func search(_ query: String) async throws -> [StockSearchResult]
}

enum StockSearchParser {
    static func parse(_ text: String, query: String) throws -> [StockSearchResult] {
        let regex = try NSRegularExpression(pattern: #"^\s*v_hint\s*=\s*("(?:[^"\\]|\\.)*")\s*;?\s*$"#)
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              let data = source.substring(with: match.range(at: 1)).data(using: .utf8),
              let payload = try? JSONDecoder().decode(String.self, from: data) else { throw StockSearchError.format }
        if payload == "N" || payload.isEmpty { return [] }
        let results = payload.split(separator: "^").compactMap { row -> StockSearchResult? in
            let fields = row.components(separatedBy: "~")
            guard fields.count == 5, ["sh", "sz", "bj"].contains(fields[0]),
                  let symbol = try? StockSymbol(fields[0] + fields[1]),
                  !fields[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  fields[2].count <= 100 else { return nil }
            let category = fields[4]
            guard symbol.isETF ? category == "ETF" :
                    (fields[0] == "bj" ? ["GP", "GP-A"].contains(category) : ["GP-A", "GP-A-CYB", "GP-A-KCB"].contains(category)) else { return nil }
            return StockSearchResult(symbol: symbol, name: fields[2], initials: fields[3].lowercased())
        }
        return ranked(results, query: query)
    }

    static func ranked(_ results: [StockSearchResult], query: String) -> [StockSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        func score(_ result: StockSearchResult) -> Int {
            let values = [result.symbol.code, result.id, result.initials.lowercased()]
            if values.contains(query) { return 0 }
            if values.contains(where: { $0.hasPrefix(query) }) { return 1 }
            if values.contains(where: { $0.contains(query) }) { return 2 }
            return 3
        }
        var seen = Set<String>()
        return Array(results.enumerated().filter { score($0.element) < 3 }
            .sorted { score($0.element) == score($1.element) ? $0.offset < $1.offset : score($0.element) < score($1.element) }
            .map(\.element).filter { seen.insert($0.id).inserted }.prefix(5))
    }
}

struct StockSearchService: StockSearching {
    var session: URLSession = .shared
    var quotes: any QuoteProviding = QuoteService()

    func search(_ query: String) async throws -> [StockSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.range(of: #"^[a-z0-9]{1,32}$"#, options: .regularExpression) != nil else { throw StockSearchError.invalidQuery }
        // Full codes continue working independently of the suggestion service, including Beijing listings.
        if let symbol = try? StockSymbol(query) {
            let result = try await quotes.fetch([symbol])
            try Task.checkCancellation()
            guard let quote = result[symbol.rawValue], quote.isValid, quote.symbol == symbol else { return [] }
            return [StockSearchResult(symbol: symbol, name: quote.name, initials: "")]
        }
        var results = try await suggestions(query)
        // Broad board abbreviations can be crowded out by indices in the provider's first page.
        if results.isEmpty, !query.hasSuffix("etf"), query.rangeOfCharacter(from: .letters) != nil {
            let etfs = try await suggestions(query + "etf")
            results = StockSearchParser.ranked(etfs, query: query)
        }
        return results
    }

    private func suggestions(_ query: String) async throws -> [StockSearchResult] {
        var url = URLComponents(string: "https://smartbox.gtimg.cn/s3/")!
        url.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "t", value: "all")]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StockSearchError.response }
        guard data.count <= 256_000 else { throw StockSearchError.format }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb) else { throw StockSearchError.format }
        return try StockSearchParser.parse(text, query: query)
    }
}

@MainActor final class StockSearchModel: ObservableObject {
    @Published private(set) var results: [StockSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?
    private let service: any StockSearching
    private var task: Task<Void, Never>?
    private var revision = 0

    init(service: any StockSearching = StockSearchService()) { self.service = service }

    func updateQuery(_ input: String, immediately: Bool = false) {
        cancel()
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return }
        guard query.range(of: #"^[a-z0-9]{1,32}$"#, options: .regularExpression) != nil else {
            message = StockSearchError.invalidQuery.localizedDescription; return
        }
        let current = revision
        isSearching = true
        task = Task { [weak self, service] in
            do {
                if !immediately { try await Task.sleep(nanoseconds: 300_000_000) }
                let found = try await service.search(query)
                try Task.checkCancellation()
                guard let self, self.revision == current else { return }
                self.results = StockSearchParser.ranked(found, query: query)
                self.message = self.results.isEmpty ? "未找到匹配的 A 股或 ETF，试试完整代码。" : nil
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.revision == current else { return }
                self.message = error is StockSearchError ? error.localizedDescription : StockSearchError.response.localizedDescription
                self.isSearching = false
            }
        }
    }

    func cancel() {
        revision &+= 1
        task?.cancel(); task = nil
        results = []; message = nil; isSearching = false
    }
}
