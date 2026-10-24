import AppKit
import Combine
import SwiftUI
import StockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: AppStore!
    private var titleSubscription: AnyCancellable?
    private var panelObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        let customDirectory: URL?
        if let flag = args.firstIndex(of: "--data-dir"), flag + 1 < args.count {
            customDirectory = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        } else { customDirectory = nil }
        store = AppStore(dataDirectory: customDirectory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePanel)
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("打开速览")
            button.toolTip = "速览"
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(store: store))
        popover.contentViewController = host
        titleSubscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle(); self?.resizePanel() }
        }
        panelObserver = NotificationCenter.default.addObserver(forName: .openStockPanel, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showPanel() }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: .closeStockPanel, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
        updateTitle()
        store.start()
        if args.contains("--show-panel") { showPanel() }
    }

    private func updateTitle() {
        statusItem.button?.title = store.menuTitle
        let unread = store.hasUnreadAlerts
        let image = NSImage(size: NSSize(width: unread ? 22 : 16, height: 16), flipped: false) { _ in
            NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?.draw(in: NSRect(x: 1, y: 1, width: 14, height: 14))
            if unread { NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 18, y: 10, width: 3, height: 3)).fill() }
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = unread ? "速览 · 有提醒" : "速览"
        statusItem.button?.setAccessibilityLabel(unread ? "速览，有未读提醒" : "打开速览")
    }
    private func resizePanel() {
        guard popover != nil else { return }
        let statusHeight: CGFloat = store.error != nil || store.message != nil ? 25 : 0
        let target = NSSize(width: 280, height: min(store.panelHeightLimit, store.panelContentHeight + statusHeight))
        if popover.contentSize != target { popover.contentSize = target }
    }
    func popoverDidClose(_ notification: Notification) { store.resetPrivacy() }
    func applicationDidResignActive(_ notification: Notification) {
        if popover?.isShown == true { store.resetPrivacy(); popover.performClose(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if popover != nil { showPanel() }
        return false
    }
    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    private func showPanel() {
        guard let button = statusItem.button else { return }
        store.resetPrivacy()
        store.panelHeightLimit = min(420, max(120, (button.window?.screen?.visibleFrame.height ?? 600) - 40))
        resizePanel()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.updatePermission() }
    }
}

@main
struct StockBarEntry {
    @MainActor static func main() {
// Read-only diagnostic entry point: no notifications, settings, or holdings are created.
if CommandLine.arguments.contains("--check-market") {
    Task {
        do {
            let symbols = try ["600519", "000001", "300750", "301269", "688981", "920002"].map { try StockSymbol($0) }
            let quotes = try await QuoteService().fetch(symbols)
            for symbol in symbols {
                guard let q = quotes[symbol.rawValue] else { throw QuoteServiceError.empty }
                print("\(q.symbol.rawValue) \(q.name) 涨跌 \(q.change) 涨跌幅 \(q.percent)% 时间 \(UI.time(q.timestamp, full: true))")
            }
            exit(0)
        } catch { fputs("行情检查失败：\(error.localizedDescription)\n", stderr); exit(1) }
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

    }
}
