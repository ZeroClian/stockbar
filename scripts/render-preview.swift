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
        let stamp = ISO8601DateFormatter().date(from: "2026-10-23T06:30:00Z")!
        let rows: [(String, String, String, String, String, Int, String)] = [
            ("600519", "贵州茅台", "1335", "1318.49", "1.25", 100, "1290"),
            ("000001", "平安银行", "11.20", "11.30", "-0.88", 2000, "11.65"),
            ("600036", "招商银行", "42.18", "41.66", "1.25", 500, "40.70")
        ]
        var state = SavedState()
        var quotes: [String: Quote] = [:]
        for (code, name, last, previous, percent, quantity, cost) in rows {
            let symbol = try StockSymbol(code)
            state.items.append(WatchItem(symbol: symbol, name: name, holding: Holding(quantity: quantity, averageCost: Decimal(string: cost)!)))
            quotes[symbol.rawValue] = Quote(symbol: symbol, name: name, last: Decimal(string: last)!, previousClose: Decimal(string: previous)!, percent: Decimal(string: percent)!, timestamp: stamp)
        }
        state.assignMissingAliases()
        state.pinnedSymbol = state.items[0].id
        state.items[0].rule.upEnabled = true
        try StateFile(url: data.appendingPathComponent("state.json")).save(state)
        let store = AppStore(dataDirectory: data, service: PreviewQuotes(values: quotes), notifications: PreviewNotifications(), shortcutBackend: PreviewShortcutBackend(), updateChecker: UpdateChecker(currentVersion: "1.2.0"), clock: { stamp })
        await store.refresh()
        let empty = AppStore(dataDirectory: data.appendingPathComponent("empty"), service: PreviewQuotes(values: [:]), notifications: PreviewNotifications(), shortcutBackend: PreviewShortcutBackend(), clock: { stamp })

        let testWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 280, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false
        let shared = NSHostingView(rootView: AnyView(PanelView(store: store).environment(\.colorScheme, .light)))
        testWindow.contentView = shared
        func render(_ name: String, store: AppStore, dark: Bool = false, reuse: NSHostingView<AnyView>? = nil) async throws -> NSSize {
            let view = reuse ?? NSHostingView(rootView: AnyView(PanelView(store: store).environment(\.colorScheme, dark ? .dark : .light)))
            if view === shared {
                view.rootView = AnyView(PanelView(store: store).environment(\.colorScheme, dark ? .dark : .light))
            }
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for _ in 0..<8 {
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 15_000_000)
            }
            let size = view.fittingSize
            precondition(abs(size.width - 280) < 1 && size.height <= store.panelHeightLimit + 1, "Panel exceeds available space")
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("\(name): \(Int(size.width)) × \(Int(size.height)); content \(Int(store.panelContentHeight))")
            return size
        }
        _ = try await render("empty", store: empty)
        let homeSize = try await render("watchlist", store: store, reuse: shared)
        store.showHoldings = true
        _ = try await render("holdings-hidden", store: store, reuse: shared)
        store.revealed = true
        _ = try await render("holdings", store: store, reuse: shared)
        _ = try await render("holdings-dark", store: store, dark: true)
        store.resetPrivacy()
        store.route = .edit(state.items[0].id, false)
        _ = try await render("holding-editor", store: store, reuse: shared)
        store.revealed = true
        _ = try await render("holding-editor-revealed", store: store, reuse: shared)
        store.revealed = false
        _ = try await render("holding-editor-hidden-again", store: store, reuse: shared)
        store.route = .edit(state.items[0].id, true)
        _ = try await render("alert-editor", store: store, reuse: shared)
        store.route = .add
        _ = try await render("add-stock", store: store, reuse: shared)
        store.route = .sorting
        _ = try await render("watchlist-sorting", store: store, reuse: shared)
        let refreshSection = NSHostingView(rootView: AnyView(RefreshSettingsView(store: store, expanded: .constant(true))
            .font(.system(size: 11)).controlSize(.small).padding(12).frame(width: 280).background(UI.background)))
        _ = try await render("refresh-expanded", store: store, reuse: refreshSection)
        let updateSection = NSHostingView(rootView: AnyView(UpdateSettingsView(checker: store.updateChecker, expanded: .constant(true))
            .padding(12).frame(width: 280).background(UI.background)))
        _ = try await render("update-expanded", store: store, reuse: updateSection)
        store.route = .settings
        let settingsSize = try await render("settings", store: store, reuse: shared)
        func allSubviews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { allSubviews($0) } }
        func checkScrollWidth() -> NSScrollView {
            let scroll = allSubviews(shared).compactMap { $0 as? NSScrollView }.first!
            let frame = scroll.convert(scroll.bounds, to: shared)
            precondition(abs(frame.minX) < 0.5 && abs(frame.width - 280) < 0.5,
                "Disclosure expansion shifted content or overflowed the 280pt panel: \(frame)")
            return scroll
        }
        func scrollToBottom() {
            let scroll = checkScrollWidth()
            let bottom = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        _ = checkScrollWidth()
        for (section, name) in [(SettingsSection.data, "data"), (.refresh, "refresh"), (.notifications, "notifications"), (.updates, "updates")] {
            store.expandedSettings = [section]
            _ = try await render("settings-" + name + "-expanded", store: store, reuse: shared)
            _ = checkScrollWidth()
        }
        store.expandedSettings = [.data]
        _ = try await render("settings-data-expanded-dark", store: store, dark: true, reuse: shared)
        scrollToBottom()
        _ = try await render("settings-data-bottom-dark", store: store, dark: true, reuse: shared)
        let bottomScroll = checkScrollWidth()
        precondition(bottomScroll.contentView.bounds.maxY >= (bottomScroll.documentView?.frame.height ?? 0) - 0.5,
            "Bottom settings actions must be reachable by scrolling")
        store.expandedSettings = [.data, .refresh, .notifications, .updates]
        _ = try await render("settings-all-expanded", store: store, reuse: shared)
        _ = checkScrollWidth()
        store.panelHeightLimit = 180
        _ = try await render("settings-short-screen", store: store, reuse: shared)
        scrollToBottom()
        _ = try await render("settings-short-screen-bottom", store: store, reuse: shared)
        let shortScroll = checkScrollWidth()
        precondition(shortScroll.contentView.bounds.maxY >= (shortScroll.documentView?.frame.height ?? 0) - 0.5,
            "Short-screen settings must still scroll to the bottom")
        store.panelHeightLimit = 420
        store.expandedSettings = []
        let collapsedSize = try await render("settings-recollapsed", store: store, reuse: shared)
        precondition(abs(collapsedSize.height - settingsSize.height) < 0.5 && checkScrollWidth().contentView.bounds.minY == 0,
            "Collapsing settings must restore original height and scroll position")
        store.setGlobalShortcut(GlobalShortcut(keyCode: 49, modifiers: [.control, .option]))
        _ = try await render("settings-shortcut", store: store, reuse: shared)
        store.isRecordingShortcut = true
        _ = try await render("settings-shortcut-recording", store: store, reuse: shared)
        store.isRecordingShortcut = false
        store.setGlobalShortcut(GlobalShortcut(keyCode: 0, modifiers: []))
        _ = try await render("settings-shortcut-error", store: store, reuse: shared)
        store.setGlobalShortcut(nil)
        store.message = "测试通知已提交；横幅显示受系统通知和专注模式设置影响。" + String(repeating: "长提示不得挤压正文。", count: 10)
        let messageSize = try await render("settings-with-message", store: store, reuse: shared)
        precondition(abs(messageSize.height - min(store.panelHeightLimit, settingsSize.height + 25)) < 2, "Message must use a fixed-height strip")
        store.route = .details
        store.panelHeightLimit = 180
        _ = try await render("short-screen-details", store: store, reuse: shared)
        store.panelHeightLimit = 420
        store.resetPrivacy()
        store.showHoldings = false
        let restored = try await render("restored-home", store: store, reuse: shared)
        precondition(abs(restored.height - homeSize.height) < 2 && !store.revealed, "Home geometry/privacy did not restore")
        print("Shared-host route transitions, fixed status strip, screen-height bound and privacy reset passed.")
    }
}
