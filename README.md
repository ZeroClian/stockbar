# Tickfin

<img src="Resources/app-icon-1024.png" width="128" alt="Tickfin：鱼形与红绿 K 线图标">

[![CI](https://github.com/ZeroClian/stockbar/actions/workflows/ci.yml/badge.svg)](https://github.com/ZeroClian/stockbar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ZeroClian/stockbar)](https://github.com/ZeroClian/stockbar/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

一个低调的原生 macOS A 股状态栏工具。看涨跌、记持仓、设提醒，不需要打开行情大窗口。

**[下载安装](https://github.com/ZeroClian/stockbar/releases/latest) · [安装指南](docs/INSTALL.md) · [更新日志](CHANGELOG.md) · [反馈问题](https://github.com/ZeroClian/stockbar/issues)**

1.2.0 更名为 **Tickfin**（Ticker + Fin），采用鱼形与红绿 K 线图标。新增全局快捷键、自定义刷新间隔、休市暂停、面板收起后后台监测、自选排序、快速切换关注股票，以及手动检查新版。[查看 v1.2.0 更新说明](docs/releases/v1.2.0.md)。 [查看设置预览](docs/screenshots/shortcut-settings.png)

## 界面

<table><tr><th>自选速览</th><th>默认隐藏持仓</th><th>主动显示持仓 · 深色</th></tr><tr>
<td><img src="docs/screenshots/watchlist.png" width="280" alt="以代号显示的自选涨跌"></td>
<td><img src="docs/screenshots/holdings-hidden.png" width="280" alt="默认遮罩持仓金额"></td>
<td><img src="docs/screenshots/holdings-dark.png" width="280" alt="点击眼睛后显示的持仓盈亏"></td>
</tr></table>

图片由实际 SwiftUI 视图渲染，使用示例数据，不代表当前行情。

## 功能

- **280pt 小面板**：单色数值，正负号区分涨跌，无分时图；默认状态栏仅显示单色鱼形 K 线标记。
- **沪深北 A 股**：输入六位代码添加，包含创业板 `300750` / `301269`、科创板 `688981`。
- **隐私显示**：稳定可编辑代号；名称、股数、成本及持仓盈亏默认隐藏，点击眼睛显示，收起后复位。
- **持仓盈亏**：录入当前股数和平均成本，查看逐只及合计的当日估算、浮动盈亏。
- **涨跌幅提醒**：默认静默小点，不申请通知权限、无横幅、无声音；每只股票可主动选择系统通知。
- **本地保存**：不需要账号，不接入券商，不上传持仓；支持本地行情缓存。
- **交易时段刷新**：5–300 秒自定义间隔，默认 15 秒；休市暂停，开市恢复，关闭面板不停止提醒。

不提供交易下单、名称搜索、自动更新或开机启动设置。仅供个人查看，行情可能延迟或中断，请以券商实际数据为准。

## 安装与开始使用

当前提供 **Apple Silicon / arm64** 的 DMG 和 ZIP。部署目标 macOS 13+，已在开发机验证；macOS 13 与 Intel 尚未实机验证，不提供 Intel 安装包。

从 v1.1.0「自选股」升级时，先退出并移走旧应用副本，再安装 Tickfin。原有持仓与设置保留，无需搬迁数据。

1. 从 [最新 Release](https://github.com/ZeroClian/stockbar/releases/latest) 下载 `Tickfin-1.2.0-arm64.dmg`。
2. 打开磁盘映像，将「Tickfin」拖入 `Applications`，弹出映像，再从应用程序打开。
3. 点击菜单栏的 **鱼形 K 线标记**。应用没有 Dock 图标，默认不会自动展开。
4. 点底部 `＋` 添加股票，点股票行编辑，点眼睛显示真实名称与持仓。
5. 在该股票的「提醒」页设置阈值；铃铛查看未读提醒，偏好页可测试小点。

当前是本地 **ad-hoc 签名，未做 Apple Developer ID 签名或公证**。首次打开可能被 Gatekeeper 阻止，请按 [安装指南](docs/INSTALL.md)核对来源后操作；不要全局关闭系统安全检查。

## 提醒规则

上涨达到正阈值、下跌达到负阈值即可触发，不要求刚刚穿越阈值。相同股票、方向、阈值每天一次，重启保留记录；改阈值视为新规则。静默提醒将未读与去重记录一起保存，标记已读不会重触发；下一交易日的新提醒会清理以前的未读。

1.2.0 在上海时区交易日 09:30–11:30、13:00–15:00 内刷新（不含收盘端点），且报价为当日、不超过 180 秒的新行情时判断。**关闭面板仍持续监测，应用必须保持运行，电脑不能休眠。** 提醒按刷新间隔采样，可能错过两次采样之间短暂触达阈值的情况。

午休、收盘、周末和内置节假日停止自动及手动行情刷新，开市自动恢复；休市启动只读取上次行情缓存，无缓存时等待开市。手动添加股票时仍会查询接口验证代码，版本检查由用户单独触发。休眠、退出、旧行情、更新失败不触发提醒。

内置日历依据[上交所 2026 年休市公告](https://www.sse.com.cn/disclosure/announcement/general/c/c_20251222_10802507.shtml)，覆盖 2026 年，周末调休上班也不开市；不包含临时停市。超出已覆盖年份会暂停行情监测并显示“日历需更新”，需安装包含新年度日历的版本。旧版 v1.1.0 采用固定 15 秒轮询和新鲜行情过滤，不含该调度策略。

主动选择系统通知后，通知使用代号、无金额、无声音；横幅受通知权限和专注模式影响。系统通知提交成功后才保存去重记录，通知系统与本机文件之间不是跨系统原子事务。

## 操作入口（1.2.0）

- **全局快捷键**：偏好 → 全局快捷键 → 点击设置，按组合键并松开后保存。默认未设置；支持至少两个修饰键（包含 ⌃ 或 ⌘）加字母、数字或空格，例如 ⌃⌥空格。
- **刷新间隔**：偏好 → 刷新 → 输入 5–300 秒整数 → 保存。
- **自选排序**：主页右上角上下箭头 → 点每行上移／下移，即时保存；持仓列表沿用自选顺序，代号不变。
- **快速切换状态栏股票**：主页右上角图钉 → 选择代号。保持原状态栏显示模式；如需看涨跌幅，到偏好将“仅图标”改为“仅涨跌幅”。
- **检查新版**：偏好 → 版本与更新 → 检查更新 → 下载新版。只打开本项目 GitHub Release 页面，下载与替换由用户手动完成，不自动安装或重启。

## 计算口径

| 项目 | 计算方式 |
| --- | --- |
| 每股涨跌额 | 现价 − 昨收价 |
| 当日估算盈亏 | 每股涨跌额 × 当前持仓股数 |
| 浮动盈亏 | （现价 − 平均成本）× 当前持仓股数 |

平均成本可填写券商含费成本；不追踪日内交易、已卖出收益、分红或现金。缺少部分持仓行情时不展示不完整合计；旧行情会标记。金额使用 `Decimal` 计算。

## 数据与隐私

数据位于 `~/Library/Application Support/StockBar/state.json`，包含自选、代号、持仓、提醒及去重记录；本地文件未加密，界面遮罩不等于磁盘加密。应用将最近行情保存在同目录的 `quotes-cache.json`，缓存仅供展示，不触发提醒。更名后沿用 `StockBar` 数据目录，已有持仓和设置无需迁移。

行情通过 HTTPS 请求腾讯公开接口 `qt.gtimg.cn`，发送证券代码，不发送持仓数量或成本。服务提供方仍可获知网络请求信息。项目与腾讯、券商没有隶属关系，也不承诺接口长期可用。

备份、升级和卸载步骤见 [安装指南](docs/INSTALL.md)。损坏的数据文件不会被静默重置，应用会停止保存与提醒以保护原数据。

## 本地开发

需要 macOS、Swift 6+ 工具链（Xcode 16+ 或相应 Command Line Tools），测试使用 Swift Testing；生产没有第三方 Swift 包依赖。

```bash
git clone https://github.com/ZeroClian/stockbar.git
cd stockbar
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Tickfin.app
```

开发脚本使用 SwiftPM native 构建引擎及项目内缓存，部分工具链会提示该引擎弃用；测试框架可能产生部署版本警告。生产应用不链接测试框架。

```bash
# 生成 DMG、ZIP、SHA-256 清单；默认会先构建
bash scripts/package-release.sh

# 隔离数据目录，避免影响日常持仓
open -n dist/Tickfin.app --args --data-dir /tmp/stockbar-dev --show-panel

# 只读真实行情检查，不读写持仓、不申请通知权限
dist/Tickfin.app/Contents/MacOS/StockBar --check-market

# 重建原创图标资源（需要 macOS AppKit）
swift scripts/make-icon.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

# 实际 SwiftUI 离屏预览，使用示例数据
bash scripts/render-preview.sh
```

| 目录 | 内容 |
| --- | --- |
| `Sources/StockCore` | 证券代码、解析、金额与提醒规则、本地状态模型 |
| `Sources/StockBar` | SwiftUI 界面、AppKit 状态栏、行情及通知服务 |
| `Tests` | 核心规则与 AppStore 集成测试 |
| `Resources` | 应用元数据和图标 |
| `scripts` | 构建、测试、预览与安装包脚本 |

[贡献指南](CONTRIBUTING.md) · [验证范围](docs/VALIDATION.md) · [版本发布流程](docs/RELEASING.md) · [安全反馈](SECURITY.md)

## 开源与致谢

项目源码按 [MIT 许可证](LICENSE)开放。第三方服务、商标及系统资源的权利不因本许可证转移。

交互方向参考 [Fishing Funds](https://github.com/1zilc/fishing-funds)，本项目独立实现精简需求，未复制其源码。
