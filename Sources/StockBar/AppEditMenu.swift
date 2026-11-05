import AppKit

/// Accessory apps still need an Edit menu to route keyboard equivalents to the field editor.
@MainActor enum AppEditMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key, modifiers): (String, String, String, NSEvent.ModifierFlags) in [
            ("撤销", "undo:", "z", .command),
            ("重做", "redo:", "z", [.command, .shift]),
            ("剪切", "cut:", "x", .command),
            ("复制", "copy:", "c", .command),
            ("粘贴", "paste:", "v", .command),
            ("全选", "selectAll:", "a", .command)
        ] {
            let command = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            command.keyEquivalentModifierMask = modifiers
            edit.addItem(command) // nil target uses the responder chain, including secure field editors.
        }
        item.submenu = edit
        menu.addItem(item)
        return menu
    }
}
