import AppKit
import Combine
import Foundation
import UserNotifications
import StockCore

enum PanelRoute: Equatable {
    case home, add, edit(String, Bool), settings, details, inbox
}

/// Display-only policy. Alert eligibility remains governed by MarketClock.isFresh.
enum QuoteDisplayPolicy {
    static func isOld(_ quote: Quote, now: Date) -> Bool {
        guard MarketClock.day(quote.timestamp) == MarketClock.day(now), quote.timestamp <= now else { return true }
        if MarketClock.isTradingTime(now) { return !MarketClock.isFresh(quote, now: now) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = components.weekday, (2...6).contains(weekday),
              let hour = components.hour, let minute = components.minute else { return true }
        let minutes = hour * 60 + minute
        let close: Date?
        if minutes >= 15 * 60 {
            close = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now)
        } else if minutes >= 11 * 60 + 30 && minutes < 13 * 60 {
            close = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: now)
        } else { return true }
        guard let close else { return true }
        // Keep the original timestamp, including provider updates after the close.
        return quote.timestamp < close.addingTimeInterval(-180)
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = SavedState()
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var failedSymbols: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAdding = false
    @Published private(set) var storageHealthy = true
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var now: Date
    @Published var route: PanelRoute = .home {
        didSet { if oldValue != route { navigationRevision &+= 1 } }
    }
    @Published var showHoldings = false
    @Published var revealed = false
    @Published var panelHeightLimit: CGFloat = 420
    @Published var panelContentHeight: CGFloat = 200
    @Published var previewDot = false
    @Published var message: String?
    @Published var error: String?
    let dataURL: URL
    private let file: StateFile
    private let service: any QuoteProviding
    private let notifications: any NotificationSending
    private let clock: () -> Date
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var processingAlerts = false
    private var navigationRevision = 0

    init(dataDirectory: URL? = nil, service: any QuoteProviding = QuoteService(),
         notifications: (any NotificationSending)? = nil, clock: @escaping () -> Date = Date.init) {
        self.service = service
        self.notifications = notifications ?? NotificationService()
        self.clock = clock
        self.now = clock()
        let directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StockBar", isDirectory: true)
        dataURL = directory.appendingPathComponent("state.json")
        file = StateFile(url: dataURL)
        do { state = try file.load() }
        catch { storageHealthy = false; self.error = "本地数据无法读取，已停止保存与提醒以保护持仓。\(error.localizedDescription)" }
    }

    func start() {
        guard timer == nil else { return }
        Task { await updatePermission(); await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
    }

    var holdings: [WatchItem] { state.items.filter { $0.holding.quantity > 0 } }
    var summary: PortfolioSummary { PortfolioSummary(items: state.items, quotes: quotes) }
    var hasOldHoldings: Bool { holdings.contains { isOld($0.id) } }
    var marketLabel: String { MarketClock.isTradingTime(now) ? "交易时段" : "休市" }
    var latestTime: Date? { state.items.compactMap { quotes[$0.id]?.timestamp }.min() }
    var hasUnreadAlerts: Bool { previewDot || !state.unreadAlerts.isEmpty }
    func displayName(_ item: WatchItem) -> String { revealed ? item.name : (state.aliases[item.id] ?? "—") }
    func resetPrivacy() { revealed = false; route = .home; message = nil }
    func closePanel() { resetPrivacy(); NotificationCenter.default.post(name: .closeStockPanel, object: nil) }
    func acknowledgeAlerts() {
        var next = state
        next.unreadAlerts = []
        if commit(next) { previewDot = false }
    }

    func isOld(_ id: String) -> Bool {
        guard let q = quotes[id] else { return true }
        return failedSymbols.contains(id) || QuoteDisplayPolicy.isOld(q, now: now)
    }

    func quoteLabel(_ id: String) -> String {
        guard let quote = quotes[id] else { return "等待行情" }
        let stamp = UI.time(quote.timestamp, full: MarketClock.day(quote.timestamp) != MarketClock.day(now))
        if failedSymbols.contains(id) { return "更新失败 · \(stamp) 旧行情" }
        if isOld(id) { return "历史/延迟行情 · \(stamp)" }
        return "\(MarketClock.isTradingTime(now) ? "行情" : "收盘/休市行情") · \(stamp)"
    }

    var menuTitle: String {
        // Legacy dailyProfit remains decodable, but never exposes holdings in the menu bar.
        guard state.menuMode == .stock else { return "" }
        guard let item = state.items.first(where: { $0.id == state.pinnedSymbol }) ?? state.items.first,
              let q = quotes[item.id] else { return "—" }
        return "\(UI.number(q.percent, signed: true))%\(isOld(item.id) ? " · 旧" : "")"
    }

    func refresh() async {
        guard !isRefreshing else { return }
        now = clock()
        let requested = state.items.map(\.symbol)
        guard !requested.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false; now = clock() }
        do {
            let result = try await service.fetch(requested)
            now = clock()
            let current = Set(state.items.map(\.id))
            let ids = Set(requested.map(\.rawValue)).intersection(current)
            var accepted: [String: Quote] = [:]
            for id in ids {
                if let quote = result[id], quotes[id].map({ quote.timestamp >= $0.timestamp }) ?? true {
                    quotes[id] = quote
                    failedSymbols.remove(id)
                    accepted[id] = quote
                } else { failedSymbols.insert(id) }
            }
            if !ids.isEmpty && accepted.isEmpty { error = "未取得有效新行情，请检查网络或证券代码；旧行情不会触发提醒。" }
            else if !failedSymbols.isEmpty { error = "部分股票更新失败，已标记旧行情。" }
            else if storageHealthy { error = nil }
            await processAlerts(accepted)
        } catch {
            failedSymbols.formUnion(requested.map(\.rawValue))
            self.error = "行情更新失败：\(error.localizedDescription)"
        }
    }

