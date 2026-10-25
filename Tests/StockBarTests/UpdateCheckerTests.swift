import Foundation
import Testing
@testable import StockBar

private func releaseResponse(tag: String = "v1.10.0", draft: Bool = false, prerelease: Bool = false, status: Int = 200) throws -> (Data, URLResponse) {
    let data = try JSONSerialization.data(withJSONObject: [
        "tag_name": tag, "draft": draft, "prerelease": prerelease,
        "html_url": "https://untrusted.example/download"
    ])
    let response = HTTPURLResponse(url: URL(string: "https://api.github.com/repos/ZeroClian/stockbar/releases/latest")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (data, response)
}

@MainActor @Test func updateComparisonUsesNumericVersionAndTrustedDownloadPage() async throws {
    let fixture = try releaseResponse()
    let checker = UpdateChecker(currentVersion: "1.9.0") { request in
        #expect(request.url?.absoluteString == "https://api.github.com/repos/ZeroClian/stockbar/releases/latest")
        #expect(request.timeoutInterval == 15)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return fixture
    }
    await checker.check()
    guard case .available(let release) = checker.state else { Issue.record("应发现 1.10.0 新版本"); return }
    #expect(release.version == "1.10.0")
    #expect(release.url.absoluteString == "https://github.com/ZeroClian/stockbar/releases/tag/v1.10.0")
}

@MainActor @Test func currentDevelopmentVersionNeverOffersDowngrade() async throws {
    let fixture = try releaseResponse(tag: "v1.1.0")
    let checker = UpdateChecker(currentVersion: "1.2.0", request: { _ in fixture })
    await checker.check()
    #expect(checker.state == .developmentVersion(latest: "1.1.0"))
}

@MainActor @Test func equalVersionIgnoringBuildMetadataIsLatest() async throws {
    let fixture = try releaseResponse(tag: "v1.2.0")
    let checker = UpdateChecker(currentVersion: "1.2.0+build.3", request: { _ in fixture })
    await checker.check()
    #expect(checker.state == .latest(version: "1.2.0"))
}

@MainActor @Test func stableVersionSupersedesCurrentPrerelease() async throws {
    let fixture = try releaseResponse(tag: "v1.2.0")
    let checker = UpdateChecker(currentVersion: "1.2.0-rc.1", request: { _ in fixture })
    await checker.check()
    guard case .available = checker.state else { Issue.record("正式版应高于同版本预览版"); return }
}

@MainActor @Test(arguments: [(true, false), (false, true)])
func unpublishedOrPrereleaseIsNotOffered(flags: (Bool, Bool)) async throws {
    let fixture = try releaseResponse(draft: flags.0, prerelease: flags.1)
    let checker = UpdateChecker(currentVersion: "1.2.0", request: { _ in fixture })
    await checker.check()
    #expect(checker.state == .failed(.noStableRelease))
}

@MainActor @Test(arguments: ["../other", "https://evil.example", "v1.2.0/../../other", "v01.2.0", "v1.2.0-rc.1", "", "v999999999999999999999.1.0"])
func invalidReleaseTagsCannotProduceDownloadLinks(tag: String) async throws {
    let fixture = try releaseResponse(tag: tag)
    let checker = UpdateChecker(currentVersion: "1.0.0", request: { _ in fixture })
    await checker.check()
    #expect(checker.state == .failed(.invalidResponse))
}

@MainActor @Test(arguments: [403, 404, 429, 500])
func releaseHTTPFailureIsActionable(status: Int) async throws {
    let fixture = try releaseResponse(status: status)
    let checker = UpdateChecker(currentVersion: "1.0.0", request: { _ in fixture })
    await checker.check()
    let expected: UpdateCheckError = status == 404 ? .noStableRelease : (status == 403 || status == 429 ? .rateLimited : .server(status))
    #expect(checker.state == .failed(expected))
}

@MainActor @Test func networkFailureAllowsManualRetry() async throws {
    let fixture = try releaseResponse(tag: "v1.2.0")
    var requests = 0
    let checker = UpdateChecker(currentVersion: "1.2.0") { _ in
        requests += 1
        if requests == 1 { throw URLError(.notConnectedToInternet) }
        return fixture
    }
    await checker.check()
    #expect(checker.state == .failed(.network))
    await checker.check()
    #expect(checker.state == .latest(version: "1.2.0"))
}

@MainActor @Test func malformedAndNonHTTPResponsesDoNotReportLatest() async throws {
    let (_, response) = try releaseResponse()
    let checker = UpdateChecker(currentVersion: "1.0.0", request: { _ in (Data("{}".utf8), response) })
    await checker.check()
    #expect(checker.state == .failed(.invalidResponse))
    let nonHTTP = URLResponse(url: URL(string: "https://api.github.com")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    let other = UpdateChecker(currentVersion: "1.0.0", request: { _ in (Data(), nonHTTP) })
    await other.check()
    #expect(other.state == .failed(.invalidResponse))
}

@MainActor @Test func unknownCurrentVersionDoesNotInventUpdateComparison() async {
    let checker = UpdateChecker(currentVersion: "开发版本") { _ in
        Issue.record("版本未知时不应请求网络")
        throw URLError(.badURL)
    }
    await checker.check()
    #expect(checker.state == .failed(.invalidCurrentVersion))
}

@MainActor @Test func concurrentChecksShareInFlightStateWithoutDuplicateRequest() async throws {
    let fixture = try releaseResponse(tag: "v1.2.0")
    var resume: CheckedContinuation<Void, Never>?
    var requests = 0
    let checker = UpdateChecker(currentVersion: "1.2.0") { _ in
        requests += 1
        await withCheckedContinuation { resume = $0 }
        return fixture
    }
    let first = Task { await checker.check() }
    while resume == nil { await Task.yield() }
    #expect(checker.state == .checking)
    await checker.check()
    #expect(requests == 1)
    resume?.resume()
    await first.value
    #expect(checker.state == .latest(version: "1.2.0"))
}
