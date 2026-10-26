import Foundation
import CryptoKit
import Testing
@testable import StockBar

@Test func updatePackageRequiresMatchingArchitectureSizeAndDigest() throws {
    let name = "Tickfin-1.3.0-\(UpdatePackage.architecture).zip"
    let digest = "sha256:" + String(repeating: "a", count: 64)
    let asset = UpdatePackage.Asset(name: name, size: 123, digest: digest)
    let package = try #require(UpdatePackage.select(assets: [asset], tag: "v1.3.0", version: "1.3.0"))
    #expect(package.url.absoluteString == "https://github.com/ZeroClian/stockbar/releases/download/v1.3.0/" + name)
    for invalid in [UpdatePackage.Asset(name: "other.zip", size: 123, digest: digest),
                    .init(name: name, size: 123, digest: nil), .init(name: name, size: 0, digest: digest),
                    .init(name: name, size: 200_000_000, digest: digest), .init(name: name, size: 123, digest: "sha256:wrong")] {
        #expect(UpdatePackage.select(assets: [invalid], tag: "v1.3.0", version: "1.3.0") == nil)
    }
    #expect(UpdatePackage.select(assets: [asset, asset], tag: "v1.3.0", version: "1.3.0") == nil)
}

@Test func downloadedPackageRejectsTamperingAndTruncation() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    let data = Data("a verified package".utf8)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let package = UpdatePackage(version: "1.3.0", url: URL(string: "https://github.com")!, sha256: digest, size: Int64(data.count))
    try data.write(to: path); try package.verify(path)
    try Data(repeating: 0, count: data.count).write(to: path)
    #expect(throws: (any Error).self) { try package.verify(path) }
    try Data().write(to: path)
    #expect(throws: (any Error).self) { try package.verify(path) }
}

@Test func updateArchiveRejectsTraversalSymlinksAndOversizePayloads() throws {
    let valid = "Tickfin.app/\nTickfin.app/Contents/Info.plist\nTickfin.app/Contents/MacOS/StockBar\n"
    try UpdateTools.validateArchive(names: valid, details: "3 files, 123 bytes uncompressed, 100 bytes compressed")
    for names in [valid + "../outside\n", valid + "Tickfin.app/../../outside\n", valid + "/absolute\n", "Other.app/Contents/Info.plist"] {
        #expect(throws: (any Error).self) { try UpdateTools.validateArchive(names: names, details: "3 files, 123 bytes uncompressed") }
    }
    for details in ["lrwxrwxrwx link\n3 files, 123 bytes uncompressed", "3 files, 999999999 bytes uncompressed", "invalid"] {
        #expect(throws: (any Error).self) { try UpdateTools.validateArchive(names: valid, details: details) }
    }
}

@Test(arguments: [false, true]) func replacementRestoresOldAppIfLaunchFails(fail: Bool) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let target = root.appendingPathComponent("Tickfin.app")
    let plan = UpdateTransaction(root: root.appendingPathComponent("stage"), target: target, version: "1.3.0", parentPID: 123, token: UUID().uuidString)
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    try fm.createDirectory(at: plan.stagedApp, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: target.appendingPathComponent("version"))
    try Data("new".utf8).write(to: plan.stagedApp.appendingPathComponent("version"))
    do {
        try plan.replaceAndLaunch { url in
            #expect(try String(contentsOf: url.appendingPathComponent("version")) == "new")
            if fail { throw UpdateFailure.launch }
        }
        #expect(!fail)
    } catch { #expect(fail) }
    #expect(try String(contentsOf: target.appendingPathComponent("version")) == (fail ? "old" : "new"))
    #expect(fm.fileExists(atPath: plan.backup.path) == !fail)
}

@Test func singleInstanceLockIsReleasedWhenOwnerExits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var first: AppInstanceLock? = AppInstanceLock()
    let second = AppInstanceLock()
    #expect(try first!.acquire(directory: directory))
    #expect(try !second.acquire(directory: directory))
    first = nil
    #expect(try second.acquire(directory: directory))
}

@MainActor @Test func releaseCheckerOnlyOffersVerifiedPackageFromFixedRepository() async throws {
    let object: [String: Any] = ["tag_name":"v1.3.0", "draft":false, "prerelease":false,
        "assets":[["name":"Tickfin-1.3.0-\(UpdatePackage.architecture).zip", "size":123,
                   "digest":"sha256:" + String(repeating:"b", count:64), "browser_download_url":"https://evil.example/package.zip"]]]
    let data = try JSONSerialization.data(withJSONObject: object)
    let checker = UpdateChecker(currentVersion: "1.2.1") { request in
        (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await checker.check()
    guard case .available(let release) = checker.state else { Issue.record("Missing update"); return }
    #expect(release.package?.url.host == "github.com")
    #expect(release.package?.url.path.hasPrefix("/ZeroClian/stockbar/releases/download/v1.3.0/") == true)
}
