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
    @ViewState private var addingID: String?
    @StateObject private var search: StockSearchModel
    @FocusState private var focused: Bool
    init(store: AppStore, search: StockSearchModel? = nil) {
        self.store = store
        _search = StateObject(wrappedValue: search ?? StockSearchModel())
    }
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store, title: "添加", subtitle: "")
            VStack(alignment: .leading, spacing: 10) {
                TextField("代码 / 拼音简写，如 NDSD", text: $code)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityLabel("股票或 ETF 代码、拼音首字母")
                    .onChange(of: code) { search.updateQuery($0) }
                    .onSubmit { search.updateQuery(code, immediately: true) }
                Text("沪深北 A 股 · 沪深场内 ETF")
                    .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if search.isSearching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("搜索中…").foregroundColor(.secondary)
                    }
                }
                if let message = search.message {
                    Text(message).font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重新搜索") { search.updateQuery(code, immediately: true) }
                }
                if !search.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(search.results) { result in
                            resultRow(result)
                            if result.id != search.results.last?.id { Divider() }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("完成") { store.route = .home }
                }
            }.font(.system(size: 11)).controlSize(.small).padding(12)
        }.onAppear { focused = true }.onDisappear { addTask?.cancel(); search.cancel() }
    }

    private func resultRow(_ result: StockSearchResult) -> some View {
        let added = store.state.items.contains { $0.id == result.id }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name).lineLimit(1).help(result.name)
                Text(result.symbol.marketName + " " + result.symbol.code)
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if addingID == result.id {
                ProgressView().controlSize(.mini).frame(width: 24, height: 28)
            } else {
                Button { add(result) } label: {
                    Image(systemName: added ? "checkmark" : "plus")
                        .font(.system(size: 12)).frame(width: 24, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(added || store.isAdding || !store.storageHealthy)
                    .help(added ? "已添加" : "添加 " + result.name)
                    .accessibilityLabel((added ? "已添加 " : "添加 ") + result.name + " " + result.symbol.code)
            }
        }.padding(.vertical, 6)
    }

    private func add(_ result: StockSearchResult) {
        guard addTask == nil else { return }
        addingID = result.id
        store.error = nil
        addTask = Task {
            defer { addTask = nil; addingID = nil }
            if await store.add(result.id), !Task.isCancelled, store.route == .add {
                store.showHoldings = false
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
    @ViewState private var alertSection: Int
    @ViewState private var priceRule: PriceAlertRule
    @ViewState private var holdingRule: HoldingAlertRule
    @ViewState private var abovePrice: String
    @ViewState private var belowPrice: String
    @ViewState private var profitTarget: String
    @ViewState private var lossTarget: String
    @ViewState private var saving = false
    @ViewState private var saveTask: Task<Void, Never>?
    @ViewState private var confirmRemoval = false
    @ViewState private var confirmClearHolding = false

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
        _priceRule = ViewState(initialValue: item.rule.price)
        _holdingRule = ViewState(initialValue: item.rule.holding)
        _abovePrice = ViewState(initialValue: UI.input(item.rule.price.above))
        _belowPrice = ViewState(initialValue: UI.input(item.rule.price.below))
        _profitTarget = ViewState(initialValue: UI.input(item.rule.holding.profit))
        _lossTarget = ViewState(initialValue: UI.input(item.rule.holding.loss))
        _alertSection = ViewState(initialValue: item.rule.upEnabled || item.rule.downEnabled ? 0 :
            item.rule.price.aboveEnabled || item.rule.price.belowEnabled ? 1 :
            item.rule.holding.profitEnabled || item.rule.holding.lossEnabled ? 2 : 0)
    }
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(store: store, title: store.displayName(item),
                        subtitle: store.revealed ? item.symbol.marketName + " " + item.symbol.code : "", showPrivacy: true)
            priceSummary
            Picker("自选项设置", selection: $alerts) {
                Text("持仓").tag(false); Text("提醒").tag(true)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.top, 10).disabled(saving)
            VStack(alignment: .leading, spacing: alerts ? 8 : 10) {
                if alerts { alertForm } else { holdingForm }
                HStack(spacing: 7) {
                    if !alerts {
                        Button("移出") { confirmRemoval = true }.buttonStyle(.plain).disabled(!store.storageHealthy)
                        Button("清空持仓") { confirmClearHolding = true }
                            .buttonStyle(.plain)
                            .disabled(saving || !store.storageHealthy || !store.state.items.contains { $0.id == item.id && $0.holding != Holding() })
                            .confirmationDialog("清空 \(store.displayName(item)) 的持仓？", isPresented: $confirmClearHolding, titleVisibility: .visible) {
                                Button("清空持仓", role: .destructive) {
                                    if store.clearHolding(item.id) { shares = "0"; cost = "0" }
                                }
                                Button("取消", role: .cancel) {}
                            } message: {
                                Text("仅将此项的数量和成本归零，保留自选、代号及提醒。确认后立即保存，取消编辑不会撤销。")
                            }
                    }
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
    private var priceSummary: some View {
        let quote = store.quotes[item.id]
        return VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 4) {
                priceColumn("当日最高价", value: quote?.dayHigh)
                priceColumn("当前价格", value: quote?.last, prominent: true)
                priceColumn("当日最低价", value: quote?.dayLow)
            }
            Text(store.quoteLabel(item.id))
                .font(.system(size: 9)).foregroundColor(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.padding(.horizontal, 12).padding(.top, 12)
    }
    private func priceColumn(_ title: String, value: Decimal?, prominent: Bool = false) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value.map { UI.number($0, digits: item.symbol.priceFractionDigits) } ?? "—")
                .font(.system(size: prominent ? 18 : 14, weight: prominent ? .medium : .regular))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .frame(height: 22, alignment: .bottom)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value.map { UI.number($0, digits: item.symbol.priceFractionDigits) + " 元" } ?? "暂无行情")
    }
    private var holdingForm: some View {
        Group {
            entry("代号", value: $alias, numeric: false)
            if store.revealed {
                entry(item.symbol.isETF ? "持仓份数" : "持仓股数", value: $shares)
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
                Text(item.symbol.isETF
                     ? "当日估算＝每份涨跌 × 当前份数。\n浮动盈亏＝（现价 − 每份平均成本）× 当前份数。\n份数填 0 清空持仓；不计日内交易、卖出收益或分红。"
                     : "当日估算＝每股涨跌 × 当前股数。\n浮动盈亏＝（现价 − 平均成本）× 当前股数。\n股数填 0 清空持仓；不计日内交易、卖出收益或分红。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
        }
    }
    private var alertForm: some View {
        Group {
            Picker("提醒条件", selection: $alertSection) {
                Text("涨跌幅").tag(0); Text("价格").tag(1); Text("盈亏").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            if alertSection == 0 {
                threshold("上涨达到", enabled: $upEnabled, value: $up)
                threshold("下跌达到", enabled: $downEnabled, value: $down)
            } else if alertSection == 1 {
                threshold("价格涨到", enabled: $priceRule.aboveEnabled, value: $abovePrice, unit: "元")
                threshold("价格跌到", enabled: $priceRule.belowEnabled, value: $belowPrice, unit: "元")
            } else {
                if store.revealed {
                    Picker("浮动盈亏", selection: $holdingRule.unit) {
                        Text("金额（元）").tag(HoldingAlertUnit.amount)
                        Text("比例（%）").tag(HoldingAlertUnit.percent)
                    }.help("按单项持仓浮动盈亏判断，亏损阈值填正数；数量或成本为零时暂停。")
                    threshold("盈利达到", enabled: $holdingRule.profitEnabled, value: $profitTarget, unit: holdingRule.unit == .amount ? "元" : "%")
                    threshold("亏损达到", enabled: $holdingRule.lossEnabled, value: $lossTarget, unit: holdingRule.unit == .amount ? "元" : "%")
                } else {
                    Button("显示盈亏提醒以编辑") { store.revealed = true }
                }
            }
            Text(enabledAlertSummary).font(.system(size: 9)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("提醒方式", selection: $delivery) {
                Text("静默小点").tag(AlertDelivery.silent)
                Text("系统通知").tag(AlertDelivery.system)
            }
            Text(delivery == .silent ? "只亮小点，无横幅、无声音。" : "需系统通知权限；通知使用代号，不含金额。")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("触发规则") {
                Text("每条规则每天一次。达到或越过阈值即满足；保存后已达标会在下一次有效行情提醒。三类条件可同时启用。盈亏按此项持仓的浮动盈亏判断，亏损阈值填正数；数量或成本为零时暂停。收起面板继续监测；休眠、休市、旧行情不提醒。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
        }
    }
    private var enabledAlertSummary: String {
        let flags = [(upEnabled, "涨幅"), (downEnabled, "跌幅"),
                     (priceRule.aboveEnabled, "涨到"), (priceRule.belowEnabled, "跌到"),
                     (holdingRule.profitEnabled, "盈利"), (holdingRule.lossEnabled, "亏损")]
        let labels = flags.filter { $0.0 }.map { $0.1 }
        return labels.isEmpty ? "尚未开启提醒条件" : "已开启：" + labels.joined(separator: "、")
    }
    private func entry(_ title: String, value: Binding<String>, numeric: Bool = true) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.secondary)
            Spacer(minLength: 4)
            TextField(numeric ? "0" : "GZMT", text: value)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .monospacedDigit().frame(width: 142).accessibilityLabel(title)
        }
    }
    private func threshold(_ title: String, enabled: Binding<Bool>, value: Binding<String>, unit: String = "%") -> some View {
        HStack(spacing: 6) {
            Toggle(title, isOn: enabled).toggleStyle(.checkbox)
            Spacer(minLength: 0)
            TextField("3", text: value).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).monospacedDigit().frame(width: 65)
                .disabled(!enabled.wrappedValue).accessibilityLabel(title + "（" + unit + "）")
            Text(unit).foregroundColor(.secondary)
        }
    }
    private func save() {
        guard !saving else { return }
        store.error = nil
        if alerts {
            guard let above = UI.decimal(abovePrice), let below = UI.decimal(belowPrice),
                  let profit = UI.decimal(profitTarget), let loss = UI.decimal(lossTarget),
                  above > 0, below > 0, profit > 0, loss > 0 else {
                store.error = "价格和盈亏阈值需填写大于零的数值，最多四位小数。"; return
            }
            var price = priceRule; price.above = above; price.below = below
            var holding = holdingRule; holding.profit = profit; holding.loss = loss
            saving = true
            let sourceRoute = store.route
            saveTask = Task {
                if await store.saveRule(id: item.id, upEnabled: upEnabled, downEnabled: downEnabled, up: up, down: down, delivery: delivery, price: price, holding: holding),
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
                        Text("仅对主动选择系统通知的自选项发送。专注模式可能影响横幅。")
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
                Text("5–300 秒；间隔越长，提醒可能越晚。午休、周末和节假日不刷新；添加自选时仍会查询验证代码。")
                Text("内置 2026 年交易日历，超出范围会暂停并提示更新。")
            }.font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }.onAppear { interval = String(store.state.refreshIntervalSeconds) }
    }
}
