import SwiftUI
import StockCore

enum BarkPreview {
    static func message(configuration: BarkConfiguration, test: Bool = false) throws -> BarkMessage {
        let symbol = try StockSymbol("159915")
        let quote = Quote(symbol: symbol, name: "示例ETF", last: Decimal(string: "2.651")!, previousClose: Decimal(string: "2.678")!, percent: -1.01, timestamp: Date(timeIntervalSince1970: 1792717200))
        let candidate = AlertCandidate(key: "sz159915|priceBelow|2.66", day: MarketClock.day(quote.timestamp), symbol: symbol, title: "", body: "", value: quote.last)
        return try BarkMessage(configuration: configuration, alias: "CYBETF", candidate: candidate, quote: quote, test: test)
    }
}

struct BarkSettingsView: View {
    @ObservedObject var store: AppStore
    @Binding var expanded: Bool
    @ViewState private var draft = BarkConfiguration()
    @ViewState private var key = ""
    @ViewState private var testing = false
    @ViewState private var testTask: Task<Void, Never>?
    @ViewState private var confirmRemoval = false

    var body: some View {
        DisclosureGroup("Bark 推送 · " + (store.state.bark.enabled ? "已启用" : "未启用"), isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("启用 Bark", isOn: $draft.enabled)
                TextField("服务地址", text: $draft.server)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Bark HTTPS 服务地址")
                SecureField(store.hasBarkKey ? "留空保留已保存密钥" : "设备密钥（不含网址）", text: $key)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Bark 设备密钥")
                Text(store.hasBarkKey ? "密钥已保存到本机钥匙串。" : "从 iPhone 的 Bark 推送网址中复制设备密钥。")
                    .foregroundColor(.secondary)
                Divider()
                Text("信息模板").fontWeight(.medium)
                TextField("标题（1–40 字）", text: $draft.title).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bark 通知标题")
                Text("补充说明（最多 120 字）").foregroundColor(.secondary)
                TextEditor(text: $draft.note).font(.system(size: 11)).frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
                    .accessibilityLabel("Bark 可编辑补充说明")
                Toggle("发送阈值和触发数值", isOn: $draft.includeValues)
                Text(draft.includeValues ? "包含实际价格或持仓盈亏，将经 Bark 服务发送到手机。" : "只发送代号、规则类型和行情时间。")
                    .foregroundColor(.secondary)
                Text("关键信息由程序生成，不能编辑或删除；关闭数值时保留其余固定信息。")
                    .foregroundColor(.secondary)
                if let preview = try? BarkPreview.message(configuration: draft) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("预览 · 示例数据").foregroundColor(.secondary)
                        Text(preview.title).fontWeight(.medium)
                        Text(preview.facts).monospacedDigit()
                        if !preview.note.isEmpty { Text("补充说明：\n" + preview.note).foregroundColor(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(UI.surface).cornerRadius(6)
                }
                HStack {
                    Button("保存") {
                        if store.saveBarkSettings(draft, newKey: key) { key = "" }
                    }.disabled(!store.storageHealthy || testing)
                    Button(testing ? "发送中…" : "发送测试") {
                        testing = true
                        testTask = Task { await store.testBark(); testing = false }
                    }.disabled(testing || !store.storageHealthy || !store.state.bark.enabled || !store.hasBarkKey || draft != store.state.bark || !key.isEmpty)
                    Spacer(minLength: 0)
                }
                if store.hasBarkKey {
                    Button("删除密钥并停用") { confirmRemoval = true }.disabled(testing || !store.storageHealthy)
                }
                Text("先保存，再发送示例测试。在 iPhone 的 Watch → 通知中开启 Bark 镜像；手机锁屏、手表佩戴解锁时通常在手表显示。")
                    .foregroundColor(.secondary)
                Text("每只自选需单独选择 Bark。Mac 运行且未休眠时监测，休市暂停。声音与触感由设备设置决定。")
                    .foregroundColor(.secondary)
            }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
        .onAppear { draft = store.state.bark }
        .onChange(of: expanded) { value in if value { store.refreshBarkStatus() } }
        .onChange(of: store.state.bark) { value in draft = value }
        .onDisappear { key = ""; testTask?.cancel() }
        .confirmationDialog("删除设备密钥并停用 Bark？自选及提醒规则会保留。", isPresented: $confirmRemoval) {
            Button("删除并停用", role: .destructive) { store.removeBarkKey(); key = "" }
            Button("取消", role: .cancel) {}
        }
    }
}
