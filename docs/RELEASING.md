# 维护者发布流程

1. 更新 Resources/Info.plist 的用户版本和递增 build，更新 CHANGELOG.md 与 docs/releases/ 对应说明。
2. 检查迁移、隐私和兼容性，执行 `bash scripts/test.sh`。UI 有改动时补原生预览与桌面实测。
3. 提交源码并推送 main，等待该提交 CI 通过。不要提交 dist 或用户数据。
4. 在目标 Mac 上运行 `bash scripts/package-release.sh`，它构建并严格验证签名，输出版本化 DMG、ZIP、SHA256SUMS.txt；不自动创建或发布 GitHub Release。
5. 校验 ZIP、DMG，挂载后核对应用版本、架构与 Applications 快捷方式；手动安装并记录真实验证范围。
6. 为已验证提交创建 v<版本> 标签并推送；使用对应 docs/releases/<版本>.md 创建 Release，上传上述三个文件。
7. 下载公开资产，比较 SHA-256，确认远程 main、标签与本地提交一致，确认 Release 为公开状态。

示例（版本需与 Info.plist 一致）：

```bash
git tag -a v1.1.0 -m 'StockBar v1.1.0'
git push origin v1.1.0
gh release create v1.1.0 --verify-tag --title 'StockBar v1.1.0 · 隐身速览' \
  --notes-file docs/releases/v1.1.0.md \
  dist/StockBar-1.1.0-arm64.dmg dist/StockBar-1.1.0-arm64.zip dist/SHA256SUMS.txt
```

当前打包脚本使用 ad-hoc 签名，不包含 Apple 凭证，不执行公证。未来若加入 Developer ID 和公证，应使用受保护的发布环境与密钥存储，并同步更新安装说明；不得把证书密码或私钥提交到仓库。
