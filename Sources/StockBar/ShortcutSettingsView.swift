import AppKit
import SwiftUI
import StockCore

struct ShortcutSettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var monitor: Any?
    @ViewState private var capture = ShortcutCapture()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("全局快捷键")
                Spacer(minLength: 0)
                Button(store.isRecordingShortcut ? (capture.pending.map { $0.displayName + " · 松开" } ?? "按组合键…") : (store.state.globalShortcut?.displayName ?? "点击设置")) {
                    store.isRecordingShortcut.toggle()
                }.help("点击后按下组合键；同一组合键打开或收起面板")
                    .accessibilityLabel("设置全局打开或收起快捷键")
                    .disabled(!store.storageHealthy)
                if store.state.globalShortcut != nil && !store.isRecordingShortcut {
                    Button("清除") { store.setGlobalShortcut(nil) }.disabled(!store.storageHealthy)
                }
            }
            Text(store.isRecordingShortcut ? "至少两个修饰键，含 ⌃ 或 ⌘；加字母、数字或空格。Esc 取消。" : "同一组合键打开／收起；点击修改。")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = store.shortcutError {
                Text(error).font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel("快捷键设置失败：" + error)
            }
        }
        .onChange(of: store.isRecordingShortcut) { recording in
            removeMonitor()
            capture = ShortcutCapture()
            if recording {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                    guard store.isRecordingShortcut, store.route == .settings, NSApp.isActive else { return event }
                    if event.type == .keyUp {
                        if let shortcut = capture.keyUp(UInt32(event.keyCode)) { store.setGlobalShortcut(shortcut) }
                        return nil
                    }
                    if event.keyCode == 53 { store.isRecordingShortcut = false; return nil }
                    guard !event.isARepeat else { return nil }
                    let shortcut = GlobalShortcut(event: event)
                    // The registered key arrives through Carbon; that callback cancels recording without toggling.
                    if shortcut == store.shortcutManager.current { return nil }
                    do { try capture.keyDown(shortcut, isRepeat: event.isARepeat) }
                    catch { store.setGlobalShortcut(shortcut) } // The store presents the validation failure.
                    return nil
                }
            }
        }
        .onDisappear { store.isRecordingShortcut = false; removeMonitor() }
    }
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
