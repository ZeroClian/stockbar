import Foundation
import Testing
import UserNotifications
import StockCore
@testable import StockBar

private let tradingNow = ISO8601DateFormatter().date(from: "2026-10-23T02:00:00Z")!
private let receipt = ["sh600519|up|3": "2026-10-23"]
private enum BoundaryFailure: Error { case unavailable }

@MainActor @Test func etfCanBeAddedPinnedHeldAndMonitoredAfterClosingPanel() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tickfin-etf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let q = Quote(symbol: try StockSymbol("159915"), name: "创业板ETF", last: Decimal(string: "2.651")!,
                  previousClose: Decimal(string: "2.702")!, percent: Decimal(string: "-1.89")!, timestamp: tradingNow)
    let store = AppStore(dataDirectory: directory, service: QuotesStub(.success(["sz159915": q])),
                         notifications: NotificationsStub(), clock: { tradingNow })
    #expect(await store.add("159915"))
    #expect(store.saveHolding(id: "sz159915", quantity: "1000", cost: "2.5", pin: true))
    #expect(await store.saveRule(id: "sz159915", upEnabled: false, downEnabled: true, up: "3", down: "1", delivery: .silent))
    store.closePanel()
    await store.refresh()
    #expect(store.summary.daily == -51)
    #expect(store.summary.floating == 151)
    #expect(store.state.pinnedSymbol == "sz159915")
    #expect(store.state.unreadAlerts.count == 1)
    await store.refresh()
    #expect(store.state.unreadAlerts.count == 1)
    let persisted = try StateFile(url: store.dataURL).load()
    #expect(persisted.items.first?.holding.quantity == 1000)
    #expect(persisted.delivered["sz159915|down|1"] == "2026-10-23")
    let restored = AppStore(dataDirectory: directory, service: QuotesStub(.success([:])),
                            notifications: NotificationsStub(), clock: { tradingNow })
    #expect(restored.state == persisted)
    #expect(restored.quotes["sz159915"]?.last == Decimal(string: "2.651"))
}

private actor QuotesStub: QuoteProviding {
    var result: Result<[String: Quote], BoundaryFailure>
    init(_ result: Result<[String: Quote], BoundaryFailure>) { self.result = result }
    func set(_ result: Result<[String: Quote], BoundaryFailure>) { self.result = result }
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] { try result.get() }
}

@MainActor @Test(arguments: [AlertDelivery.silent, .system])
func priceAndProfitRulesSaveMonitorClosedAndDeduplicateAfterReload(delivery: AlertDelivery) async throws {
    let fixture = try Fixture(alerts: false); defer { fixture.remove() }
    let notifications = NotificationsStub()
    notifications.permission = .notDetermined
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    var price = PriceAlertRule(); price.aboveEnabled = true; price.above = 103
    var holding = HoldingAlertRule(); holding.profitEnabled = true; holding.profit = 400
    #expect(await store.saveRule(id: "sh600519", upEnabled: false, downEnabled: false, up: "3", down: "2", delivery: delivery, price: price, holding: holding))
    #expect(notifications.permissionRequests == (delivery == .system ? 1 : 0))
    store.closePanel()
    await store.refresh()
    let keys: Set<String> = ["sh600519|priceAbove|103", "sh600519|profitAmount|400"]
    #expect(Set(store.state.delivered.keys) == keys)
    if delivery == .silent {
        #expect(store.state.unreadAlerts.map(\.value) == [103, 400])
        #expect(store.state.unreadAlerts.map(\.kind) == [.priceAbove, .profitAmount])
    } else { #expect(notifications.submitted.count == 2) }
    let persisted = try fixture.file.load()
    #expect(persisted.items[0].rule.price == price && persisted.items[0].rule.holding == holding)
    let restored = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    await restored.refresh()
    #expect(restored.state.delivered == persisted.delivered)
    #expect(delivery == .silent ? restored.state.unreadAlerts.count == 2 : notifications.submitted.count == 2)
}

@MainActor @Test func clearedPositionStopsProfitRuleAndInvalidRulesPreserveData() async throws {
    let fixture = try Fixture(alerts: false, delivery: .silent); defer { fixture.remove() }
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), NotificationsStub())
    var price = PriceAlertRule(); price.aboveEnabled = true; price.above = 103
    var holding = HoldingAlertRule(); holding.profitEnabled = true; holding.profit = 400
    #expect(await store.saveRule(id: "sh600519", upEnabled: false, downEnabled: false, up: "3", down: "2", price: price, holding: holding))
    let before = store.state
    var invalid = holding; invalid.profit = .nan
    #expect(!((await store.saveRule(id: "sh600519", upEnabled: false, downEnabled: false, up: "3", down: "2", holding: invalid))))
    #expect(store.state == before && store.storageHealthy)
    #expect(store.clearHolding("sh600519"))
    store.closePanel(); await store.refresh()
    #expect(store.state.unreadAlerts.map(\.kind) == [.priceAbove])
    #expect(store.state.items[0].rule.holding.profitEnabled)
}

