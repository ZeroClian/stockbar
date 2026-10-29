# 维护者发布流程

1. 更新 Resources/Info.plist 的用户版本和递增 build，更新 CHANGELOG.md 与 docs/releases/ 对应说明。
2. 检查迁移、隐私和兼容性，执行 `bash scripts/test.sh`。UI 有改动时补原生预览与桌面实测。
3. 提交源码并推送 main，等待该提交 CI 通过。不要提交 dist 或用户数据。
4. 在目标 Mac 上运行 `bash scripts/package-release.sh`，它构建并严格验证签名，输出版本化 DMG、ZIP、SHA256SUMS.txt；不自动创建或发布 GitHub Release。
5. 校验 ZIP、DMG，挂载后核对应用版本、架构与 Applications 快捷方式；手动安装并记录真实验证范围。
6. 为已验证提交创建 v<版本> 标签并推送；使用对应 docs/releases/<版本>.md 创建 Release，上传上述三个文件。
7. 下载公开资产，比较 SHA-256，确认远程 main、标签与本地提交一致，确认 Release 为公开状态。

一键更新使用 GitHub API 中 ZIP 资产的 `digest`（`sha256:…`），只识别 `Tickfin-<版本>-<arm64|x86_64>.zip`。发布后须确认 digest 非空且与本地 ZIP 一致；保留签名、Bundle ID 和 `StockBar` 可执行名称。未来更新包应保留应用的启动确认协议，否则更新助手会回滚。更换签名策略时同步验证自动更新。

本地开发安装使用 `TICKFIN_WORK_ROOT=<项目临时目录>/build.noindex bash scripts/install-local.sh`；先退出应用，脚本只替换 `/Applications/Tickfin.app`，并清理构建的临时应用包。不要在每次开发后从不同目录启动 `.app`，否则 Spotlight/启动台会登记多个副本。构建缓存与发布产物不作为安装副本运行。

示例（版本需与 Info.plist 一致）：

```bash
git tag -a v1.2.2 -m 'Tickfin v1.2.2'
git push origin v1.2.2
gh release create v1.2.2 --verify-tag --title 'Tickfin v1.2.2' \
  --notes-file docs/releases/v1.2.2.md \
  dist/Tickfin-1.2.2-arm64.dmg dist/Tickfin-1.2.2-arm64.zip dist/SHA256SUMS.txt
```

当前打包脚本使用 ad-hoc 签名，不包含 Apple 凭证，不执行公证。未来若加入 Developer ID 和公证，应使用受保护的发布环境与密钥存储，并同步更新安装说明；不得把证书密码或私钥提交到仓库。

## CI 执行器与容量故障

日常 push / PR 默认使用 `macos-15-intel`，执行同一套测试、构建和打包，产物按实际架构命名。ARM64 验证可在 Actions → CI → Run workflow 中将 `runner` 选择为 `macos-15`；两种架构的运行不会互相取消。Intel CI 成功不能替代 ARM64 安装包验证，也不自动增加公开 Release 的 Intel 支持声明。

若出现 `The job was not acquired by Runner` 并提示 ARM64 capacity constraints，说明 GitHub 未能分配执行器，测试与构建尚未开始。原失败记录不会因修复或新运行自动变绿；查看最新提交的 CI 结果。`Re-run jobs` 会沿用旧提交的工作流，如需切换执行器请使用最新 main 的 Run workflow。

执行器标签参见 [GitHub 官方文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

## 仓库外构建与打包

以下路径由维护者指定，避免把开发缓存或临时应用登记为多个安装副本；CI 可继续使用脚本默认的 `.build` / `dist`。

```bash
# 将此路径改为本机项目临时目录，勿提交绝对路径或产物
export TICKFIN_WORK_ROOT="/path/to/project-temp/release.noindex"
export TICKFIN_TEST_ROOT="$TICKFIN_WORK_ROOT/tests"
export TICKFIN_BUILD_ROOT="$TICKFIN_WORK_ROOT/build"
export TICKFIN_APP_PATH="$TICKFIN_WORK_ROOT/Tickfin.app"
export TICKFIN_RELEASE_DIR="$TICKFIN_WORK_ROOT/packages"
mkdir -p "$TICKFIN_WORK_ROOT/runtime"
export TMPDIR="$TICKFIN_WORK_ROOT/runtime/"
bash scripts/test.sh
bash scripts/package-release.sh
```

自定义输出目录时，`gh release create` 的三个资产路径也应改为 `$TICKFIN_RELEASE_DIR/...`。打包脚本会清理 DMG 临时组装目录，但保留构建出的应用以便维护者校验；上传并验收后删除临时 `.app` 与回下载副本。不要运行它们，日常只启动固定位置的正式应用。源码不包含构建缓存、发布包或个人数据。
