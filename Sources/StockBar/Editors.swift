import AppKit
import SwiftUI
import StockCore

struct PanelHeader: View {
    @ObservedObject var store: AppStore
    let title: String
    let subtitle: String
    var showPrivacy = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", label: "返回速览") { store.route = .home }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if showPrivacy {
                    IconButton(symbol: store.revealed ? "eye" : "eye.slash", label: "显示或隐藏名称和持仓") { store.revealed.toggle() }
                }
                IconButton(symbol: "xmark", label: "立即收起") { store.closePanel() }
            }.padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
        }
    }
}

struct AddStockView: View {
    @ObservedObject var store: AppStore
    @ViewState private var code = ""
    @ViewState private var addTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store, title: "添加", subtitle: "")
            VStack(alignment: .leading, spacing: 10) {
                TextField("六位代码，例如 300750", text: $code)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityLabel("股票代码").onSubmit { add() }
                Text("沪深北 A 股 · 含创业板、科创板")
                    .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if store.isAdding { ProgressView().controlSize(.mini) }
                    Button("取消") { store.route = .home }
                    Button("添加") { add() }
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAdding || !store.storageHealthy)
                }
            }.font(.system(size: 11)).controlSize(.small).padding(12)
        }.onAppear { focused = true }.onDisappear { addTask?.cancel() }
    }
    private func add() {
        guard addTask == nil else { return }
        addTask = Task {
            defer { addTask = nil }
            if await store.add(code), !Task.isCancelled, store.route == .add {
                store.showHoldings = false
                store.route = .home
            }
        }
    }
}

struct StockEditor: View {
    @ObservedObject var store: AppStore
    let item: WatchItem
    @ViewState private var alerts: Bool
    @ViewState private var alias: String
    @ViewState private var shares: String
    @ViewState private var cost: String
    @ViewState private var pin: Bool
    @ViewState private var upEnabled: Bool
    @ViewState private var downEnabled: Bool
    @ViewState private var up: String
    @ViewState private var down: String
    @ViewState private var delivery: AlertDelivery
    @ViewState private var saving = false
    @ViewState private var saveTask: Task<Void, Never>?
    @ViewState private var confirmRemoval = false

