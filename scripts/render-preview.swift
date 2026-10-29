// Development-only render of real SwiftUI views with isolated sample data.
// This is not a screenshot of desktop interactions or a live market check.
import AppKit
import SwiftUI
import UserNotifications
import StockCore

struct PreviewQuotes: QuoteProviding {
    let values: [String: Quote]
    func fetch(_ symbols: [StockSymbol]) async throws -> [String: Quote] { values }
}

@MainActor final class PreviewNotifications: NotificationSending {
    func status() async -> UNAuthorizationStatus { .denied }
    func requestPermission() async throws -> Bool { false }
    func send(identifier: String, title: String, body: String) async throws {}
}

@MainActor final class PreviewShortcutBackend: ShortcutRegistering {
    final class Token: ShortcutRegistration { func cancel() {} }
    func register(_ shortcut: GlobalShortcut, action: @escaping @MainActor () -> Void) throws -> any ShortcutRegistration { Token() }
}

@MainActor final class PreviewBarkKeys: BarkKeyStoring {
    func read() throws -> String? { "preview-key" }
    func write(_ key: String?) throws {}
}

@MainActor final class PreviewBarkSender: BarkSending {
    func send(configuration: BarkConfiguration, key: String, message: BarkMessage) async throws {}
}

@main struct PreviewRenderer {
    @MainActor static func main() async throws {
        // Process-local only: reproduce the user's always-visible scrollbar setting.
        UserDefaults.standard.setVolatileDomain(["AppleShowScrollBars": "Always"], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("StockBar-render-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: data) }
        let stamp = ISO8601DateFormatter().date(from: "2026-10-29T06:30:00Z")!
        let rows: [(String, String, String, String, String, Int, String)] = [
            ("600519", "贵州茅台", "1335", "1318.49", "1.25", 100, "1290"),
            ("000001", "平安银行", "11.20", "11.30", "-0.88", 2000, "11.65"),
            ("159915", "创业板ETF", "2.651", "2.702", "-1.89", 1000, "2.50")
        ]
        var state = SavedState()
        var quotes: [String: Quote] = [:]
        for (code, name, last, previous, percent, quantity, cost) in rows {
            let symbol = try StockSymbol(code)
            state.items.append(WatchItem(symbol: symbol, name: name, holding: Holding(quantity: quantity, averageCost: Decimal(string: cost)!)))
            quotes[symbol.rawValue] = Quote(symbol: symbol, name: name, last: Decimal(string: last)!, previousClose: Decimal(string: previous)!, percent: Decimal(string: percent)!, timestamp: stamp, dayHigh: Decimal(string: last)! * Decimal(string: "1.01")!, dayLow: Decimal(string: last)! * Decimal(string: "0.99")!)
        }
        state.assignMissingAliases()
        state.pinnedSymbol = state.items[0].id
        state.items[0].rule.upEnabled = true
        state.items[2].rule.price.belowEnabled = true
        state.items[2].rule.price.below = Decimal(string: "2.60")!
        state.items[2].rule.delivery = .bark
        state.bark.enabled = true
        state.menuMode = .stockPrice
        state.globalShortcut = GlobalShortcut(keyCode: 4, modifiers: [.command, .shift])
        state.previousStockShortcut = GlobalShortcut(keyCode: 123, modifiers: [.control, .option])
        state.nextStockShortcut = GlobalShortcut(keyCode: 124, modifiers: [.control, .option])
        try StateFile(url: data.appendingPathComponent("state.json")).save(state)
        let store = AppStore(dataDirectory: data, service: PreviewQuotes(values: quotes), notifications: PreviewNotifications(), shortcutBackend: PreviewShortcutBackend(), updateChecker: UpdateChecker(currentVersion: "1.2.2"), barkSender: PreviewBarkSender(), barkKeys: PreviewBarkKeys(), clock: { stamp })
        await store.refresh()


        let testWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 280, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false
        let shared = NSHostingView(rootView: AnyView(PanelView(store: store).environment(\.colorScheme, .light)))
        testWindow.contentView = shared
        func render(_ name: String, store: AppStore, dark: Bool = false, reuse: NSHostingView<AnyView>? = nil) async throws -> NSSize {
            let view = reuse ?? NSHostingView(rootView: AnyView(PanelView(store: store).environment(\.colorScheme, dark ? .dark : .light)))
            if view === shared {
                view.rootView = AnyView(PanelView(store: store).environment(\.colorScheme, dark ? .dark : .light))
            }
            testWindow.contentView = view
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for _ in 0..<8 {
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 15_000_000)
            }
            let size = view.fittingSize
            precondition(abs(size.width - 280) < 1 && (reuse != nil && reuse !== shared || size.height <= store.panelHeightLimit + 1), "Panel exceeds available space")
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("\(name): \(Int(size.width)) × \(Int(size.height)); content \(Int(store.panelContentHeight))")
            return size
        }
        _ = try await render("watchlist", store: store, reuse: shared)
        store.showHoldings = true
        _ = try await render("holdings-hidden", store: store, reuse: shared)
        store.revealed = true
        _ = try await render("holdings-dark", store: store, dark: true, reuse: shared)
        store.route = .edit(state.items[2].id, true)
        _ = try await render("price-alerts", store: store, reuse: shared)
        store.resetPrivacy()
        store.route = .settings
        _ = try await render("menu-settings", store: store, reuse: shared)
        store.refreshBarkStatus()
        let bark = NSHostingView(rootView: AnyView(BarkSettingsView(store: store, expanded: .constant(true))
            .font(.system(size: 11)).controlSize(.small).padding(12).frame(width: 280).background(UI.background)))
        _ = try await render("bark-settings", store: store, reuse: bark)
        print("Documentation previews rendered from real SwiftUI views with isolated sample data; no network pushes.")
    }
}
