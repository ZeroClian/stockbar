import AppKit
import Foundation
import Darwin

struct UpdateTransaction: Codable, Sendable {
    let root: URL
    let target: URL
    let version: String
    let parentPID: Int32
    let token: String
    var stagedApp: URL { root.appendingPathComponent("payload/Tickfin.app") }
    var backup: URL { root.appendingPathComponent("previous.app") }
    var planURL: URL { root.appendingPathComponent("plan.json") }
    var ready: URL { root.appendingPathComponent("ready") }
    var acknowledgement: URL { root.appendingPathComponent("started") }
    static var errorFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.stockbar.app/update-error.txt")
    }
    static var installationURLs: [URL] {
        [URL(fileURLWithPath: "/Applications/Tickfin.app"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Tickfin.app")]
    }
    func validate() throws {
        guard Self.installationURLs.contains(where: { $0.path == target.standardizedFileURL.path }),
              root.deletingLastPathComponent().standardizedFileURL.path == target.deletingLastPathComponent().standardizedFileURL.path,
              root.lastPathComponent == ".Tickfin-update-\(token).noindex", UUID(uuidString: token) != nil,
              parentPID > 1,
              (try root.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == false,
              (try target.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == false else { throw UpdateFailure.invalidLocation }
    }

    // File replacement is separated from process handling so rollback uses the same path in tests and production.
    func replaceAndLaunch(launch: (URL) throws -> Void) throws {
        let fm = FileManager.default
        var movedOld = false
        do {
            try fm.moveItem(at: target, to: backup); movedOld = true
            try fm.moveItem(at: stagedApp, to: target)
            try launch(target)
        } catch {
            if movedOld {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: backup, to: target)
            }
            throw error
        }
    }

    static func apply(planURL: URL) throws {
        let plan = try JSONDecoder().decode(Self.self, from: Data(contentsOf: planURL))
        try plan.validate()
        guard plan.planURL.standardizedFileURL.path == planURL.standardizedFileURL.path else { throw UpdateFailure.invalidLocation }
        try UpdateTools.validateApp(plan.stagedApp, version: plan.version)
        try Data(plan.token.utf8).write(to: plan.ready, options: .atomic)
        // Do not replace files until the old process has actually exited.
        for _ in 0..<300 {
            if kill(plan.parentPID, 0) != 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard kill(plan.parentPID, 0) != 0 else {
            try? FileManager.default.removeItem(at: plan.root)
            throw UpdateFailure.helper
        }
        let register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        var launched = false
        do {
            try plan.replaceAndLaunch { target in
                try UpdateTools.run("/usr/bin/open", ["-g", target.path, "--args", "--tickfin-update-ack", plan.planURL.path])
                for _ in 0..<200 {
                    if (try? String(contentsOf: plan.acknowledgement, encoding: .utf8)) == plan.token { return }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                // Stop only the replacement at this exact path before rolling its files back.
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.stockbar.app") where app.bundleURL?.standardizedFileURL.path == target.standardizedFileURL.path {
                    app.terminate()
                    for _ in 0..<30 { if app.isTerminated { break }; Thread.sleep(forTimeInterval: 0.1) }
                    if !app.isTerminated { app.forceTerminate() }
                }
                throw UpdateFailure.launch
            }
            launched = true
            _ = try? UpdateTools.run(register, ["-u", plan.backup.path])
            _ = try? UpdateTools.run(register, ["-f", plan.target.path])
            try? FileManager.default.removeItem(at: errorFile)
            // Includes the downloaded ZIP, extracted payload, old app, helper and handshake files.
            try FileManager.default.removeItem(at: plan.root)
        } catch {
            try? FileManager.default.createDirectory(at: errorFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let hasBackup = FileManager.default.fileExists(atPath: plan.backup.path)
            let message = launched
                ? "新版已启动，但更新文件未能完全清理。请检查安装目录的写入权限。"
                : (hasBackup ? "更新及回滚未完成，旧版备份仍保留在 \(plan.backup.path)。请勿删除该目录。"
                             : "上次更新未完成，已恢复旧版。请重新检查更新。")
            try? Data(message.utf8).write(to: errorFile, options: .atomic)
            // Never discard a remaining backup if rollback itself failed.
            if !hasBackup { try? FileManager.default.removeItem(at: plan.root) }
            if !launched { _ = try? UpdateTools.run("/usr/bin/open", ["-g", plan.target.path]) }
            throw error
        }
    }

    static func acknowledgeLaunch(arguments: [String], bundle: Bundle = .main) {
        guard let index = arguments.firstIndex(of: "--tickfin-update-ack"), index + 1 < arguments.count,
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])),
              let plan = try? JSONDecoder().decode(Self.self, from: data),
              (try? plan.validate()) != nil,
              bundle.bundleURL.standardizedFileURL.path == plan.target.standardizedFileURL.path,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == plan.version else { return }
        try? Data(plan.token.utf8).write(to: plan.acknowledgement, options: .atomic)
    }
}
