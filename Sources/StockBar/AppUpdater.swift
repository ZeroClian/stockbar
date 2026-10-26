import AppKit
import Combine
import Foundation

@MainActor final class AppUpdater: ObservableObject {
    @Published private(set) var isUpdating = false
    @Published private(set) var message: String?
    init() { message = try? String(contentsOf: UpdateTransaction.errorFile, encoding: .utf8) }

    func install(_ package: UpdatePackage) async {
        guard !isUpdating else { return }
        isUpdating = true
        message = "正在下载并校验新版，完成后自动重启…"
        let target = Bundle.main.bundleURL.standardizedFileURL
        let executable = Bundle.main.executableURL
        var prepared: UpdateTransaction?
        do {
            guard UpdateTransaction.installationURLs.contains(where: { $0.path == target.path }), let executable else { throw UpdateFailure.invalidLocation }
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path),
                  FileManager.default.isWritableFile(atPath: target.path) else { throw UpdateFailure.notWritable }
            let plan = try await Task.detached(priority: .utility) {
                try await Self.prepare(package, target: target, executable: executable)
            }.value
            prepared = plan
            message = "校验完成，正在替换并重启…"
            let helper = Process()
            helper.executableURL = plan.root.appendingPathComponent("update-helper")
            helper.arguments = ["--apply-update", plan.planURL.path]
            helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
            try helper.run()
            var ready = false
            for _ in 0..<50 {
                if (try? String(contentsOf: plan.ready, encoding: .utf8)) == plan.token { ready = true; break }
                if !helper.isRunning { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard ready else { if helper.isRunning { helper.terminate() }; throw UpdateFailure.helper }
            NSApp.terminate(nil)
        } catch {
            if let prepared { try? FileManager.default.removeItem(at: prepared.root) }
            message = (error as? UpdateFailure)?.localizedDescription ?? "更新未完成，原应用未更改。请检查网络后重试。"
            isUpdating = false
        }
    }

    nonisolated static func prepare(_ package: UpdatePackage, target: URL, executable: URL) async throws -> UpdateTransaction {
        let fm = FileManager.default, token = UUID().uuidString
        let root = target.deletingLastPathComponent().appendingPathComponent(".Tickfin-update-\(token).noindex", isDirectory: true)
        let plan = UpdateTransaction(root: root, target: target, version: package.version, parentPID: ProcessInfo.processInfo.processIdentifier, token: token)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try plan.validate()
            var request = URLRequest(url: package.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            request.setValue("Tickfin", forHTTPHeaderField: "User-Agent")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (temporary, response) = try await session.download(for: request)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.download }
            try package.verify(temporary)
            let archive = root.appendingPathComponent("package.zip")
            try fm.moveItem(at: temporary, to: archive)
            let names = try UpdateTools.run("/usr/bin/unzip", ["-Z1", archive.path])
            let details = try UpdateTools.run("/usr/bin/unzip", ["-Z", "-l", archive.path])
            try UpdateTools.validateArchive(names: names, details: details)
            try UpdateTools.run("/usr/bin/ditto", ["-x", "-k", archive.path, root.appendingPathComponent("payload").path])
            try UpdateTools.validateApp(plan.stagedApp, version: package.version)
            try fm.copyItem(at: executable, to: root.appendingPathComponent("update-helper"))
            try JSONEncoder().encode(plan).write(to: plan.planURL, options: .atomic)
            return plan
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }
}
