import AppKit
import SwiftUI
import StockCore

struct ShortcutSettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var monitor: Any?
    @ViewState private var capture = ShortcutCapture()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("全局快捷键 · 可自定义").fontWeight(.medium)
            helpNote("应用运行时生效，在其他应用中也能使用。")
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
            Divider().padding(.vertical, 4)
            Text("面板内快捷键 · 固定按键").fontWeight(.medium)
            helpNote("仅面板打开且处于前台时生效。")
            shortcutRow("↑ / ↓", "选择上一只 / 下一只股票")
            shortcutRow("回车 / →", "查看选中股票的持仓详情")
            shortcutRow("⌘1 / ⌘2", "自选列表 / 持仓列表")
            shortcutRow("⌘3", "当前股票的提醒设置")
            shortcutRow("空格 / ⌘D", "显示 / 隐藏名称与金额")
            shortcutRow("← / ⌘[", "返回上一级")
            shortcutRow("⌘F", "搜索添加股票或 ETF")
            shortcutRow("⌘R", "手动刷新（休市也可用）")
            shortcutRow("⌘I", "查看未读提醒")
            shortcutRow("⌘,", "打开偏好设置")
            shortcutRow("⌘K", "显示与快捷键设置")
            shortcutRow("⌘回车", "关注列表选中股票")
            shortcutRow("⌘S", "保存单项持仓或提醒编辑")
            shortcutRow("Esc", "收起面板并恢复隐藏")
            helpNote("↑↓、回车、→ 和关注操作用于列表；显示／隐藏用于列表与股票详情。输入框内方向键、空格、回车保留编辑功能，可用 ⌘[ 返回、⌘D 显示／隐藏。")
            helpNote("切换页面会放弃未保存的编辑，请先保存。录制全局快捷键时暂停面板快捷键，Esc 仅取消录制。")
            Divider().padding(.vertical, 4)
            Text("文本编辑 · 输入框内").fontWeight(.medium)
            shortcutRow("⌘C / ⌘V", "复制 / 粘贴")
            shortcutRow("⌘X / ⌘A", "剪切 / 全选")
            shortcutRow("⌘Z / ⇧⌘Z", "撤销 / 重做")
            shortcutRow("Tab / ⇧Tab", "下一个 / 上一个输入项")
        }
        .onChange(of: store.isRecordingShortcut) { _ in updateMonitor() }
        .onChange(of: store.recordingShortcutAction) { _ in updateMonitor() }
        .onDisappear { store.isRecordingShortcut = false; removeMonitor() }
    }
    private func helpNote(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 84, alignment: .leading)
            Text(action).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
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
                guard store.isRecordingShortcut, store.route == .settingsPage(.appearance), NSApp.isActive else { return event }
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
