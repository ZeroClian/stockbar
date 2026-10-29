import Foundation
import Testing
import UserNotifications
import StockCore
@testable import StockBar

@MainActor private final class BarkKeysStub: BarkKeyStoring {
    var key: String? = "test-device-key"
    var failWrite = false
    func read() throws -> String? { key }
    func write(_ key: String?) throws {
        if failWrite { throw BarkFailure.keychain }
        self.key = key
    }
}
@MainActor private final class BarkSenderStub: BarkSending {
    var messages: [BarkMessage] = []
    var fail = false
    func send(configuration: BarkConfiguration, key: String, message: BarkMessage) async throws {
        messages.append(message)
        if fail { throw BarkFailure.unavailable }
    }
}
private struct BarkQuotesStub: QuoteProviding {
    let quote: Quote
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] { [quote.symbol.rawValue: quote] }
}
@MainActor private final class BarkNotificationsStub: NotificationSending {
    var count = 0
    func status() async -> UNAuthorizationStatus { .notDetermined }
    func requestPermission() async throws -> Bool { count += 1; return false }
    func send(identifier: String, title: String, body: String) async throws { count += 1 }
}
@MainActor private final class BarkFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keys = BarkKeysStub()
    let sender = BarkSenderStub()
    let notifications = BarkNotificationsStub()
    var now = ISO8601DateFormatter().date(from: "2026-10-23T02:00:00Z")!
    var quote: Quote {
        Quote(symbol: try! StockSymbol("600519"), name: "贵州茅台", last: 103, previousClose: 100, percent: 3, timestamp: now)
    }
    init() throws {
        var state = SavedState(items: [WatchItem(symbol: try StockSymbol("600519"), name: "贵州茅台", holding: Holding(quantity: 100, averageCost: 99), rule: AlertRule(upEnabled: true, delivery: .bark))])
        state.bark.enabled = true
        try StateFile(url: root.appendingPathComponent("state.json")).save(state)
    }
    func store() -> AppStore {
        AppStore(dataDirectory: root, service: BarkQuotesStub(quote: quote), notifications: notifications, barkSender: sender, barkKeys: keys, clock: { self.now })
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor @Test func barkUsesPostAndNeverPlacesKeyInURL() async throws {
    var config = BarkConfiguration(); config.includeValues = true
    let message = try BarkPreview.message(configuration: config)
    var requests: [URLRequest] = []
    let service = BarkService { request in
        requests.append(request)
        return (Data(#"{"code":200,"message":"success"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    try await service.send(configuration: config, key: "private-test-key", message: message)
    let request = try #require(requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://api.day.app/push")
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(body["device_key"] == "private-test-key")
    #expect(body["body"] == message.body && body["title"] == message.title)
    #expect(body["level"] == "active" && body["isArchive"] == "0")
}

@MainActor @Test(arguments: [0, 1, 2]) func barkRejectsHTTPAndAPIErrorWithoutLeakingServerText(mode: Int) async throws {
    let service = BarkService { request in
        let data = mode == 2 ? "not-json-private-test-key" : #"{"code":400,"message":"private-test-key"}"#
        return (Data(data.utf8), HTTPURLResponse(url: request.url!, statusCode: mode == 0 ? 500 : 200, httpVersion: nil, headerFields: nil)!)
    }
    do {
        try await service.send(configuration: BarkConfiguration(), key: "private-test-key", message: BarkPreview.message(configuration: BarkConfiguration()))
        Issue.record("Bark failure was accepted")
    } catch { #expect(!error.localizedDescription.contains("private-test-key")) }
}

@MainActor @Test func barkMonitorsClosedPanelAndPersistsReceiptOnlyAfterSuccess() async throws {
    let fixture = try BarkFixture(); defer { fixture.remove() }
    let store = fixture.store()
    store.closePanel()
    await store.refresh()
    #expect(fixture.sender.messages.count == 1 && fixture.notifications.count == 0)
    #expect(fixture.sender.messages[0].body.contains("GZMT"))
    #expect(!fixture.sender.messages[0].body.contains("103") && !fixture.sender.messages[0].body.contains("贵州茅台"))
    #expect(store.state.delivered["sh600519|up|3"] == "2026-10-23")
    #expect(store.state.unreadAlerts.count == 1)
    let restored = fixture.store()
    await restored.refresh()
    #expect(fixture.sender.messages.count == 1)
}

@MainActor @Test func barkFailureRetriesAfterBackoffWithoutConsumingDailyReceipt() async throws {
    let fixture = try BarkFixture(); defer { fixture.remove() }
    fixture.sender.fail = true
    let store = fixture.store()
    await store.refresh()
    #expect(store.state.delivered.isEmpty && store.state.unreadAlerts.isEmpty)
    await store.refresh()
    #expect(fixture.sender.messages.count == 1)
    fixture.now = fixture.now.addingTimeInterval(61)
    fixture.sender.fail = false
    await store.refresh()
    #expect(fixture.sender.messages.count == 2 && store.state.delivered.count == 1)
}

@MainActor @Test func barkSettingsKeepSecretsOutOfStateAndRollbackKeyOnSaveFailure() throws {
    let fixture = try BarkFixture(); defer { fixture.remove() }
    let store = fixture.store()
    var config = store.state.bark; config.title = "新标题"
    #expect(store.saveBarkSettings(config, newKey: "new-device-key"))
    #expect(fixture.keys.key == "new-device-key")
    #expect(!String(decoding: try Data(contentsOf: store.dataURL), as: UTF8.self).contains("new-device-key"))
    try FileManager.default.removeItem(at: store.dataURL)
    try FileManager.default.createDirectory(at: store.dataURL, withIntermediateDirectories: false)
    #expect(!store.saveBarkSettings(config, newKey: "not-committed-key"))
    #expect(fixture.keys.key == "new-device-key" && !store.storageHealthy)
}

@MainActor @Test func barkCanBeDisabledAndKeyRemovalPreservesPortfolioAndRules() async throws {
    let fixture = try BarkFixture(); defer { fixture.remove() }
    let store = fixture.store()
    let items = store.state.items
    store.removeBarkKey()
    #expect(!store.state.bark.enabled && fixture.keys.key == nil)
    #expect(store.state.items == items)
    await store.refresh()
    #expect(fixture.sender.messages.isEmpty && store.state.delivered.isEmpty)
    #expect(!((await store.saveRule(id: "sh600519", upEnabled: true, downEnabled: false, up: "3", down: "2", delivery: .bark))))
}

@MainActor @Test func barkTestUsesExampleDataAndDoesNotCreateAlertReceipts() async throws {
    let fixture = try BarkFixture(); defer { fixture.remove() }
    let store = fixture.store()
    await store.testBark()
    #expect(fixture.sender.messages.count == 1)
    #expect(fixture.sender.messages[0].title.hasPrefix("测试 · "))
    #expect(fixture.sender.messages[0].body.contains("非真实触发"))
    #expect(store.state.delivered.isEmpty)
    let task = Task { await store.testBark() }; task.cancel(); await task.value
    #expect(fixture.sender.messages.count == 1)
}