@MainActor private final class NotificationsStub: NotificationSending {
    var permission: UNAuthorizationStatus = .authorized
    var shouldFail = false
    var submitted: [String] = []
    var permissionRequests = 0
    func status() async -> UNAuthorizationStatus { permission }
    func requestPermission() async throws -> Bool { permissionRequests += 1; permission = .authorized; return true }
    func send(identifier: String, title: String, body: String) async throws {
        if shouldFail { throw BoundaryFailure.unavailable }
        submitted.append(identifier)
    }
}

// Real state files and real AppStore logic; only remote quotes, OS notifications,
// and wall-clock time are substituted at their external boundaries.
private struct Fixture {
    let directory: URL
    let file: StateFile
    let initial: SavedState
    init(alerts: Bool = true, twoHoldings: Bool = false, delivery: AlertDelivery = .system) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("stockbar-tests-\(UUID().uuidString)", isDirectory: true)
        file = StateFile(url: directory.appendingPathComponent("state.json"))
        var items = [WatchItem(symbol: try StockSymbol("600519"), name: "贵州茅台",
            holding: Holding(quantity: 100, averageCost: 99), rule: AlertRule(upEnabled: alerts, delivery: delivery))]
        if twoHoldings { items.append(WatchItem(symbol: try StockSymbol("000001"), name: "平安银行", holding: Holding(quantity: 50, averageCost: 10))) }
        initial = SavedState(items: items, pinnedSymbol: "sh600519", menuMode: .stock)
        try file.save(initial)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func quotes(at timestamp: Date = tradingNow) throws -> [String: Quote] {
        ["sh600519": Quote(symbol: try StockSymbol("600519"), name: "贵州茅台", last: 103,
            previousClose: 100, percent: 3, timestamp: timestamp)]
    }
    @MainActor func store(_ service: any QuoteProviding, _ notifications: NotificationsStub, now: Date = tradingNow) -> AppStore {
        AppStore(dataDirectory: directory, service: service, notifications: notifications, clock: { now })
    }
}

@MainActor @Test func defaultAlertDoesNotSubmitSystemNotification() async throws {
    let fixture = try Fixture(delivery: .silent); defer { fixture.remove() }
    let notifications = NotificationsStub()
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    await store.refresh()
    #expect(notifications.submitted.isEmpty)
    #expect(try fixture.file.load().delivered == receipt)
    #expect(store.state.unreadAlerts.count == 1)
    #expect(store.hasUnreadAlerts)
    #expect(notifications.permissionRequests == 0)
}

@MainActor @Test func defaultAlertWorksWithoutSystemPermission() async throws {
    let fixture = try Fixture(delivery: .silent); defer { fixture.remove() }
    let notifications = NotificationsStub(); notifications.permission = .denied
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    await store.refresh()
    #expect(notifications.submitted.isEmpty)
    #expect(try fixture.file.load().delivered == receipt)
    #expect(try fixture.file.load().unreadAlerts.count == 1)
    #expect(notifications.permissionRequests == 0)
}

