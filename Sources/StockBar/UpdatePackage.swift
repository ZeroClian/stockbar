import Foundation
import CryptoKit

struct UpdatePackage: Equatable, Sendable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let digest: String?
    }
    let version: String
    let url: URL
    let sha256: String
    let size: Int64
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    static func select(assets: [Asset], tag: String, version: String) -> Self? {
        let name = "Tickfin-\(version)-\(architecture).zip"
        let matches = assets.filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first, asset.size > 0, asset.size <= 100_000_000,
              let digest = asset.digest, digest.range(of: #"^sha256:[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else { return nil }
        let url = URL(string: "https://github.com/ZeroClian/stockbar/releases/download/")!
            .appendingPathComponent(tag).appendingPathComponent(name)
        return Self(version: version, url: url, sha256: String(digest.dropFirst(7)).lowercased(), size: asset.size)
    }
    func verify(_ file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == size else { throw UpdateFailure.invalidPackage }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw UpdateFailure.invalidPackage }
    }
}

enum UpdateFailure: LocalizedError {
    case invalidPackage, invalidLocation, notWritable, download, invalidArchive, incompatible, helper, launch
    var errorDescription: String? {
        switch self {
        case .invalidPackage: return "更新包校验失败，原应用未更改，请重新下载。"
        case .invalidLocation: return "请先将 Tickfin.app 放入应用程序文件夹，再进行应用内更新。"
        case .notWritable: return "当前安装位置不可写，请使用有权限的账户安装到应用程序文件夹。"
        case .download: return "更新包下载失败，请检查网络后重试。"
        case .invalidArchive: return "更新包内容无效，原应用未更改。"
        case .incompatible: return "更新包的版本、签名或芯片架构不匹配，原应用未更改。"
        case .helper: return "无法启动更新程序，原应用仍在运行。"
        case .launch: return "新版未能正常启动，已尝试恢复旧应用。"
        }
    }
}

enum UpdateTools {
    @discardableResult static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.incompatible }
        return String(decoding: data, as: UTF8.self)
    }
    static func validateArchive(names: String, details: String) throws {
        let files = names.split(whereSeparator: \.isNewline).map(String.init)
        guard !files.isEmpty, files.count <= 5000,
              files.contains("Tickfin.app/Contents/Info.plist"),
              files.allSatisfy({ name in
                  (name.hasPrefix("Tickfin.app/") || name.hasPrefix("__MACOSX/")) &&
                  !name.components(separatedBy: "/").contains("..") && !name.contains("\\")
              }), !details.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("l") }) else { throw UpdateFailure.invalidArchive }
        let regex = try NSRegularExpression(pattern: #"([0-9]+) bytes uncompressed"#)
        let text = details as NSString
        guard let match = regex.firstMatch(in: details, range: NSRange(location: 0, length: text.length)),
              let size = Int64(text.substring(with: match.range(at: 1))), size > 0, size < 250_000_000 else { throw UpdateFailure.invalidArchive }
    }
    static func validateApp(_ app: URL, version: String) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "local.stockbar.app",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "StockBar" else { throw UpdateFailure.incompatible }
        if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
            let current = ProcessInfo.processInfo.operatingSystemVersion
            let value = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
            guard value.compare(minimum, options: .numeric) != .orderedAscending else { throw UpdateFailure.incompatible }
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let architectures = try run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/StockBar").path])
        guard architectures.split(whereSeparator: \.isWhitespace).contains(Substring(UpdatePackage.architecture)) else { throw UpdateFailure.incompatible }
    }
}
