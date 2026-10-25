import AppKit
import Carbon
import StockCore

@MainActor protocol ShortcutRegistration: AnyObject { func cancel() }
@MainActor protocol ShortcutRegistering {
    func register(_ shortcut: GlobalShortcut, action: @escaping @MainActor () -> Void) throws -> any ShortcutRegistration
}

enum ShortcutError: LocalizedError {
    case systemConflict, unavailable(OSStatus)
    var errorDescription: String? {
        switch self {
        case .systemConflict: return "该组合键已用于系统功能，请换一组。"
        case .unavailable: return "该组合键被占用或无法注册，请换一组；原设置未更改。"
        }
    }
}

/// Keep the previous registration live until both the new registration and disk save succeed.
@MainActor final class GlobalShortcutManager {
    private let backend: any ShortcutRegistering
    private var registration: (any ShortcutRegistration)?
    private(set) var current: GlobalShortcut?
    var onActivate: (() -> Void)?
    init(backend: any ShortcutRegistering) { self.backend = backend }

    @discardableResult func replace(_ shortcut: GlobalShortcut?, persist: (GlobalShortcut?) -> Bool) throws -> Bool {
        try shortcut?.validate()
        if shortcut == current { return persist(shortcut) }
        let candidate = try shortcut.map { value in
            try backend.register(value) { [weak self] in
                guard self?.current == value else { return }
                self?.onActivate?()
            }
        }
        guard persist(shortcut) else { candidate?.cancel(); return false }
        registration?.cancel()
        registration = candidate
        current = shortcut
        return true
    }
    func stop() { registration?.cancel(); registration = nil; current = nil }
}

extension GlobalShortcut {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
    init(event: NSEvent) {
        var flags: ShortcutModifiers = []
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        if event.modifierFlags.contains(.function) { flags.insert(.init(rawValue: 16)) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags)
    }
}

@MainActor final class CarbonShortcutBackend: ShortcutRegistering {
    private var nextID: UInt32 = 1
    func register(_ shortcut: GlobalShortcut, action: @escaping @MainActor () -> Void) throws -> any ShortcutRegistration {
        try shortcut.validate()
        var hotKeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&hotKeys)
        guard status == noErr, let keys = hotKeys?.takeRetainedValue() as? [[String: Any]] else {
            throw ShortcutError.unavailable(status)
        }
        for key in keys {
            if (key[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
               (key[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode,
               (key[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.carbonModifiers {
                throw ShortcutError.systemConflict
            }
        }
        let id = EventHotKeyID(signature: 0x53544252, id: nextID) // STBR
        nextID &+= 1
        return try CarbonShortcutRegistration(shortcut: shortcut, id: id, action: action)
    }
}

/// The application event target dispatches on the main event loop. No key-event tap is installed.
@MainActor private final class CarbonShortcutRegistration: ShortcutRegistration {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: EventHotKeyID
    private let action: @MainActor () -> Void
    private var pressed = false
    private var active = true

    init(shortcut: GlobalShortcut, id: EventHotKeyID, action: @escaping @MainActor () -> Void) throws {
        self.id = id; self.action = action
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<CarbonShortcutRegistration>.fromOpaque(context).takeUnretainedValue()
                return owner.receive(event)
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { throw ShortcutError.unavailable(installed) }
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
        guard result == noErr else { cancel(); throw ShortcutError.unavailable(result) }
    }
    private func receive(_ event: EventRef) -> OSStatus {
        var incoming = EventHotKeyID()
        guard active, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &incoming) == noErr,
              incoming.signature == id.signature, incoming.id == id.id else { return OSStatus(eventNotHandledErr) }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { pressed = false }
        else if !pressed { pressed = true; action() }
        return noErr
    }
    func cancel() {
        active = false
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

/// Registration starts after the captured physical key is released, never while it is held.
struct ShortcutCapture {
    private(set) var pending: GlobalShortcut?
    mutating func keyDown(_ shortcut: GlobalShortcut, isRepeat: Bool) throws {
        guard !isRepeat else { return }
        pending = nil
        try shortcut.validate()
        pending = shortcut
    }
    mutating func keyUp(_ keyCode: UInt32) -> GlobalShortcut? {
        guard pending?.keyCode == keyCode else { return nil }
        defer { pending = nil }
        return pending
    }
}