@MainActor @Test func refreshPersistsSuccessfulAlertAndDeduplicatesNextRequest() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let notifications = NotificationsStub()
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    #expect(store.state == fixture.initial)
    await store.refresh()
    #expect(store.now == tradingNow)
    #expect(store.quotes["sh600519"]?.last == 103)
    #expect(store.summary.daily == 300 && store.summary.floating == 400)
    #expect(store.state.delivered == receipt)
    #expect(try fixture.file.load().delivered == receipt)
    await store.refresh()
    #expect(store.state.delivered == receipt)
    #expect(notifications.submitted == ["2026-10-23|sh600519|up|3"])
}

@MainActor @Test func rebuiltStoreUsesPersistedReceiptRatherThanAlertingAgain() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let service = QuotesStub(.success(try fixture.quotes()))
    let first = fixture.store(service, NotificationsStub())
    await first.refresh()
    #expect(try fixture.file.load().delivered == receipt)
    let notifications = NotificationsStub()
    let rebuilt = fixture.store(service, notifications)
    await rebuilt.refresh()
    #expect(rebuilt.state.delivered == receipt)
    #expect(try fixture.file.load() == rebuilt.state)
    #expect(notifications.submitted.isEmpty)
}

@MainActor @Test func notificationFailureDoesNotPersistReceiptAndNextRefreshRetries() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let notifications = NotificationsStub(); notifications.shouldFail = true
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    await store.refresh()
    #expect(store.state.delivered.isEmpty)
    #expect(try fixture.file.load().delivered.isEmpty)
    #expect(store.error != nil)
    notifications.shouldFail = false
    await store.refresh()
    #expect(try fixture.file.load().delivered == receipt)
}

@MainActor @Test func failedRequestRetainsQuoteButCannotUseItForNewlyEnabledRule() async throws {
    let fixture = try Fixture(alerts: false); defer { fixture.remove() }
    let service = QuotesStub(.success(try fixture.quotes()))
    let notifications = NotificationsStub()
    let store = fixture.store(service, notifications)
    await store.refresh()
    #expect(await store.saveRule(id: "sh600519", upEnabled: true, downEnabled: false, up: "3", down: "2"))
    await service.set(.failure(.unavailable))
    await store.refresh()
    #expect(store.quotes["sh600519"]?.last == 103)
    #expect(store.failedSymbols == ["sh600519"])
    #expect(store.isOld("sh600519"))
    #expect(try fixture.file.load().items[0].rule.upEnabled)
    #expect(try fixture.file.load().delivered.isEmpty)
    #expect(notifications.submitted.isEmpty)
}

@MainActor @Test(arguments: [
    ("2026-10-23T02:00:00Z", "2026-10-23T01:56:59Z"),
    ("2026-10-23T02:00:00Z", "2026-10-22T02:00:00Z"),
    ("2026-10-23T02:00:00Z", "2026-10-23T02:00:01Z"),
    ("2026-10-23T04:00:00Z", "2026-10-23T04:00:00Z")
]) func staleFutureAndLunchQuotesCannotProduceReceipts(times: (String, String)) async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let now = ISO8601DateFormatter().date(from: times.0)!
    let timestamp = ISO8601DateFormatter().date(from: times.1)!
    let notifications = NotificationsStub()
    if !TradingSchedule.isOpen(now) {
        try JSONEncoder().encode(fixture.quotes(at: timestamp)).write(to: fixture.directory.appendingPathComponent("quotes-cache.json"))
    }
    let store = fixture.store(QuotesStub(.success(try fixture.quotes(at: timestamp))), notifications, now: now)
    await store.refresh()
    #expect(store.quotes["sh600519"]?.timestamp == timestamp)
    #expect(store.state.delivered.isEmpty)
    #expect(try fixture.file.load().delivered.isEmpty)
    #expect(notifications.submitted.isEmpty)
}

