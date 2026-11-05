import AppKit
import Foundation
import Testing
import UserNotifications
import StockCore
@testable import StockBar

@MainActor private final class PanelNotifications: NotificationSending {
    func status() async -> UNAuthorizationStatus { .denied }
    func requestPermission() async throws -> Bool { false }
    func send(identifier: String, title: String, body: String) async throws {}
}

@MainActor private func panelEvent(_ code: UInt16, _ text: String, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                    context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: repeatKey, keyCode: code)!
}

@MainActor private func panelStore(_ root: URL) throws -> AppStore {
    let items = try ["600519", "300750", "159915"].enumerated().map { index, code in
        WatchItem(symbol: try StockSymbol(code), name: "测试" + code,
                  holding: Holding(quantity: index == 1 ? 0 : 100, averageCost: 10))
    }
    try StateFile(url: root.appendingPathComponent("state.json")).save(SavedState(items: items, pinnedSymbol: items[0].id))
    return AppStore(dataDirectory: root, notifications: PanelNotifications())
}

@MainActor @Test func panelKeysNavigateVisibleRowsOpenDetailsAndPreserveSelection() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try panelStore(root)
    let original = store.state
    #expect(store.handlePanelKey(panelEvent(125, "", modifiers: .function), editingText: false))
    #expect(store.keyboardSelection == "sh600519")
    #expect(store.handlePanelKey(panelEvent(125, ""), editingText: false))
    #expect(store.keyboardSelection == "sz300750")
    #expect(store.handlePanelKey(panelEvent(36, "\r"), editingText: false))
    #expect(store.route == .edit("sz300750", false))
    #expect(store.handlePanelKey(panelEvent(20, "3", modifiers: .command), editingText: false))
    #expect(store.route == .edit("sz300750", true))
    #expect(store.handlePanelKey(panelEvent(123, ""), editingText: false))
    #expect(store.route == .home && store.keyboardSelection == "sz300750")
    #expect(store.handlePanelKey(panelEvent(19, "2", modifiers: .command), editingText: false))
    #expect(store.showHoldings && store.keyboardSelection == "sh600519")
    _ = store.handlePanelKey(panelEvent(125, ""), editingText: false)
    #expect(store.keyboardSelection == "sz159915") // Skip the unheld stock.
    _ = store.handlePanelKey(panelEvent(125, ""), editingText: false)
    #expect(store.keyboardSelection == "sz159915")
    #expect(store.state == original) // Browsing never changes the pinned stock or saved data.
    _ = store.handlePanelKey(panelEvent(36, "\r", modifiers: .command), editingText: false)
    #expect(store.state.pinnedSymbol == "sz159915")
}

@MainActor @Test func panelKeysDoNotStealTextEditingOrGlobalShortcutRecording() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try panelStore(root)
    for (code, value): (UInt16, String) in [(125, ""), (126, ""), (123, ""), (124, ""), (36, "\r"), (49, " ")] {
        #expect(!store.handlePanelKey(panelEvent(code, value), editingText: true))
    }
    for value in ["a", "c", "v", "x", "z", "s"] {
        #expect(!store.handlePanelKey(panelEvent(0, value, modifiers: .command), editingText: true))
    }
    #expect(!store.handlePanelKey(panelEvent(19, "2", modifiers: [.command, .shift]), editingText: false))
    store.isRecordingShortcut = true
    #expect(!store.handlePanelKey(panelEvent(19, "2", modifiers: .command), editingText: false))
    store.isRecordingShortcut = false
    _ = store.handlePanelKey(panelEvent(49, " "), editingText: false)
    #expect(store.revealed)
    _ = store.handlePanelKey(panelEvent(49, " ", repeatKey: true), editingText: false)
    #expect(store.revealed)
    store.route = .edit("sh600519", false)
    _ = store.handlePanelKey(panelEvent(2, "d", modifiers: .command), editingText: true)
    #expect(!store.revealed)
    _ = store.handlePanelKey(panelEvent(33, "[", modifiers: .command), editingText: true)
    #expect(store.route == .home)
    store.resetPrivacy()
    #expect(!store.revealed && store.keyboardSelection == nil && store.route == .home)
}

@MainActor @Test func panelKeysHandleEmptyListsAndSettingsBackNavigation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppStore(dataDirectory: root, notifications: PanelNotifications())
    _ = store.handlePanelKey(panelEvent(125, ""), editingText: false)
    _ = store.handlePanelKey(panelEvent(36, "\r"), editingText: false)
    #expect(store.route == .home && store.keyboardSelection == nil)
    _ = store.handlePanelKey(panelEvent(43, ",", modifiers: .command), editingText: false)
    #expect(store.route == .settings)
    _ = store.handlePanelKey(panelEvent(40, "k", modifiers: .command), editingText: true)
    #expect(store.route == .settingsPage(.appearance))
    _ = store.handlePanelKey(panelEvent(33, "[", modifiers: .command), editingText: true)
    #expect(store.route == .settings)
    store.route = .settingsPage(.bark)
    _ = store.handlePanelKey(panelEvent(123, ""), editingText: false)
    #expect(store.route == .settings)
    _ = store.handlePanelKey(panelEvent(3, "f", modifiers: .command), editingText: false)
    #expect(store.route == .add)
    #expect(!store.handlePanelKey(panelEvent(125, ""), editingText: false))
}
