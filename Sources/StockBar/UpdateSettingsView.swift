import SwiftUI
import AppKit

struct UpdateSettingsView: View {
    @ObservedObject var checker: UpdateChecker
    @ObservedObject private var updater: AppUpdater
    @Binding private var isExpanded: Bool
    @Environment(\.openURL) private var openURL

    init(checker: UpdateChecker, expanded: Binding<Bool>) {
        self.checker = checker
        self.updater = checker.updater
        _isExpanded = expanded
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                Text(statusText)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("版本检查状态：" + statusText)
                HStack(spacing: 8) {
                    Button(checker.state == .checking ? "检查中…" : "检查更新") {
                        Task { await checker.check() }
                    }
                    .disabled(checker.state == .checking || updater.isUpdating)
                    if case .available(let release) = checker.state {
                        if let package = release.package {
                            Button(updater.isUpdating ? "更新中…" : "立即更新") {
                                Task { await updater.install(package) }
                            }.disabled(updater.isUpdating)
                                .help("下载并校验新版，替换当前应用后自动重启")
                        } else {
                            Button("下载新版 ↗") { openURL(release.url) }
                                .help("此发布版缺少适配的更新包或校验信息，请从发布页安装")
                        }
                    } else {
                        Button("发布页 ↗") { openURL(UpdateChecker.releasesURL) }
                            .help("打开 Tickfin 的 GitHub 发布页")
                    }
                }.controlSize(.small)
                if let message = updater.message {
                    Text(message).font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("点击更新后自动下载、校验、替换并重启；完成后清理更新包和旧版，保留持仓与设置。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("显示当前应用位置") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .controlSize(.small)
            }.padding(.top, 5).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 5) {
                Text("版本与更新")
                Spacer(minLength: 0)
                Text(checker.currentVersion).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }.font(.system(size: 11))
        }
    }

    private var statusText: String {
        switch checker.state {
        case .idle: return "手动检查 GitHub 上的公开正式版。"
        case .checking: return "正在检查公开正式版…"
        case .latest(let version): return "已是最新正式版（\(version)）。"
        case .developmentVersion(let latest): return "当前版本高于公开正式版（\(latest)），无需降级。"
        case .available(let release): return "发现新版本 \(release.version)。"
        case .failed(let error): return error.message
        }
    }
}
