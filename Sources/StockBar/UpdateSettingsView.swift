import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var checker: UpdateChecker
    @Binding private var isExpanded: Bool
    @Environment(\.openURL) private var openURL

    init(checker: UpdateChecker, expanded: Binding<Bool>) {
        self.checker = checker
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
                    .disabled(checker.state == .checking)
                    if case .available(let release) = checker.state {
                        Button("下载新版 ↗") { openURL(release.url) }
                            .help("打开 GitHub 正式版页面，手动下载和替换应用")
                    } else {
                        Button("发布页 ↗") { openURL(UpdateChecker.releasesURL) }
                            .help("打开 Tickfin 的 GitHub 发布页")
                    }
                }.controlSize(.small)
                Text("仅检查版本；下载后需手动替换应用。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
