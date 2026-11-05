import AppKit
import Testing
@testable import StockBar

@MainActor private final class EditingTarget: NSObject {
    var pasted = false
    @objc func paste(_ sender: Any?) { pasted = true }
}

@MainActor @Test func editMenuDispatchesPasteShortcutAndProvidesStandardActions() throws {
    _ = NSApplication.shared
    let menu = AppEditMenu.make()
    let edit = try #require(menu.items.first?.submenu)
    let paste = try #require(edit.items.first(where: { $0.action == #selector(EditingTarget.paste(_:)) }))
    let target = EditingTarget()
    paste.target = target
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
    #expect(menu.performKeyEquivalent(with: event))
    #expect(target.pasted)
    for (key, action) in [("c", "copy:"), ("x", "cut:"), ("a", "selectAll:"), ("z", "undo:")] {
        #expect(edit.items.contains { $0.keyEquivalent == key && $0.action == NSSelectorFromString(action) && $0.target == nil })
    }
}