@MainActor @Test func missingHeldQuoteLeavesPortfolioSummaryIncomplete() async throws {
    let fixture = try Fixture(alerts: false, twoHoldings: true); defer { fixture.remove() }
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), NotificationsStub())
    await store.refresh()
    #expect(store.holdings.count == 2)
    #expect(store.summary.daily == nil && store.summary.floating == nil)
    #expect(store.summary.missingSymbols == ["sz000001"])
    #expect(store.failedSymbols == ["sz000001"])
    #expect(store.menuTitle == "+3.00%")
    #expect(try fixture.file.load() == fixture.initial)
}

@MainActor @Test(arguments: [
    ("-1", "99"), ("1.5", "99"), ("100000001", "99"), ("100", "-1"),
    ("100", "NaN"), ("100", "Infinity"), ("100", "1.00001"), ("100", "10000001")
]) func invalidHoldingInputDoesNotAlterMemoryOrDisk(input: (String, String)) throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let original = try Data(contentsOf: fixture.file.url)
    let store = fixture.store(QuotesStub(.success([:])), NotificationsStub())
    #expect(!store.saveHolding(id: "sh600519", quantity: input.0, cost: input.1, pin: true))
    #expect(store.state == fixture.initial)
    #expect(try Data(contentsOf: fixture.file.url) == original)
    #expect(store.storageHealthy)
    #expect(store.error != nil)
}

@MainActor @Test func failedSavePreservesLoadedHoldingsAndDamagedFileAndStopsAlerts() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let notifications = NotificationsStub()
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    let damaged = Data("{damaged-for-recovery".utf8)
    try damaged.write(to: fixture.file.url)
    #expect(!store.saveHolding(id: "sh600519", quantity: "200", cost: "101", pin: true))
    #expect(store.state == fixture.initial)
    #expect(!store.storageHealthy)
    #expect(try Data(contentsOf: fixture.file.url) == damaged)
    await store.refresh()
    #expect(store.quotes["sh600519"]?.last == 103)
    #expect(store.state == fixture.initial)
    #expect(try Data(contentsOf: fixture.file.url) == damaged)
    #expect(notifications.submitted.isEmpty)
}

private actor PausedQuoteProvider: QuoteProviding {
    let response: [String: Quote]
    var pending: CheckedContinuation<[String: Quote], Never>?
    var started: CheckedContinuation<Void, Never>?
    var requested = false
    init(response: [String: Quote]) { self.response = response }
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] {
        if requested { return response }
        requested = true
        return await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if requested { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { pending?.resume(returning: response); pending = nil }
}

@MainActor @Test func reentrantRefreshCannotPublishOrFinishWhileFirstRequestIsPending() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let service = PausedQuoteProvider(response: try fixture.quotes())
    let store = fixture.store(service, NotificationsStub())
    let first = Task { await store.refresh() }
    await service.waitUntilStarted()
    await store.refresh()
    #expect(store.isRefreshing)
    #expect(store.quotes.isEmpty)
    #expect(store.state.delivered.isEmpty)
    #expect(try fixture.file.load() == fixture.initial)
    await service.resume()
    await first.value
    #expect(!store.isRefreshing)
    #expect(store.quotes["sh600519"]?.last == 103)
    #expect(try fixture.file.load().delivered == receipt)
}

