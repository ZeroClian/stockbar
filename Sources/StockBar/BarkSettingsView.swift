import SwiftUI
import AppKit
import StockCore

enum BarkPreview {
    static func message(configuration: BarkConfiguration, test: Bool = false) throws -> BarkMessage {
        let symbol = try StockSymbol("159915")
        let quote = Quote(symbol: symbol, name: "创业板ETF", last: Decimal(string: "2.651")!, previousClose: Decimal(string: "2.678")!, percent: -1.01, timestamp: Date(timeIntervalSince1970: 1792717200))
        let candidate = AlertCandidate(key: "sz159915|priceBelow|2.66", day: MarketClock.day(quote.timestamp), symbol: symbol, title: "", body: "", value: quote.last)
        return try BarkMessage(configuration: configuration, candidate: candidate, quote: quote, test: test)
    }
}

struct BarkSettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var draft = BarkConfiguration()
    @ViewState private var key = ""
    @ViewState private var pushURL = ""
    @ViewState private var tab = 0
    @ViewState private var testing = false
    @ViewState private var testTask: Task<Void, Never>?
    @ViewState private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.state.bark.enabled ? "已启用" : "未启用").foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Bark 设置分类", selection: $tab) {
                    Text("连接").tag(0)
                    Text("模板").tag(1)
                }.pickerStyle(.segmented).labelsHidden()
                if tab == 0 {
                    Toggle("启用 Bark", isOn: $draft.enabled)
                    SecureField("完整推送网址（含设备密钥）", text: $pushURL)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Bark 完整推送网址")
                    HStack {
                        Button("导入网址") { importURL(pushURL) }.disabled(pushURL.isEmpty || testing)
                        Button("从剪贴板导入") {
                            guard let text = NSPasteboard.general.string(forType: .string) else {
                                store.error = "剪贴板中没有文字网址。"; return
                            }
                            importURL(text)
                        }.disabled(testing)
                    }
                    Text("可直接导入 Bark 的完整推送网址；下方自动填入地址和密钥，保存后生效。自建服务有路径前缀时，请分别填写。")
                        .foregroundColor(.secondary)
                    TextField("服务地址", text: $draft.server)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Bark HTTPS 服务地址")
                    SecureField("设备密钥（留空保留已保存密钥）", text: $key)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Bark 设备密钥")
                    Text(store.hasBarkKey ? "密钥已就绪，推送时复用。" : "密钥通过钥匙串保存；仅保存或更新密钥时可能请求授权。")
                        .foregroundColor(.secondary)
                } else {
                    Text("信息模板").fontWeight(.medium)
                    Text("标题随触发规则自动变化，如“跌到价格”“持仓盈利”。")
                        .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("补充说明（最多 120 字）").foregroundColor(.secondary)
                    TextEditor(text: $draft.note).font(.system(size: 11)).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
                        .accessibilityLabel("Bark 可编辑补充说明")
                    Toggle("发送阈值和触发数值", isOn: $draft.includeValues)
                    Text(draft.includeValues ? "包含实际价格或持仓盈亏，将经 Bark 服务发送到手机。" : "发送真实股票名称和规则类型，不显示行情时间。")
                        .foregroundColor(.secondary)
                    Text("关键信息由程序生成，不能编辑或删除；关闭数值时保留其余固定信息。")
                        .foregroundColor(.secondary)
                    if let preview = try? BarkPreview.message(configuration: draft) {
                        DisclosureGroup("预览 · 示例数据") {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(preview.title).fontWeight(.medium)
                                Text(preview.facts).monospacedDigit()
                                if !preview.note.isEmpty { Text("补充说明：\n" + preview.note).foregroundColor(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(UI.surface).cornerRadius(6)
                        }
                    }
                }
                HStack {
                    Button("保存") {
                        if store.saveBarkSettings(draft, newKey: key) { key = "" }
                    }.disabled(!store.storageHealthy || testing)
                    Button(testing ? "发送中…" : "发送测试") {
                        testing = true
                        testTask = Task { await store.testBark(); testing = false }
                    }.disabled(testing || !store.storageHealthy || !store.state.bark.enabled || draft != store.state.bark || !key.isEmpty)
                    Spacer(minLength: 0)
                }
                if tab == 0 {
                    Button("删除密钥并停用") { confirmRemoval = true }.disabled(testing || !store.storageHealthy)
                }
                DisclosureGroup("使用说明") {
                    Text("先保存，再发送测试：使用状态栏关注项的代码和价格，缺失字段显示 xxxx，不消耗提醒次数。在 iPhone 的 Watch → 通知中开启 Bark 镜像；手机锁屏、手表佩戴解锁时通常在手表显示。")
                        .foregroundColor(.secondary)
                    Text("每只自选需单独选择 Bark。Mac 运行且未休眠时监测，休市暂停。声音与触感由设备设置决定。")
                        .foregroundColor(.secondary)
                }
            }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
        .onAppear { draft = store.state.bark; store.refreshBarkStatus() }
        .onChange(of: store.state.bark) { value in draft = value }
        .onDisappear { key = ""; pushURL = ""; testTask?.cancel() }
        .confirmationDialog("删除设备密钥并停用 Bark？自选及提醒规则会保留。", isPresented: $confirmRemoval) {
            Button("删除并停用", role: .destructive) { store.removeBarkKey(); key = "" }
            Button("取消", role: .cancel) {}
        }
    }
    private func importURL(_ value: String) {
        do {
            let connection = try BarkConnection(pushURL: value)
            draft.server = connection.server
            key = connection.key
            pushURL = ""
            store.error = nil
            store.message = "地址和密钥已填入；请启用 Bark 并保存。"
        } catch { store.error = error.localizedDescription }
    }

}
