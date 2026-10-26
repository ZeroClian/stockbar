import Foundation
import AppKit
import Testing
import UserNotifications
import StockCore
@testable import StockBar

@MainActor private final class NoShortcutNotifications: NotificationSending {
    func status() async -> UNAuthorizationStatus { .denied }
    func requestPermission() async throws -> Bool { false }
    func send(identifier: String, title: String, body: String) async throws {}
}

@MainActor private final class ShortcutBackendStub: ShortcutRegistering {
    final class Token: ShortcutRegistration {
        var active = true
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { active = false }
        func press() { if active { action() } }
    }
    var tokens: [Token] = []
    var rejectNext = false
    func register(_ shortcut: GlobalShortcut, action: @escaping @MainActor () -> Void) throws -> any ShortcutRegistration {
        if rejectNext { throw ShortcutError.unavailable(-1) }
        let token = Token(action); tokens.append(token); return token
    }
}

@MainActor @Test func shortcutReplacementFailureKeepsOriginalWorkingAndPersisted() throws {
    let backend = ShortcutBackendStub()
    let manager = GlobalShortcutManager(backend: backend)
    let original = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    let replacement = GlobalShortcut(keyCode: 1, modifiers: [.command, .shift])
    var saved: GlobalShortcut?
    var activations = 0
    manager.onActivate = { activations += 1 }
    try manager.replace(original) { saved = $0; return true }
    backend.rejectNext = true
    #expect(throws: (any Error).self) { try manager.replace(replacement) { saved = $0; return true } }
    backend.tokens[0].press()
    #expect(manager.current == original && saved == original && activations == 1)
    backend.rejectNext = false
    #expect(try !manager.replace(replacement) { _ in false })
    backend.tokens[0].press()
    backend.tokens[1].press()
    #expect(manager.current == original && saved == original && activations == 2)
}

@MainActor @Test func replacingAndClearingShortcutDisableOldEvents() throws {
    let backend = ShortcutBackendStub()
    let manager = GlobalShortcutManager(backend: backend)
    let first = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    let second = GlobalShortcut(keyCode: 1, modifiers: [.command, .shift])
    var activations = 0
    manager.onActivate = { activations += 1 }
    try manager.replace(first) { _ in true }
    try manager.replace(second) { _ in true }
    backend.tokens[0].press(); backend.tokens[1].press()
    #expect(activations == 1 && manager.current == second)
    #expect(try !manager.replace(nil) { _ in false })
    backend.tokens[1].press()
    #expect(activations == 2 && manager.current == second)
    try manager.replace(nil) { _ in true }
    backend.tokens[1].press()
    #expect(activations == 2 && manager.current == nil)
}

@MainActor @Test func shortcutIsSavedRestoredAndRecordingNeverTogglesPanel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = ShortcutBackendStub()
    let store = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: backend)
    let shortcut = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    var toggles = 0
    store.onShortcutToggle = { toggles += 1 }
    #expect(store.setGlobalShortcut(shortcut))
    #expect(try StateFile(url: directory.appendingPathComponent("state.json")).load().globalShortcut == shortcut)
    backend.tokens[0].press()
    #expect(toggles == 1)
    store.route = .settings
    store.isRecordingShortcut = true
    backend.tokens[0].press()
    #expect(toggles == 1 && !store.isRecordingShortcut)
    store.isRecordingShortcut = true
    store.revealed = true
    store.resetPrivacy()
    #expect(!store.isRecordingShortcut && !store.revealed)
    let otherBackend = ShortcutBackendStub()
    let restored = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: otherBackend)
    restored.restoreGlobalShortcut()
    restored.onShortcutToggle = { toggles += 1 }
    otherBackend.tokens[0].press()
    #expect(toggles == 2)
    #expect(restored.setGlobalShortcut(nil))
    #expect(try StateFile(url: restored.dataURL).load().globalShortcut == nil)
}

@MainActor @Test func invalidShortcutDoesNotDisableStorageAndConflictKeepsSavedSetting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = ShortcutBackendStub()
    let store = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: backend)
    let shortcut = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    #expect(store.setGlobalShortcut(shortcut))
    #expect(!store.setGlobalShortcut(GlobalShortcut(keyCode: 0, modifiers: [])))
    #expect(store.storageHealthy && store.shortcutError != nil)
    backend.rejectNext = true
    #expect(!store.setGlobalShortcut(GlobalShortcut(keyCode: 1, modifiers: [.command, .shift])))
    #expect(try StateFile(url: store.dataURL).load().globalShortcut == shortcut)
    #expect(store.state.globalShortcut == shortcut)
}

