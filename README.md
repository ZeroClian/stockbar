# StockBar · 自选股

[![CI](https://github.com/ZeroClian/stockbar/actions/workflows/ci.yml/badge.svg)](https://github.com/ZeroClian/stockbar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ZeroClian/stockbar)](https://github.com/ZeroClian/stockbar/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

一个低调的原生 macOS A 股状态栏工具。看涨跌、记持仓、设提醒，不需要打开行情大窗口。

**[下载安装](https://github.com/ZeroClian/stockbar/releases/latest) · [安装指南](docs/INSTALL.md) · [更新日志](CHANGELOG.md) · [反馈问题](https://github.com/ZeroClian/stockbar/issues)**

## 界面

<table><tr><th>自选速览</th><th>默认隐藏持仓</th><th>主动显示持仓 · 深色</th></tr><tr>
<td><img src="docs/screenshots/watchlist.png" width="280" alt="以代号显示的自选涨跌"></td>
<td><img src="docs/screenshots/holdings-hidden.png" width="280" alt="默认遮罩持仓金额"></td>
<td><img src="docs/screenshots/holdings-dark.png" width="280" alt="点击眼睛后显示的持仓盈亏"></td>
</tr></table>

图片由实际 SwiftUI 视图渲染，使用示例数据，不代表当前行情。

## 功能

- **280pt 小面板**：单色数值，正负号区分涨跌，无分时图；默认状态栏仅显示省略号。
- **沪深北 A 股**：输入六位代码添加，包含创业板 `300750` / `301269`、科创板 `688981`。
- **隐私显示**：稳定可编辑代号；名称、股数、成本及持仓盈亏默认隐藏，点击眼睛显示，收起后复位。
- **持仓盈亏**：录入当前股数和平均成本，查看逐只及合计的当日估算、浮动盈亏。
- **涨跌幅提醒**：默认静默小点，不申请通知权限、无横幅、无声音；每只股票可主动选择系统通知。
- **本地保存**：不需要账号，不接入券商，不上传持仓；每 15 秒刷新行情。

不提供交易下单、名称搜索、自动更新或开机启动设置。仅供个人查看，行情可能延迟或中断，请以券商实际数据为准。

## 安装与开始使用

当前提供 **Apple Silicon / arm64** 的 DMG 和 ZIP。部署目标 macOS 13+，已在开发机验证；macOS 13 与 Intel 尚未实机验证，不提供 Intel 安装包。

1. 从 [最新 Release](https://github.com/ZeroClian/stockbar/releases/latest) 下载 `StockBar-版本-arm64.dmg`。
2. 打开磁盘映像，将「自选股」拖入 `Applications`，弹出映像，再从应用程序打开。
3. 点击菜单栏的 **省略号**。应用没有 Dock 图标，默认不会自动展开。
4. 点底部 `＋` 添加股票，点股票行编辑，点眼睛显示真实名称与持仓。
5. 在该股票的「提醒」页设置阈值；铃铛查看未读提醒，偏好页可测试小点。

当前是本地 **ad-hoc 签名，未做 Apple Developer ID 签名或公证**。首次打开可能被 Gatekeeper 阻止，请按 [安装指南](docs/INSTALL.md)核对来源后操作；不要全局关闭系统安全检查。

## 提醒规则

上涨达到正阈值、下跌达到负阈值即可触发，不要求刚刚穿越阈值。相同股票、方向、阈值每天一次，重启保留记录；改阈值视为新规则。静默提醒将未读与去重记录一起保存，标记已读不会重触发；下一交易日的新提醒会清理以前的未读。

仅在上海时区工作日 09:30–11:30、13:00–15:00，且报价为当日、不超过 180 秒的新行情时判断。休眠、退出、旧行情、更新失败不触发。没有独立节假日日历，依赖当日新行情过滤休市数据。

主动选择系统通知后，通知使用代号、无金额、无声音；横幅受通知权限和专注模式影响。系统通知提交成功后才保存去重记录，通知系统与本机文件之间不是跨系统原子事务。

## 计算口径

| 项目 | 计算方式 |
| --- | --- |
| 每股涨跌额 | 现价 − 昨收价 |
| 当日估算盈亏 | 每股涨跌额 × 当前持仓股数 |
| 浮动盈亏 | （现价 − 平均成本）× 当前持仓股数 |

平均成本可填写券商含费成本；不追踪日内交易、已卖出收益、分红或现金。缺少部分持仓行情时不展示不完整合计；旧行情会标记。金额使用 `Decimal` 计算。

## 数据与隐私

数据位于 `~/Library/Application Support/StockBar/state.json`，包含自选、代号、持仓、提醒及去重记录；本地文件未加密，界面遮罩不等于磁盘加密。行情只保留在内存。

行情通过 HTTPS 请求腾讯公开接口 `qt.gtimg.cn`，发送证券代码，不发送持仓数量或成本。服务提供方仍可获知网络请求信息。项目与腾讯、券商没有隶属关系，也不承诺接口长期可用。

备份、升级和卸载步骤见 [安装指南](docs/INSTALL.md)。损坏的数据文件不会被静默重置，应用会停止保存与提醒以保护原数据。

## 本地开发

需要 macOS、Swift 6+ 工具链（Xcode 16+ 或相应 Command Line Tools），测试使用 Swift Testing；生产没有第三方 Swift 包依赖。

```bash
git clone https://github.com/ZeroClian/stockbar.git
cd stockbar
bash scripts/test.sh
bash scripts/build-app.sh
open dist/自选股.app
```

开发脚本使用 SwiftPM native 构建引擎及项目内缓存，部分工具链会提示该引擎弃用；测试框架可能产生部署版本警告。生产应用不链接测试框架。

```bash
# 生成 DMG、ZIP、SHA-256 清单；默认会先构建
bash scripts/package-release.sh

# 隔离数据目录，避免影响日常持仓
open -n dist/自选股.app --args --data-dir /tmp/stockbar-dev --show-panel

# 只读真实行情检查，不读写持仓、不申请通知权限
dist/自选股.app/Contents/MacOS/StockBar --check-market

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
