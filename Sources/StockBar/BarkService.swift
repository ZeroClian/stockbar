import Foundation
import Security
import StockCore

@MainActor protocol BarkKeyStoring {
    func read() throws -> String?
    func write(_ key: String?) throws
}

enum BarkFailure: LocalizedError {
    case keychain, missingKey, invalidKey, unavailable, rejected, oversized
    var errorDescription: String? {
        switch self {
        case .keychain: return "无法访问 Bark 钥匙串，请允许 Tickfin 访问或重新保存密钥。"
        case .missingKey: return "请先在偏好 → Bark 推送中启用并保存设备密钥。"
        case .invalidKey: return "设备密钥格式无效，请只填写 Bark 设备密钥，不要填写整个推送网址。"
        case .unavailable: return "Bark 连接失败，稍后会重试仍满足条件的提醒。"
        case .rejected: return "Bark 未确认接收，请检查服务地址和设备密钥。"
        case .oversized: return "通知内容过长，请缩短标题或补充说明。"
        }
    }
    static func validateKey(_ key: String) throws {
        guard (1...256).contains(key.utf8.count),
              key.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw invalidKey }
    }
}

@MainActor final class BarkKeychain: BarkKeyStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.stockbar.app.bark", kSecAttrAccount as String: "device-key"]
    }
    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw BarkFailure.keychain }
        return key
    }
    func write(_ key: String?) throws {
        guard let key else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BarkFailure.keychain }
            return
        }
        try BarkFailure.validateKey(key)
        let values = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BarkFailure.keychain }
        } else if status != errSecSuccess { throw BarkFailure.keychain }
    }
}

@MainActor protocol BarkSending {
    func send(configuration: BarkConfiguration, key: String, message: BarkMessage) async throws
}

/// Never forward device keys through HTTP redirects or persist network caches.
final class BarkRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class BarkService: BarkSending {
    typealias Request = (URLRequest) async throws -> (Data, URLResponse)
    private let request: Request
    init(request: @escaping Request = { request in
        let session = URLSession(configuration: .ephemeral, delegate: BarkRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }) { self.request = request }

    func send(configuration: BarkConfiguration, key: String, message: BarkMessage) async throws {
        try configuration.validate(); try BarkFailure.validateKey(key)
        guard let endpoint = configuration.endpoint else { throw BarkFailure.rejected }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "device_key": key, "title": message.title, "body": message.body,
            "group": "Tickfin", "level": "active", "isArchive": "0"
        ])
        guard (request.httpBody?.count ?? 0) <= 3500 else { throw BarkFailure.oversized }
        do {
            let (data, response) = try await self.request(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = object["code"] as? Int, code == 200 else { throw BarkFailure.rejected }
        } catch is CancellationError { throw CancellationError() }
        catch let error as BarkFailure { throw error }
        catch { throw BarkFailure.unavailable } // Do not expose URLs, keys or untrusted response bodies.
    }
}
