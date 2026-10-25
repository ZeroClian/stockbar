import Foundation
import Testing
import UserNotifications
import StockCore
@testable import StockBar

private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
@MainActor private final class ManualScheduler: RefreshScheduling {
    var delay: TimeInterval?
    var action: (@MainActor () async -> Void)?
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () async -> Void) { self.delay = delay; self.action = action }
    func cancel() { delay = nil; action = nil }
    func fire() async { let callback = action; cancel(); await callback?() }
}
@MainActor private final class TestTime { var now = instant("2026-10-23T02:00:00Z") }
private actor CountingQuotes: QuoteProviding {
    var count = 0
    var timestamp: Date
    init(_ timestamp: Date) { self.timestamp = timestamp }
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] {
        count += 1
        return Dictionary(uniqueKeysWithValues: symbols.map { ($0.rawValue, Quote(symbol: $0, name: "测试", last: 104, previousClose: 100, percent: 4, timestamp: timestamp)) })
    }
    func setTime(_ date: Date) { timestamp = date }
}
@MainActor private final class TestNotifications: NotificationSending {
    var sent = 0
    func status() async -> UNAuthorizationStatus { .authorized }
    func requestPermission() async throws -> Bool { true }
    func send(identifier: String, title: String, body: String) async throws { sent += 1 }
}
private func initialState(delivery: AlertDelivery = .silent) throws -> SavedState {
    let items = try ["300750", "600519", "000001"].map { WatchItem(symbol: try StockSymbol($0), name: $0, holding: Holding(quantity: 100, averageCost: 99), rule: AlertRule(upEnabled: true, delivery: delivery)) }
    return SavedState(items: items, pinnedSymbol: items[0].id)
}
private func tempDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("stockbar-refresh-" + UUID().uuidString) }

@MainActor @Test(arguments: [AlertDelivery.silent, .system]) func panelClosedStillMonitorsAndPersistsAlerts(delivery: AlertDelivery) async throws {
    let directory = tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let file = StateFile(url: directory.appendingPathComponent("state.json")); try file.save(initialState(delivery: delivery))
    let time = TestTime(), scheduler = ManualScheduler(), notifications = TestNotifications()
    let quotes = CountingQuotes(time.now)
    let store = AppStore(dataDirectory: directory, service: quotes, notifications: notifications, scheduler: scheduler, clock: { time.now })
    defer { store.stop() }
    store.start()
    #expect(scheduler.action != nil)
    store.route = .settings; store.revealed = true
    store.closePanel()
    await scheduler.fire()
    #expect(await quotes.count == 1)
    #expect(!store.revealed && store.route == .home)
    #expect(store.state.delivered.count == 3)
    #expect(try file.load().delivered.count == 3)
    #expect(delivery == .silent ? store.hasUnreadAlerts : notifications.sent == 3)
    #expect(scheduler.delay == 15)
    time.now = time.now.addingTimeInterval(15)
    await quotes.setTime(time.now)
    await scheduler.fire()
    #expect(await quotes.count == 2)
    #expect(notifications.sent == (delivery == .system ? 3 : 0))
    #expect(store.state.unreadAlerts.count == (delivery == .silent ? 3 : 0))
}

@MainActor @Test func refreshPausesAtLunchResumesWithoutOpeningPanelAndChangesInterval() async throws {
    let directory = tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    try StateFile(url: directory.appendingPathComponent("state.json")).save(initialState())
    let time = TestTime(), scheduler = ManualScheduler()
    time.now = instant("2026-10-23T03:29:50Z")
    let quotes = CountingQuotes(time.now)
    let store = AppStore(dataDirectory: directory, service: quotes, notifications: TestNotifications(), scheduler: scheduler, clock: { time.now })
    defer { store.stop() }
    store.start(); await scheduler.fire()
    #expect(scheduler.delay == 10)
    time.now = instant("2026-10-23T03:30:00Z")
    await scheduler.fire()
    await store.refresh() // Manual action also respects the closed session.
    #expect(await quotes.count == 1)
    #expect(scheduler.delay == 5400.0)
    time.now = instant("2026-10-23T05:00:00Z")
    await quotes.setTime(time.now); await scheduler.fire()
    #expect(await quotes.count == 2)
    #expect(store.saveRefreshInterval("37"))
    #expect(scheduler.delay == 37)
    #expect(try StateFile(url: store.dataURL).load().refreshIntervalSeconds == 37)
    #expect(!store.saveRefreshInterval("4") && !store.saveRefreshInterval("15.5"))
    #expect(store.state.refreshIntervalSeconds == 37 && store.storageHealthy)
    store.stop(); #expect(scheduler.action == nil)
}

@MainActor @Test func cachedQuotesSurviveClosedMarketRestartWithoutAlertOrNetwork() async throws {
    let directory = tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    try StateFile(url: directory.appendingPathComponent("state.json")).save(initialState())
    let time = TestTime(), quotes = CountingQuotes(instant("2026-10-23T02:00:00Z"))
    let first = AppStore(dataDirectory: directory, service: quotes, notifications: TestNotifications(), clock: { time.now })
    await first.refresh()
    time.now = instant("2026-10-25T02:00:00Z")
    let rebuilt = AppStore(dataDirectory: directory, service: quotes, notifications: TestNotifications(), clock: { time.now })
    await rebuilt.refresh()
    #expect(await quotes.count == 1)
    #expect(rebuilt.quotes.count == 3 && rebuilt.isOld("sz300750"))
    #expect(rebuilt.state.delivered == first.state.delivered)
}

@MainActor @Test func watchlistOrderAndPinPersistWithoutChangingHoldingsOrAliases() throws {
    let directory = tempDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let file = StateFile(url: directory.appendingPathComponent("state.json"))
    let initial = try initialState(); try file.save(initial)
    let store = AppStore(dataDirectory: directory, service: CountingQuotes(instant("2026-10-23T02:00:00Z")), notifications: TestNotifications())
    store.moveItem("sz000001", offset: -1)
    #expect(store.state.items.map(\.id) == ["sz300750", "sz000001", "sh600519"])
    #expect(store.state.aliases == initial.aliases && store.state.pinnedSymbol == "sz300750")
    store.pinStock("sz000001")
    #expect(store.state.pinnedSymbol == "sz000001" && store.state.menuMode == .icon)
    #expect(Set(store.state.items.map(\.id)) == Set(initial.items.map(\.id)))
    for item in initial.items { #expect(store.state.items.first { $0.id == item.id } == item) }
    let beforeInvalid = store.state
    store.moveItem("sz300750", offset: -1); store.pinStock("not-a-symbol")
    #expect(store.state == beforeInvalid)
    #expect(try file.load() == store.state)
    try Data("{broken".utf8).write(to: file.url)
    store.moveItem("sz000001", offset: -1)
    #expect(store.state == beforeInvalid && !store.storageHealthy)
}
