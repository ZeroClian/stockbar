import AppKit
import SwiftUI
import StockCore

struct ShortcutSettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var monitor: Any?
    @ViewState private var capture = ShortcutCapture()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("全局快捷键")
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                HStack(spacing: 5) {
                    Text(action.title)
                    Spacer(minLength: 0)
                    Button(buttonTitle(action)) {
                        if store.isRecordingShortcut && store.recordingShortcutAction == action { store.isRecordingShortcut = false }
                        else { store.recordingShortcutAction = action; store.isRecordingShortcut = true }
                    }.accessibilityLabel("设置" + action.title + "快捷键")
                        .disabled(!store.storageHealthy)
                    if store.shortcut(for: action) != nil && !store.isRecordingShortcut {
                        Button("清除") { store.setGlobalShortcut(nil, action: action) }.disabled(!store.storageHealthy)
                    }
                }
            }
            Text(store.isRecordingShortcut ? "至少两个修饰键，含 ⌃ 或 ⌘；加字母、数字、空格或 ← →。Esc 取消。" : "上一只／下一只按自选顺序循环，不展开面板。仅图标模式下仍保持隐藏。")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = store.shortcutError {
                Text(error).font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel("快捷键设置失败：" + error)
            }
        }
        .onChange(of: store.isRecordingShortcut) { _ in updateMonitor() }
        .onChange(of: store.recordingShortcutAction) { _ in updateMonitor() }
        .onDisappear { store.isRecordingShortcut = false; removeMonitor() }
    }
    private func buttonTitle(_ action: ShortcutAction) -> String {
        if store.isRecordingShortcut && store.recordingShortcutAction == action {
            return capture.pending.map { $0.displayName + " · 松开" } ?? "按组合键…"
        }
        return store.shortcut(for: action)?.displayName ?? "点击设置"
    }
    private func updateMonitor() {
        removeMonitor()
        capture = ShortcutCapture()
        let action = store.recordingShortcutAction
        if store.isRecordingShortcut {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                guard store.isRecordingShortcut, store.route == .settings, NSApp.isActive else { return event }
                if event.type == .keyUp {
                    if let shortcut = capture.keyUp(UInt32(event.keyCode)) { store.setGlobalShortcut(shortcut, action: action) }
                    return nil
                }
                if event.keyCode == 53 { store.isRecordingShortcut = false; return nil }
                guard !event.isARepeat else { return nil }
                let shortcut = GlobalShortcut(event: event)
                // The registered key arrives through Carbon; that callback cancels recording without toggling.
                if ShortcutAction.allCases.contains(where: { store.manager(for: $0).current == shortcut }) { return nil }
                do { try capture.keyDown(shortcut, isRepeat: event.isARepeat) }
                catch { store.setGlobalShortcut(shortcut, action: action) } // The store presents the validation failure.
                return nil
            }
        }
    }
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