@MainActor @Test(arguments: [
    ("2026-10-23T08:00:00Z", "2026-10-23T02:00:00Z", true),
    ("2026-10-23T04:00:00Z", "2026-10-23T02:00:00Z", true),
    ("2026-10-23T08:00:00Z", "2026-10-23T06:59:00Z", false),
    ("2026-10-23T04:00:00Z", "2026-10-23T03:29:00Z", false),
    ("2026-10-23T04:00:00Z", "2026-10-23T03:27:00Z", false),
    ("2026-10-23T04:00:00Z", "2026-10-23T03:26:59Z", true),
    ("2026-10-23T08:00:00Z", "2026-10-23T06:57:00Z", false),
    ("2026-10-23T08:00:00Z", "2026-10-23T06:56:59Z", true),
    ("2026-10-23T10:00:00Z", "2026-10-23T08:15:00Z", false),
    ("2026-10-23T10:00:00Z", "2026-10-23T07:36:00Z", false),
    ("2026-10-23T01:00:00Z", "2026-10-23T01:00:00Z", true),
    ("2026-10-23T08:00:00Z", "2026-10-22T06:59:00Z", true),
    ("2026-10-23T08:00:00Z", "2026-10-23T08:00:01Z", true),
    ("2026-10-24T08:00:00Z", "2026-10-24T06:59:00Z", true)
]) func closedSessionKeepsDelayedQuotesOldAndAcceptsRecentSessionClose(input: (String, String, Bool)) async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let now = ISO8601DateFormatter().date(from: input.0)!
    let timestamp = ISO8601DateFormatter().date(from: input.1)!
    let notifications = NotificationsStub()
    // Rest-time startup displays local cache without requesting quotes.
    try JSONEncoder().encode(fixture.quotes(at: timestamp)).write(to: fixture.directory.appendingPathComponent("quotes-cache.json"))
    let store = fixture.store(QuotesStub(.success(try fixture.quotes(at: timestamp))), notifications, now: now)
    await store.refresh()
    #expect(store.quotes["sh600519"]?.timestamp == timestamp)
    #expect(store.isOld("sh600519") == input.2)
    #expect(store.hasOldHoldings == input.2)
    #expect(store.menuTitle.hasSuffix(" · 旧") == input.2)
    #expect(store.quoteLabel("sh600519").hasPrefix(input.2 ? "历史/延迟行情" : "收盘/休市行情"))
    #expect(try fixture.file.load().delivered.isEmpty)
    #expect(notifications.submitted.isEmpty)
}

@MainActor @Test func cancelledAddCannotPersistLateQuoteOrAffectLaterEditor() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let bank = Quote(symbol: try StockSymbol("000001"), name: "平安银行", last: 103, previousClose: 100, percent: 3, timestamp: tradingNow)
    let provider = PausedQuoteProvider(response: ["sz000001": bank])
    let store = fixture.store(provider, NotificationsStub())
    store.route = .add
    let pending = Task { await store.add("000001") }
    await provider.waitUntilStarted()
    pending.cancel()
    store.route = .edit("sh600519", false)
    await provider.resume()
    #expect(!(await pending.value))
    #expect(store.state == fixture.initial)
    #expect(try fixture.file.load() == fixture.initial)
    #expect(store.quotes["sz000001"] == nil)
    #expect(store.route == .edit("sh600519", false))
    #expect(store.message == nil && store.error == nil)
    #expect(!store.isAdding)
}

@MainActor @Test func uncancelledAddPersistsQuoteAndInitialWatchSettings() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let bank = Quote(symbol: try StockSymbol("000001"), name: "平安银行", last: 103, previousClose: 100, percent: 3, timestamp: tradingNow)
    let store = fixture.store(QuotesStub(.success(["sz000001": bank])), NotificationsStub())
    #expect(await store.add("000001"))
    let saved = try fixture.file.load()
    #expect(saved == store.state)
    #expect(saved.items.map(\.id) == ["sh600519", "sz000001"])
    #expect(saved.items[1].holding == Holding())
    #expect(!saved.items[1].rule.upEnabled && !saved.items[1].rule.downEnabled)
    #expect(saved.pinnedSymbol == "sh600519")
    #expect(store.quotes["sz000001"] == bank)
    #expect(!store.isAdding)
}

@MainActor private final class PausedNotifications: NotificationSending {
    var submitted: [String] = []
    var pending: CheckedContinuation<UNAuthorizationStatus, Never>?
    var started: CheckedContinuation<Void, Never>?
    func status() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { pending?.resume(returning: .authorized); pending = nil }
    func requestPermission() async throws -> Bool { true }
    func send(identifier: String, title: String, body: String) async throws { submitted.append(identifier) }
}