    init(store: AppStore, item: WatchItem, initialAlerts: Bool) {
        self.store = store; self.item = item
        _alerts = ViewState(initialValue: initialAlerts)
        _alias = ViewState(initialValue: store.state.aliases[item.id] ?? "")
        _shares = ViewState(initialValue: String(item.holding.quantity))
        _cost = ViewState(initialValue: UI.input(item.holding.averageCost))
        _pin = ViewState(initialValue: item.id == (store.state.pinnedSymbol ?? store.state.items.first?.id))
        _upEnabled = ViewState(initialValue: item.rule.upEnabled)
        _downEnabled = ViewState(initialValue: item.rule.downEnabled)
        _up = ViewState(initialValue: UI.input(item.rule.upThreshold))
        _down = ViewState(initialValue: UI.input(item.rule.downThreshold))
        _delivery = ViewState(initialValue: item.rule.delivery)
    }
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store, title: store.displayName(item),
                        subtitle: store.revealed ? item.symbol.marketName + " " + item.symbol.code : "", showPrivacy: true)
            Picker("股票设置", selection: $alerts) {
                Text("持仓").tag(false); Text("提醒").tag(true)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.top, 10).disabled(saving)
            VStack(alignment: .leading, spacing: 10) {
                if alerts { alertForm } else { holdingForm }
                HStack(spacing: 7) {
                    if !alerts { Button("移出") { confirmRemoval = true }.buttonStyle(.plain).disabled(!store.storageHealthy) }
                    Spacer(minLength: 0)
                    if saving { ProgressView().controlSize(.mini) }
                    Button("取消") { store.route = .home }
                    Button("保存") { save() }.disabled(saving || !store.storageHealthy)
                }.padding(.top, 2)
            }.font(.system(size: 11)).controlSize(.small).padding(12)
        }
        .confirmationDialog("移出 \(store.displayName(item))？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("移出并删除本地持仓", role: .destructive) { store.remove(item.id) }
            Button("取消", role: .cancel) {}
        } message: { Text("本地持仓与提醒设置将一并删除，不影响券商账户。") }
        .onDisappear { saveTask?.cancel() }
    }
    private var holdingForm: some View {
        Group {
            entry("代号", value: $alias, numeric: false)
            if store.revealed {
                entry("持仓股数", value: $shares)
                entry("平均成本", value: $cost)
            } else {
                HStack {
                    Text("持仓与成本").foregroundColor(.secondary)
                    Spacer()
                    Text("••••").accessibilityLabel("已隐藏")
                }
                Button("显示持仓以编辑") { store.revealed = true }
            }
            Toggle("设为状态栏选中项", isOn: $pin).toggleStyle(.checkbox)
            DisclosureGroup("计算说明") {
                Text("当日估算＝每股涨跌 × 当前股数。\n浮动盈亏＝（现价 − 平均成本）× 当前股数。\n股数填 0 清空持仓；不计日内交易、卖出收益或分红。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
        }
    }
    private var alertForm: some View {
        Group {
            threshold("上涨达到", enabled: $upEnabled, value: $up)
            threshold("下跌达到", enabled: $downEnabled, value: $down)
            Picker("提醒方式", selection: $delivery) {
                Text("静默小点").tag(AlertDelivery.silent)
                Text("系统通知").tag(AlertDelivery.system)
            }
            Text(delivery == .silent ? "只亮小点，无横幅、无声音。" : "需系统通知权限；通知使用代号，不含金额。")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("触发规则") {
                Text("每条规则每天一次。仅在应用运行、交易时段内且当日行情有效时判断。休眠、休市、旧行情不提醒。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
        }
    }
    private func entry(_ title: String, value: Binding<String>, numeric: Bool = true) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.secondary)
            Spacer(minLength: 4)
            TextField(numeric ? "0" : "A01", text: value)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .monospacedDigit().frame(width: 142).accessibilityLabel(title)
        }
    }
    private func threshold(_ title: String, enabled: Binding<Bool>, value: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Toggle(title, isOn: enabled).toggleStyle(.checkbox)
            Spacer(minLength: 0)
            TextField("3", text: value).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).monospacedDigit().frame(width: 65)
                .disabled(!enabled.wrappedValue).accessibilityLabel(title + "百分比")
            Text("%").foregroundColor(.secondary)
        }
    }
    private func save() {
        guard !saving else { return }
        store.error = nil
        if alerts {
            saving = true
            let sourceRoute = store.route
            saveTask = Task {
                if await store.saveRule(id: item.id, upEnabled: upEnabled, downEnabled: downEnabled, up: up, down: down, delivery: delivery),
                   !Task.isCancelled, store.route == sourceRoute { store.route = .home }
                saving = false
            }
        } else if store.saveHolding(id: item.id, quantity: shares, cost: cost, pin: pin, alias: alias) { store.route = .home }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var testing = false
    @ViewState private var testTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store, title: "偏好", subtitle: "")
            VStack(alignment: .leading, spacing: 10) {
                Picker("状态栏", selection: Binding(get: { store.state.menuMode == .stock ? MenuMode.stock : .icon }, set: { store.saveSettings(mode: $0) })) {
                    Text("仅图标").tag(MenuMode.icon)
                    Text("仅涨跌幅").tag(MenuMode.stock)
                }.disabled(!store.storageHealthy)
                Text("名称默认代号，金额默认隐藏。\n收起后恢复隐藏；按 Esc 可立即收起。")
                    .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                ShortcutSettingsView(store: store)
                RefreshSettingsView(store: store, expanded: expansion(.refresh))
                HStack {
                    Button("测试小点") { store.previewDot = true; store.message = "静默测试：状态栏已亮小点，没有发送系统通知。" }
                    Button("查看提醒") { store.route = .inbox }
                    Spacer(minLength: 0)
                }
                Divider()
                DisclosureGroup("系统通知 · " + permissionText, isExpanded: expansion(.notifications)) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("仅对主动选择系统通知的股票发送。专注模式可能影响横幅。")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("测试通知") { testing = true; testTask = Task { await store.testNotification(); testing = false } }.disabled(testing)
                            Button("通知设置") { store.openNotificationSettings() }
                        }
                    }.font(.system(size: 10)).padding(.top, 6)
                }
                UpdateSettingsView(checker: store.updateChecker, expanded: expansion(.updates))
                DisclosureGroup("数据与说明", isExpanded: expansion(.data)) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("收起面板不影响交易时段内的提醒监测；休眠或退出后停止监测。持仓与行情缓存仅保存在本机，行情可能延迟，以券商数据为准。")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("查看数据文件") { store.revealData() }
                    }.font(.system(size: 10)).padding(.top, 6)
                }
                HStack {
                    Button("刷新") { Task { await store.refresh() } }.disabled(store.isRefreshing || !TradingSchedule.isOpen(store.now))
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }
                }
            }.font(.system(size: 11)).controlSize(.small).padding(12)
        }.task { await store.updatePermission() }.onDisappear { testTask?.cancel() }
    }
    private var permissionText: String {
        switch store.notificationStatus {
        case .authorized, .provisional: return "已允许"
        case .denied: return "未允许"
        default: return "未申请"
        }
    }
    private func expansion(_ section: SettingsSection) -> Binding<Bool> {
        Binding(get: { store.expandedSettings.contains(section) }, set: { expanded in
            if expanded { store.expandedSettings.insert(section) }
            else { store.expandedSettings.remove(section) }
        })
    }
}

struct RefreshSettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var interval = ""
    @Binding private var isExpanded: Bool
    init(store: AppStore, expanded: Binding<Bool>) {
        self.store = store
        _isExpanded = expanded
    }
    var body: some View {
        DisclosureGroup("刷新 · \(store.state.refreshIntervalSeconds) 秒", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    TextField("5–300", text: $interval).frame(width: 58)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("刷新间隔秒数")
                        .onSubmit { _ = store.saveRefreshInterval(interval) }
                    Text("秒")
                    Spacer(minLength: 0)
                    Button("保存") { _ = store.saveRefreshInterval(interval) }
                        .disabled(!store.storageHealthy)
                }
                Text(store.refreshDescription)
                Text("5–300 秒；间隔越长，提醒可能越晚。午休、周末和节假日不刷新；添加股票时仍会查询验证代码。")
                Text("内置 2026 年交易日历，超出范围会暂停并提示更新。")
            }.font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }.onAppear { interval = String(store.state.refreshIntervalSeconds) }
    }
}