    func add(_ input: String) async -> Bool {
        guard !isAdding, storageHealthy else { return false }
        isAdding = true
        let revision = navigationRevision
        defer { isAdding = false }
        do {
            try Task.checkCancellation()
            let symbol = try StockSymbol(input)
            guard !state.items.contains(where: { $0.symbol == symbol }) else {
                error = "这只股票已在自选列表中。"; return false
            }
            let result = try await service.fetch([symbol])
            try Task.checkCancellation()
            guard revision == navigationRevision else { return false }
            guard let quote = result[symbol.rawValue] else { throw QuoteServiceError.empty }
            var next = state
            next.items.append(WatchItem(symbol: symbol, name: quote.name))
            if next.pinnedSymbol == nil { next.pinnedSymbol = symbol.rawValue }
            guard commit(next) else { return false }
            quotes[symbol.rawValue] = quote
            failedSymbols.remove(symbol.rawValue)
            now = clock()
            message = "已添加 \(state.aliases[symbol.rawValue] ?? "自选项")"
            return true
        } catch is CancellationError { return false }
        catch { if !Task.isCancelled, revision == navigationRevision { self.error = error.localizedDescription }; return false }
    }

    func saveHolding(id: String, quantity: String, cost: String, pin: Bool, alias: String? = nil) -> Bool {
        guard let i = state.items.firstIndex(where: { $0.id == id }) else { return false }
        guard quantity.range(of: #"^\d+$"#, options: .regularExpression) != nil,
              let shares = Int(quantity), shares <= 100_000_000,
              let average = UI.decimal(cost), average <= 10_000_000 else {
            error = "股数需为 0–1 亿的整数，成本需为 0–1000 万元，最多 4 位小数。"; return false
        }
        var next = state
        if let alias {
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 8,
                  !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
                  !state.aliases.contains(where: { $0.key != id && $0.value == value }) else {
                error = "代号需为 1–8 个非空白字符，且不能重复。"; return false
            }
            next.aliases[id] = value
        }
        next.items[i].holding = Holding(quantity: shares, averageCost: average)
        if pin { next.pinnedSymbol = id }
        else if next.pinnedSymbol == id { next.pinnedSymbol = next.items.first(where: { $0.id != id })?.id ?? id }
        guard commit(next) else { return false }
        message = "持仓已保存"; return true
    }

    func saveRule(id: String, upEnabled: Bool, downEnabled: Bool, up: String, down: String, delivery: AlertDelivery? = nil) async -> Bool {
        guard !Task.isCancelled, state.items.contains(where: { $0.id == id }) else { return false }
        let revision = navigationRevision
        guard let upValue = UI.decimal(up), let downValue = UI.decimal(down),
              upValue > 0, downValue > 0, upValue <= 999, downValue <= 999 else {
            error = "提醒阈值需大于 0 且不超过 999%。"; return false
        }
        let channel = delivery ?? state.items.first(where: { $0.id == id })!.rule.delivery
        if channel == .system && (upEnabled || downEnabled) {
            await updatePermission()
            guard !Task.isCancelled, revision == navigationRevision else { return false }
            if notificationStatus == .notDetermined {
                do { _ = try await notifications.requestPermission() }
                catch { if !Task.isCancelled, revision == navigationRevision { self.error = "无法申请通知权限：\(error.localizedDescription)" }; return false }
                guard !Task.isCancelled, revision == navigationRevision else { return false }
                await updatePermission()
            }
        }
        guard !Task.isCancelled, revision == navigationRevision, let i = state.items.firstIndex(where: { $0.id == id }) else { return false }
        var next = state
        next.items[i].rule.upEnabled = upEnabled
        next.items[i].rule.downEnabled = downEnabled
        next.items[i].rule.upThreshold = upValue
        next.items[i].rule.downThreshold = downValue
        next.items[i].rule.delivery = channel
        guard commit(next) else { return false }
        message = channel == .system && notificationStatus == .denied && (upEnabled || downEnabled)
            ? "规则已保存；需在系统设置允许通知后才能收到提醒。" : "提醒已保存，下一次有效行情开始判断。"
        return true
    }

    func remove(_ id: String) {
        var next = state
        next.items.removeAll { $0.id == id }
        next.aliases.removeValue(forKey: id)
        next.unreadAlerts.removeAll { $0.symbol.rawValue == id }
        if next.pinnedSymbol == id { next.pinnedSymbol = next.items.first?.id }
        // Keep today's receipt keys so removing/re-adding a stock cannot bypass deduplication.
        guard commit(next) else { return }
        quotes.removeValue(forKey: id); failedSymbols.remove(id)
        route = .home; message = "已移出自选"
    }

    func saveSettings(mode: MenuMode? = nil, compact: Bool? = nil) {
        var next = state
        if let mode { next.menuMode = mode }
        if let compact { next.compactRows = compact }
        _ = commit(next)
    }

    @discardableResult private func commit(_ next: SavedState) -> Bool {
        guard storageHealthy else { error = "本地存储异常，请先检查数据文件；现有数据不会被覆盖。"; return false }
        var normalized = next
        normalized.assignMissingAliases()
        do { try file.save(normalized); state = normalized; error = nil; return true }
        catch { storageHealthy = false; self.error = "保存失败，提醒已停用以避免重复：\(error.localizedDescription)"; return false }
    }

    private func processAlerts(_ freshQuotes: [String: Quote]) async {
        guard storageHealthy, !processingAlerts else { return }
        processingAlerts = true
        defer { processingAlerts = false }
        let candidates = AlertEvaluator.candidates(items: state.items, quotes: freshQuotes, delivered: state.delivered, now: clock())
        for candidate in candidates {
            guard storageHealthy else { break }
            guard let delivery = state.items.first(where: { $0.id == candidate.symbol.rawValue })?.rule.delivery else { continue }
            if delivery == .system {
                await updatePermission()
                guard notificationStatus == .authorized || notificationStatus == .provisional else { continue }
            }
            // Settings may change while macOS handles an asynchronous notification request.
            guard AlertEvaluator.candidates(items: state.items, quotes: freshQuotes, delivered: state.delivered, now: clock())
                .contains(where: { $0.key == candidate.key && $0.day == candidate.day }),
                state.items.first(where: { $0.id == candidate.symbol.rawValue })?.rule.delivery == delivery else { continue }
            do {
                if delivery == .system {
                    let alias = state.aliases[candidate.symbol.rawValue] ?? "自选项"
                    try await notifications.send(identifier: "\(candidate.day)|\(candidate.key)", title: "提醒", body: "\(alias) 已达到设置条件，打开速览查看。")
                }
                var next = state
                next.delivered = next.delivered.filter { $0.value == candidate.day }
                next.delivered[candidate.key] = candidate.day
                next.unreadAlerts = next.unreadAlerts.filter { $0.day == candidate.day }
                if delivery == .silent, let q = freshQuotes[candidate.symbol.rawValue] {
                    next.unreadAlerts.append(PendingAlert(key: candidate.key, day: candidate.day, symbol: candidate.symbol, percent: q.percent))
                }
                guard commit(next) else { break }
            } catch { self.error = "提醒发送失败：\(error.localizedDescription)" }
        }
    }

    func updatePermission() async { notificationStatus = await notifications.status() }

    func testNotification() async {
        let revision = navigationRevision
        guard !Task.isCancelled else { return }
        do {
            await updatePermission()
            guard !Task.isCancelled, revision == navigationRevision else { return }
            if notificationStatus == .notDetermined {
                _ = try await notifications.requestPermission()
                guard !Task.isCancelled, revision == navigationRevision else { return }
                await updatePermission()
            }
            guard !Task.isCancelled, revision == navigationRevision else { return }
            guard notificationStatus == .authorized || notificationStatus == .provisional else {
                error = "通知权限未开启。请在系统设置 → 通知 → 自选股中允许通知。"; return
            }
            try await notifications.send(identifier: "manual-test", title: "测试提醒", body: "这是手动测试，不代表达到提醒条件。")
            guard !Task.isCancelled, revision == navigationRevision else { return }
            message = "测试通知已提交；横幅显示受系统通知和专注模式设置影响。"
        } catch { if !Task.isCancelled, revision == navigationRevision { self.error = "测试通知失败：\(error.localizedDescription)" } }
    }

    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([dataURL]) }
    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
}