@MainActor @Test func closedTestNotificationCannotSendAfterPermissionReturns() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let notifications = PausedNotifications()
    let store = AppStore(dataDirectory: fixture.directory, service: QuotesStub(.success([:])), notifications: notifications, clock: { tradingNow })
    store.route = .settings
    let request = Task { await store.testNotification() }
    await notifications.waitUntilStarted()
    store.resetPrivacy()
    store.route = .settings
    notifications.resume()
    await request.value
    #expect(notifications.submitted.isEmpty)
    #expect(store.message == nil && store.error == nil)
}

@MainActor @Test func cancelledRuleSaveCannotCommitAfterPermissionReturns() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let notifications = PausedNotifications()
    let store = AppStore(dataDirectory: fixture.directory, service: QuotesStub(.success([:])), notifications: notifications, clock: { tradingNow })
    store.route = .edit("sh600519", true)
    let pending = Task { await store.saveRule(id: "sh600519", upEnabled: true, downEnabled: false, up: "5", down: "2") }
    await notifications.waitUntilStarted()
    pending.cancel()
    store.route = .settings
    notifications.resume()
    #expect(!(await pending.value))
    #expect(store.state == fixture.initial)
    #expect(try fixture.file.load() == fixture.initial)
    #expect(store.route == .settings)
    #expect(store.message == nil && store.error == nil)
}

@MainActor @Test func acknowledgingSilentAlertSurvivesRestartWithoutRepeating() async throws {
    let fixture = try Fixture(delivery: .silent); defer { fixture.remove() }
    let service = QuotesStub(.success(try fixture.quotes()))
    let store = fixture.store(service, NotificationsStub())
    await store.refresh()
    #expect(store.hasUnreadAlerts)
    let rebuilt = fixture.store(service, NotificationsStub())
    #expect(rebuilt.hasUnreadAlerts)
    #expect(rebuilt.state.unreadAlerts.first?.percent == 3)
    rebuilt.acknowledgeAlerts()
    #expect(!rebuilt.hasUnreadAlerts)
    #expect(try fixture.file.load().delivered == receipt)
    let third = fixture.store(service, NotificationsStub())
    await third.refresh()
    #expect(!third.hasUnreadAlerts)
    #expect(third.state.delivered == receipt)
}

@MainActor @Test func privacyResetDoesNotExposeStockOrHoldingsInMenu() async throws {
    let fixture = try Fixture(alerts: false); defer { fixture.remove() }
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), NotificationsStub())
    await store.refresh()
    let item = store.state.items[0]
    #expect(store.displayName(item) == "GZMT")
    #expect(store.menuTitle == "+3.00%")
    store.revealed = true
    #expect(store.displayName(item) == "贵州茅台")
    store.route = .edit(item.id, false)
    store.message = "saved"
    store.resetPrivacy()
    #expect(!store.revealed && store.route == .home && store.message == nil)
    #expect(store.displayName(item) == "GZMT")
    store.saveSettings(mode: .icon)
    #expect(store.menuTitle.isEmpty)
    store.saveSettings(mode: .dailyProfit)
    #expect(store.menuTitle.isEmpty)
    #expect(store.state.items == fixture.initial.items)
}

@MainActor @Test func closingPanelPreventsLateAddEvenBeforeViewCancellation() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let q = Quote(symbol: try StockSymbol("000001"), name: "平安银行", last: 103, previousClose: 100, percent: 3, timestamp: tradingNow)
    let provider = PausedQuoteProvider(response: ["sz000001": q])
    let store = fixture.store(provider, NotificationsStub())
    store.route = .add
    let request = Task { await store.add("000001") }
    await provider.waitUntilStarted()
    store.resetPrivacy()
    store.route = .add // Leaving and returning cannot revive the earlier request.
    await provider.resume()
    #expect(!(await request.value))
    #expect(try fixture.file.load() == fixture.initial)
    #expect(store.message == nil)
}

@MainActor @Test func silentRuleSaveNeverRequestsAuthorization() async throws {
    let fixture = try Fixture(alerts: false); defer { fixture.remove() }
    let notifications = NotificationsStub(); notifications.permission = .notDetermined
    let store = fixture.store(QuotesStub(.success([:])), notifications)
    #expect(await store.saveRule(id: "sh600519", upEnabled: true, downEnabled: false, up: "5", down: "2", delivery: .silent))
    #expect(notifications.permissionRequests == 0)
    #expect(try fixture.file.load().items[0].rule.delivery == .silent)
}

