import Foundation
import Observation

/// Compares this build with the latest GitHub release. Result is shown in Settings → About.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case failed(String)
    }
    private(set) var status = Status.idle

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    func check() async {
        guard status != .checking else { return }
        status = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/KaskoYurii/yk-mac-cleaner/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            status = Self.isNewer(latest, than: Self.version) ? .available(version: latest, url: release.html_url) : .upToDate
        } catch {
            status = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    /// Numeric compare, so 1.0.10 > 1.0.9 and 1.1.0 > 1.0.9.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
