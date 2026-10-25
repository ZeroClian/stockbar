// Native API smoke check. Registers a temporary combination and dispatches events
// to this process; does not inject keyboard input or touch user settings.
import AppKit
import Carbon
import StockCore

@main struct ShortcutCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let backend = CarbonShortcutBackend()
        let manager = GlobalShortcutManager(backend: backend)
        defer { manager.stop() }
        let shortcut = GlobalShortcut(keyCode: 29, modifiers: [.control, .option, .shift, .command])
        var toggles = 0
        manager.onActivate = { toggles += 1 }
        try manager.replace(shortcut) { _ in true }
        do {
            let duplicate = try backend.register(shortcut) {}
            duplicate.cancel()
            fatalError("Exclusive registration failed to detect a duplicate")
        } catch { print("PASS: duplicate native registration rejected") }
        func event(_ id: UInt32, _ kind: UInt32) throws {
            var event: EventRef?
            guard CreateEvent(nil, OSType(kEventClassKeyboard), kind, GetCurrentEventTime(), 0, &event) == noErr,
                  let event else { throw CocoaError(.coderInvalidValue) }
            defer { ReleaseEvent(event) }
            var key = EventHotKeyID(signature: 0x53544252, id: id)
            guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    MemoryLayout<EventHotKeyID>.size, &key) == noErr else { throw CocoaError(.coderInvalidValue) }
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        }
        try event(1, UInt32(kEventHotKeyPressed))
        try event(1, UInt32(kEventHotKeyPressed))
        precondition(toggles == 1, "Held key toggled repeatedly")
        try event(1, UInt32(kEventHotKeyReleased))
        try event(1, UInt32(kEventHotKeyPressed))
        precondition(toggles == 2, "Second press was not delivered")
        try manager.replace(nil) { _ in true }
        try event(1, UInt32(kEventHotKeyPressed))
        precondition(toggles == 2, "Cleared shortcut still toggled")
        try manager.replace(shortcut) { _ in true }
        print("PASS: Carbon callback dispatch, held-key suppression, clear and re-register")
        print("This check does not prove physical keystrokes or popover behavior in other applications.")
    }
}