@Test func recordingWaitsForMatchingKeyReleaseAndIgnoresHeldRepeats() throws {
    var capture = ShortcutCapture()
    let shortcut = GlobalShortcut(keyCode: 49, modifiers: [.control, .option])
    try capture.keyDown(shortcut, isRepeat: false)
    #expect(capture.keyUp(1) == nil)
    try capture.keyDown(GlobalShortcut(keyCode: 1, modifiers: [.command, .shift]), isRepeat: true)
    #expect(capture.keyUp(49) == shortcut)
    #expect(capture.keyUp(49) == nil)
    try capture.keyDown(shortcut, isRepeat: false)
    #expect(throws: (any Error).self) { try capture.keyDown(GlobalShortcut(keyCode: 0, modifiers: []), isRepeat: false) }
    #expect(capture.keyUp(49) == nil)
}

@MainActor @Test func stockShortcutsCycleCurrentOrderWithoutOpeningOrRevealingAndRestore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let items = try ["300750", "600519", "510300"].map { WatchItem(symbol: try StockSymbol($0), name: $0) }
    let file = StateFile(url: directory.appendingPathComponent("state.json"))
    try file.save(SavedState(items: items, pinnedSymbol: items[2].id))
    let backend = ShortcutBackendStub()
    let store = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: backend)
    var opens = 0
    store.onShortcutToggle = { opens += 1 }
    let next = GlobalShortcut(keyCode: 124, modifiers: [.control, .option])
    let previous = GlobalShortcut(keyCode: 123, modifiers: [.control, .option])
    #expect(store.setGlobalShortcut(next, action: .nextStock))
    #expect(store.setGlobalShortcut(previous, action: .previousStock))
    store.closePanel()
    backend.tokens[0].press()
    #expect(store.state.pinnedSymbol == items[0].id && store.route == .home && !store.revealed && opens == 0)
    #expect(store.state.menuMode == .icon)
    backend.tokens[1].press()
    #expect(store.state.pinnedSymbol == items[2].id)
    store.isRecordingShortcut = true
    backend.tokens[0].press()
    #expect(!store.isRecordingShortcut && store.state.pinnedSymbol == items[2].id)
    store.stop()
    let restoredBackend = ShortcutBackendStub()
    let restored = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: restoredBackend)
    restored.restoreGlobalShortcut()
    #expect(restored.state.previousStockShortcut == previous && restored.state.nextStockShortcut == next)
    restoredBackend.tokens[1].press()
    #expect(try file.load().pinnedSymbol == items[0].id)
    restored.moveItem(items[0].id, offset: 1)
    restoredBackend.tokens[1].press()
    #expect(restored.state.pinnedSymbol == items[2].id)
    #expect(restored.setGlobalShortcut(nil, action: .nextStock))
    restoredBackend.tokens[1].press()
    #expect(restored.state.pinnedSymbol == items[2].id && restored.state.nextStockShortcut == nil)
}

@MainActor @Test func shortcutActionsRejectDuplicatesWithoutDamagingSavedBindings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = ShortcutBackendStub()
    let store = AppStore(dataDirectory: directory, notifications: NoShortcutNotifications(), shortcutBackend: backend)
    let first = GlobalShortcut(keyCode: 124, modifiers: [.control, .option])
    #expect(store.setGlobalShortcut(first, action: .nextStock))
    #expect(!store.setGlobalShortcut(first, action: .previousStock))
    #expect(!store.setGlobalShortcut(first))
    #expect(store.storageHealthy && store.state.globalShortcut == nil && store.state.previousStockShortcut == nil)
    backend.rejectNext = true
    #expect(!store.setGlobalShortcut(GlobalShortcut(keyCode: 123, modifiers: [.control, .option]), action: .nextStock))
    #expect(store.state.nextStockShortcut == first)
    var invalid = store.state
    invalid.previousStockShortcut = first
    #expect(throws: (any Error).self) { try invalid.validate() }
    store.cycleStock(offset: 1)
    #expect(store.state.items.isEmpty && store.state.pinnedSymbol == nil)
}

@MainActor @Test func arrowShortcutIgnoresAutomaticFunctionFlag() throws {
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option, .function, .numericPad], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
    let shortcut = GlobalShortcut(event: event)
    try shortcut.validate()
    #expect(shortcut == GlobalShortcut(keyCode: 124, modifiers: [.control, .option]))
}
