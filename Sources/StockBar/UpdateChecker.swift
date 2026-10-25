import Foundation
import Combine

enum UpdateCheckError: Equatable {
    case invalidCurrentVersion
    case noStableRelease
    case rateLimited
    case server(Int)
    case invalidResponse
    case network

    var message: String {
        switch self {
        case .invalidCurrentVersion: return "无法识别当前版本，请到发布页核对。"
        case .noStableRelease: return "暂未找到可用的公开正式版，可稍后重试。"
        case .rateLimited: return "GitHub 暂时限制访问，请稍后重试，或直接查看发布页。"
        case .server(let code): return "GitHub 返回错误（\(code)），请稍后重试。"
        case .invalidResponse: return "版本信息无效，请稍后重试，或直接查看发布页。"
        case .network: return "检查失败，请检查网络后重试，或直接查看发布页。"
        }
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case latest(version: String)
        case developmentVersion(latest: String)
        case available(Release)
        case failed(UpdateCheckError)
    }

    typealias Request = (URLRequest) async throws -> (Data, URLResponse)
    static let releasesURL = URL(string: "https://github.com/ZeroClian/stockbar/releases")!
    private static let endpoint = URL(string: "https://api.github.com/repos/ZeroClian/stockbar/releases/latest")!

    let currentVersion: String
    @Published private(set) var state: State = .idle
    private let request: Request

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知",
         request: @escaping Request = { try await URLSession.shared.data(for: $0) }) {
        self.currentVersion = currentVersion
        self.request = request
    }

    func check() async {
        guard state != .checking else { return }
        guard let current = Version(currentVersion) else {
            state = .failed(.invalidCurrentVersion)
            return
        }
        state = .checking
        var urlRequest = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("StockBar", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await request(urlRequest)
            guard let response = response as? HTTPURLResponse else {
                state = .failed(.invalidResponse)
                return
            }
            switch response.statusCode {
            case 200: break
            case 403, 429: state = .failed(.rateLimited); return
            case 404: state = .failed(.noStableRelease); return
            default: state = .failed(.server(response.statusCode)); return
            }
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                state = .failed(.invalidResponse)
                return
            }
            guard !release.draft && !release.prerelease else {
                state = .failed(.noStableRelease)
                return
            }
            // Never trust html_url or asset URLs in the response. Only validated
            // stable version tags may extend this fixed repository's release URL.
            guard let latest = Version(release.tagName), !latest.isPrerelease else {
                state = .failed(.invalidResponse)
                return
            }
            switch current.compare(to: latest) {
            case .orderedAscending:
                let url = Self.releasesURL.appendingPathComponent("tag").appendingPathComponent(release.tagName)
                state = .available(Release(version: latest.display, url: url))
            case .orderedSame:
                state = .latest(version: latest.display)
            case .orderedDescending:
                state = .developmentVersion(latest: latest.display)
            }
        } catch {
            state = .failed(.network)
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }

    private struct Version {
        let components: [Int]
        let isPrerelease: Bool
        let display: String

        init?(_ input: String) {
            // Restrict to SemVer's ASCII alphabet; reject path separators, escapes,
            // invalid leading zeroes and overflowing numeric components.
            let pattern = #"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
            guard input.utf8.count <= 128,
                  let range = input.range(of: pattern, options: .regularExpression),
                  range == input.startIndex..<input.endIndex else { return nil }
            let version = input.hasPrefix("v") ? String(input.dropFirst()) : input
            let withoutBuild = String(version.split(separator: "+", maxSplits: 1)[0])
            let pieces = withoutBuild.split(separator: "-", maxSplits: 1)
            let numbers = pieces[0].split(separator: ".").compactMap { Int($0) }
            guard numbers.count == 3 else { return nil }
            components = numbers
            isPrerelease = pieces.count > 1
            display = withoutBuild
        }

        // The API candidate must be a stable release; current prereleases with
        // the same numeric version are older than that stable release.
        func compare(to stable: Version) -> ComparisonResult {
            for (current, latest) in zip(components, stable.components) {
                if current < latest { return .orderedAscending }
                if current > latest { return .orderedDescending }
            }
            return isPrerelease ? .orderedAscending : .orderedSame
        }
    }
}