@MainActor @Test func silentReceiptAndUnreadFailTogetherOnDamagedStorage() async throws {
    let fixture = try Fixture(delivery: .silent); defer { fixture.remove() }
    let notifications = NotificationsStub()
    let store = fixture.store(QuotesStub(.success(try fixture.quotes())), notifications)
    let damaged = Data("{broken".utf8)
    try damaged.write(to: fixture.file.url)
    await store.refresh()
    #expect(!store.storageHealthy)
    #expect(store.state.delivered.isEmpty && store.state.unreadAlerts.isEmpty)
    #expect(!store.hasUnreadAlerts && notifications.submitted.isEmpty)
    #expect(try Data(contentsOf: fixture.file.url) == damaged)
}

@MainActor @Test func nextDaySystemReceiptPrunesOldSilentUnreadAtomically() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    var initial = fixture.initial
    initial.items.append(WatchItem(symbol: try StockSymbol("000001"), name: "平安银行",
        rule: AlertRule(upEnabled: true, delivery: .system)))
    initial.delivered = ["sh600519|up|3": "2026-10-22"]
    initial.unreadAlerts = [PendingAlert(key: "sh600519|up|3", day: "2026-10-22",
        symbol: try StockSymbol("600519"), percent: 3)]
    initial.assignMissingAliases()
    try fixture.file.save(initial)
    let bank = Quote(symbol: try StockSymbol("000001"), name: "平安银行", last: 103,
        previousClose: 100, percent: 3, timestamp: tradingNow)
    let notifications = NotificationsStub()
    let store = fixture.store(QuotesStub(.success(["sz000001": bank])), notifications)
    await store.refresh()
    #expect(store.storageHealthy)
    #expect(store.state.unreadAlerts.isEmpty)
    #expect(try fixture.file.load().delivered == ["sz000001|up|3": "2026-10-23"])
    #expect(notifications.submitted.count == 1)
}

@MainActor @Test func invalidAliasDoesNotDisableStorageOrChangeHoldings() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let store = fixture.store(QuotesStub(.success([:])), NotificationsStub())
    #expect(!store.saveHolding(id: "sh600519", quantity: "1", cost: "99", pin: true, alias: "\u{0000}"))
    #expect(store.storageHealthy)
    #expect(try fixture.file.load() == fixture.initial)
}

@MainActor @Test func clearSingleHoldingPreservesEverythingElseAndPersists() throws {
    let fixture = try Fixture(twoHoldings: true); defer { fixture.remove() }
    var initial = fixture.initial
    initial.delivered = receipt
    initial.unreadAlerts = [PendingAlert(key: "sh600519|up|3", day: "2026-10-23", symbol: try StockSymbol("600519"), percent: 3)]
    try fixture.file.save(initial)
    let store = fixture.store(QuotesStub(.success([:])), NotificationsStub())
    var expected = initial
    expected.items[0].holding = Holding()
    #expect(store.clearHolding("sh600519"))
    #expect(store.state == expected)
    #expect(try fixture.file.load() == expected)
    #expect(store.clearHolding("sh600519"))
    #expect(store.state == expected)
    #expect(!store.clearHolding("sz300750"))
    #expect(try fixture.file.load() == expected)
}

@MainActor @Test func failedHoldingClearPreservesMemoryAndDamagedFile() throws {
    let fixture = try Fixture(twoHoldings: true); defer { fixture.remove() }
    let store = fixture.store(QuotesStub(.success([:])), NotificationsStub())
    let broken = Data("broken data must remain recoverable".utf8)
    try broken.write(to: store.dataURL)
    #expect(!store.clearHolding("sh600519"))
    #expect(store.state == fixture.initial)
    #expect(try Data(contentsOf: store.dataURL) == broken)
}
