import AppKit
import StockCore

/// Local to the visible panel. Never registers system-wide hotkeys.
@MainActor extension AppStore {
    var keyboardItems: [WatchItem] { showHoldings ? holdings : state.items }
    var keyboardItem: WatchItem? {
        keyboardItems.first { $0.id == keyboardSelection }
            ?? keyboardItems.first { $0.id == state.pinnedSymbol }
            ?? keyboardItems.first
    }

    func selectKeyboardItem(offset: Int) {
        let items = keyboardItems
        guard !items.isEmpty else { keyboardSelection = nil; return }
        if let selected = keyboardSelection, let index = items.firstIndex(where: { $0.id == selected }) {
            keyboardSelection = items[min(max(index + offset, 0), items.count - 1)].id
        } else { keyboardSelection = keyboardItem?.id }
    }

    func showKeyboardList(holdings: Bool) {
        showHoldings = holdings
        route = .home
        keyboardSelection = keyboardItem?.id
    }

    /// Returns true only for a command actually handled by the panel.
    func handlePanelKey(_ event: NSEvent, editingText: Bool) -> Bool {
        guard event.type == .keyDown, !isRecordingShortcut else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "1": showKeyboardList(holdings: false)
            case "2": showKeyboardList(holdings: true)
            case "3":
                let id: String?
                if case .edit(let current, _) = route { id = current } else { id = keyboardItem?.id }
                if let id { route = .edit(id, true) }
            case "f": if storageHealthy { message = nil; route = .add }
            case "r": if !event.isARepeat { Task { await self.refresh(manually: true) } }
            case ",": message = nil; route = .settings
            case "i": route = .inbox
            case "k": message = nil; route = .settingsPage(.appearance)
            case "[":
                guard route != .home else { return false }
                goBackFromKeyboard()
            case "d":
                guard route == .home || isStockEditor else { return false }
                if !event.isARepeat { revealed.toggle() }
            case "\r":
                if route == .home, let item = keyboardItem, storageHealthy { pinStock(item.id) }
                else { return false }
            default: return false // Copy/paste/select all/undo remain AppKit's responsibility.
            }
            return true
        }
        guard modifiers.isEmpty, !editingText else { return false }
        switch event.keyCode {
        case 125, 126:
            guard route == .home else { return false }
            selectKeyboardItem(offset: event.keyCode == 125 ? 1 : -1)
        case 36, 76, 124:
            guard route == .home else { return false }
            if let item = keyboardItem { keyboardSelection = item.id; route = .edit(item.id, false) }
        case 123:
            guard route != .home else { return false }
            goBackFromKeyboard()
        case 49:
            guard route == .home || isStockEditor else { return false }
            if !event.isARepeat { revealed.toggle() }
        default: return false
        }
        return true
    }

    private func goBackFromKeyboard() {
        if case .settingsPage = route { route = .settings } else { route = .home }
    }

    private var isStockEditor: Bool {
        if case .edit = route { return true }
        return false
    }
}
