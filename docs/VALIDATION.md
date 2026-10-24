# 验证范围

## v1.1.0

- 46 项 Swift Testing 测试在开发机通过，覆盖核心解析、迁移、Decimal 计算、提醒去重、静默原子保存、失败保护及异步操作失效。
- 真实 SwiftUI 离屏渲染 14 个状态，共用 host 验证切页、高度、持仓隐藏/显示/再隐藏、固定提示条。三行自选为 280×186pt；持仓为 280×238pt。
- release 编译、Info.plist、ad-hoc 严格签名与 ZIP 校验通过。发布打包新增 DMG 完整性校验及 SHA-256 清单，安装包生成不修改用户数据。
- 最终应用只读诊断曾解析沪深主板、300750、301269、688981、920002 的真实接口响应；返回的是收盘数据，不能视为交易中实时保证。公开 fixtures 仅含行情，不含账户数据。
- 旧应用替换后进程启动、原有持仓与阈值保持已核对。

未完成完整桌面自动化点击、真实系统横幅、交易时段长时间提醒、macOS 13 与 Intel 实机验收。离屏图片、替身通知测试不能替代这些实测。所有预览使用示例持仓。

## 复现

```bash
bash scripts/test.sh
bash scripts/build-app.sh
bash scripts/render-preview.sh
bash scripts/package-release.sh --skip-build
```

CI 在 macOS runner 上执行测试、构建和打包，不读取个人持仓、不发送系统通知、不把网络行情作为必须成功的测试依赖。实际状态见仓库 Actions；仅当对应提交运行成功才说明该版本 CI 通过。
